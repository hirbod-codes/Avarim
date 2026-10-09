import express from 'express';
import { generalRateLimiter } from '../../middlewares/rateLimiting';
import { UserRepository } from '../../db/MongoDB/UserRepository';
import { auth } from '../../middlewares/auth';
import { Upload } from '@aws-sdk/lib-storage';
import { BUCKET_NAME } from '../../configs';
import { DeleteObjectCommand, GetObjectCommand } from '@aws-sdk/client-s3';
import { s3 } from '../..';
import { getLogger, runWithLogger } from '../../observability/requestLoggerContext';
import { handleError, validate } from '../../lib';
import { fetchAvatarSchema, preferencesSchema, uploadAvatarSchema } from './schemas';
import UsageRepository from '../../db/MongoDB/UsageRepository';
import { deleteFromS3 } from '../../lib/file_management';
import { MongoDB } from '../../db/MongoDB/mongodb';

const router = express.Router();

router.use(auth)

router.get('/info', async (req, res) => {
    const log = getLogger().child({ module: 'user', route: 'POST /api/user/info' });

    try {
        log.info('user info request received')

        const userRepository = new UserRepository()

        const result = await runWithLogger(log, () => userRepository.get(req.user!.userId))
        if (!result) {
            log.info('User not found')
            return res.status(401).send()
        }
        delete result?.password
        log.debug({ result })
        log.info('User found')

        res.status(200).json({ status: 'success', data: result })
    } catch (err) {
        runWithLogger(log, () => handleError(res, err))
    }
})

router.post('/preferences', async (req, res) => {
    const log = getLogger().child({ module: 'user', route: 'POST /api/user/preferences' });

    try {
        log.info('update user preferences request received')

        const { language, calendar, timezone } = await runWithLogger(log, () => validate(preferencesSchema, req.body ?? {}))
        log.debug({ language, calendar, timezone })

        const userId = req.user!.userId
        log.debug({ userId })

        const ur = new UserRepository()

        const updateResult = await runWithLogger(log, () => ur.unsafeUpdate(userId, { language, calendar, timezone }));
        log.debug({ updateResult })
        if (updateResult !== true) {
            log.warn('system failed to update user\'s preferences');
            return res.status(500).json({ status: 'error', error_code: 'UPDATE_FAILED' })
        }

        return res.status(204).json({ status: 'success' })
    } catch (err) {
        runWithLogger(log, () => handleError(res, err))
    }
})

router.post('/avatar', async (req, res) => {
    const log = getLogger().child({ module: 'user', route: 'POST /api/user/avatar' });

    try {
        log.info('upload user avatar request received')

        const { fileName } = await runWithLogger(log, () => validate(uploadAvatarSchema, req.query ?? {}))
        log.debug({ fileName })

        const userId = req.user!.userId
        log.debug({ userId })

        const avatarKey = `user/avatar/${userId}`
        log.debug({ avatarKey })

        const userRepository = new UserRepository()

        const userUnsafeUpdate = await runWithLogger(log, () => userRepository.unsafeUpdate(userId, { avatarKey, temporaryAvatar: true }))
        log.debug({ userUnsafeUpdate })
        if (userUnsafeUpdate !== true) {
            log.error('failure while trying to update user record with avatar key and set temporary avatar field to true')
            return res.status(500).json({ status: 'error', error_code: 'UPLOAD_FAILED' });
        }

        let uploadImage: Upload | null = null
        try {
            uploadImage = new Upload({
                client: s3,
                params: {
                    Bucket: BUCKET_NAME,
                    Key: avatarKey,
                    Body: req
                }
            });
            await uploadImage.done();
        } catch (err) {
            log.error(err, 'failure while trying to upload avatar to the cloud s3 storage, aborting...')

            try { await uploadImage?.abort(); } catch (_) { }

            return res.status(500).json({ status: 'error', error_code: 'UPLOAD_FAILED' });
        }
        log.info('avatar uploaded')

        const userUnsafeUpdate2 = await runWithLogger(log, () => userRepository.unsafeUpdate(userId, { temporaryAvatar: false }))
        log.debug({ userUnsafeUpdate2 })
        if (userUnsafeUpdate2 !== true) {
            log.error('failure while trying to update user record and set temporary avatar field to false')

            try { await uploadImage?.abort(); } catch (_) { }

            return res.status(500).json({ status: 'error', error_code: 'UPLOAD_FAILED' });
        }

        res.status(201).json({ status: 'success' })
    } catch (err) {
        runWithLogger(log, () => handleError(res, err))
    }
})

router.get('/avatar', async (req, res) => {
    const log = getLogger().child({ module: 'user', route: 'GET /api/user/avatar' });

    try {
        log.info('user avatar delete request received')

        let { download: downloadStr } = await runWithLogger(log, () => validate(fetchAvatarSchema, req.query ?? {}))
        const download = downloadStr === 'true'
        log.debug({ download })

        const userId = req.user!.userId
        log.debug({ userId })

        const userRepository = new UserRepository()

        const user = await runWithLogger(log, () => userRepository.get(userId))
        log.debug({ user })
        if (!user) {
            log.info('user not found')
            return res.status(404).json({ status: 'error', error_code: 'USER_NOT_FOUND' });
        }

        if (!user.avatarKey || user.temporaryAvatar || user?.avatarDeletionQueued === true) {
            log.info('avatar not found')
            return res.status(404).json({ status: 'error', error_code: 'AVATAR_NOT_FOUND' });
        }
        log.info('user fetched')

        const s3Result = await s3.send(new GetObjectCommand({
            Bucket: BUCKET_NAME,
            Key: user.avatarKey,
            ResponseContentDisposition: download ? `attachment; filename="user_avatar.jpg"` : undefined,
        }));
        log.debug({ s3ResultMetaData: s3Result.Metadata, s3ResultContentType: s3Result.ContentType, s3ResultContentLength: s3Result.ContentLength })

        const stream = s3Result.Body;
        if (stream === undefined || stream === null) {
            log.warn('avatar not found in the cloud s3 storage')
            return res.status(404).json({ status: 'error', error_code: 'AVATAR_NOT_FOUND' });
        }

        res.setHeader("Content-Type", s3Result.ContentType || "image/jpg");
        res.setHeader("Content-Length", s3Result.ContentLength ?? "");

        res.status(200);
        (stream as any).pipe(res);

    } catch (err) {
        runWithLogger(log, () => handleError(res, err))
    }
})

router.delete('/avatar', async (req, res) => {
    const log = getLogger().child({ module: 'user', route: 'DELETE /api/user/avatar' });

    let db: MongoDB | undefined = undefined
    try {
        log.info('user avatar delete request received')

        const userId = req.user!.userId

        db = MongoDB.getDbInstance()

        // sessions are set after in case s3 storage deletion process gets interrupted
        const session = await db.startTransaction()

        const userRepository = new UserRepository()
        userRepository.setTransactionSession(session)

        const user = await runWithLogger(log, () => userRepository.get(userId))
        log.debug({ user })
        if (!user) {
            log.info('user not found')
            await db.abortTransaction()
            res.status(404).json({ message: 'User not found' });
            return
        }
        if (!user.avatarKey || user.temporaryAvatar) {
            log.info('user avatar not found')
            await db.abortTransaction()
            res.status(404).json({ message: 'Avatar not found' });
            return
        }

        const r = await runWithLogger(log, () => userRepository.unsafeUpdate(userId, { avatarDeletionQueued: true }));
        log.debug({ updateResult: r });
        if (!r) {
            log.error({ updateResult: r }, 'Failed to mark audio temporary before delete');
            await db.abortTransaction()
            res.status(500).json({ status: 'error', message: 'Error deleting audio' });
            return
        }
        log.info('Marked audio temporary before delete');

        log.info('deleting user avatar...')
        if (user.avatarKey) {
            await runWithLogger(log, () => deleteFromS3(user.avatarKey!))
            log.info('deleted user avatar')
        }

        console.log("Deleting avatar in DB...");
        const result = await runWithLogger(log, () => userRepository.unsafeUpdate(userId, { avatarKey: undefined, temporaryAvatar: false, avatarDeletionQueued: false }))
        log.debug({ result })
        if (result !== true) {
            log.warn('failed to delete user avatar from MongoDB')
            await db.abortTransaction()
            res.status(500).send()
            return
        }
        console.log("Deleted avatar in DB");

        await db.commitTransaction()

        log.info('avatar deleted successfully');
        return res.status(200).send();
    } catch (err) {
        await db?.abortTransaction()
        runWithLogger(log, () => handleError(res, err))
    }
})

router.get('/usage', async (req, res) => {
    const log = getLogger().child({ module: 'user', route: 'GET /api/user/usage' });

    try {
        log.info('user usage request received')

        const usageRepository = new UsageRepository()

        const result = await runWithLogger(log, () => usageRepository.getByUserId(req.user!.userId))
        log.debug({ result })
        if (!result) {
            log.info('User not found')
            return res.status(401).send()
        }
        log.info('User found')

        res.status(200).json({ status: 'success', data: result })
    } catch (err) {
        runWithLogger(log, () => handleError(res, err))
    }
})

export { router as userRoutes };
