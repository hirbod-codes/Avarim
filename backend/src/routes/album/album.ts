import express from 'express';
import { auth, isAdminIfAuthenticated } from '../../middlewares/auth';
import { getLogger, runWithLogger } from '../../observability/requestLoggerContext';
import { handleError, validate } from '../../lib';
import { avatarParamsSchema, deleteParamsSchema, listQuerySchema, postSchema } from './schemas';
import AlbumRepository from '../../db/MongoDB/AlbumRepository';
import { meiliAlbum } from '../../db/meilisearch';
import { Album, getAvatarKey } from '../../db/models/Album';
import { deleteFromS3, detectContentType, getS3ObjectStream, receiveUpload, uploadToS3 } from '../../lib/file_management';
import { imageUploadTmpDir } from '../../configs';
import { join } from 'node:path';
import { mkdir, rm, unlink } from 'node:fs/promises';
import { createReadStream } from 'node:fs';
import { MongoDB } from '../../db/MongoDB/mongodb';

const ALBUM_NAME_SEPARATOR = '__ALBUM_NAME_SEPARATOR__'

const router = express.Router();

router.post('/', auth, isAdminIfAuthenticated, async (req, res) => {
    let log = getLogger().child({ module: 'album', route: 'GET /api/album/' });

    try {
        log.info('album list request received');

        log.debug({ query: req.query });
        const { name } = await runWithLogger(log, () => validate(postSchema, req.query));
        log.info('Input validated');
        log.debug({ name });

        const albumRepository = new AlbumRepository();

        const duplicateNameCheck = await runWithLogger(log, () => albumRepository.getByName(name))
        log.debug({ duplicateNameCheck })
        if (duplicateNameCheck) {
            log.info('provided name already exists')
            return res.status(400).json({ status: 'error', error_code: 'NAME_NOT_UNIQUE' })
        }

        const result = await runWithLogger(log, () => albumRepository.insert({ name }))
        log.debug({ result })
        if (!result.acknowledged) {
            log.info('failed to create album')
            return res.status(500).json({ status: 'error', error_code: 'INTERNAL_ERROR' })
        }

        log.info('album created');
        res.status(201).json({ status: 'success' });
    } catch (err) {
        runWithLogger(log, () => handleError(res, err));
    }
});

router.get('/', auth, async (req, res) => {
    let log = getLogger().child({ module: 'album', route: 'GET /api/album/' });

    try {
        log.info('album list request received');

        log.debug({ query: req.query });
        const { page, pageSize, search } = await runWithLogger(log, () => validate(listQuerySchema, req.query));
        log.info('Input validated');
        log.debug({ page, pageSize, search });

        const userId = req.user!.userId;
        log = log.child({ userId, page, pageSize });

        const albumRepository = new AlbumRepository();

        let items: Album[]
        if (search) {
            log.info('search in meilisearch')

            const searchResult = await meiliAlbum.search(search, { page, hitsPerPage: pageSize })
            const { totalHits, totalPages, hits } = searchResult
            log.debug({ totalHits, totalPages, hits })

            const ids = hits.map(m => m._id)

            log.info('fetch from albumRepository')
            items = await runWithLogger(log, () => albumRepository.getMany(ids))
        } else {
            log.info('fetch from albumRepository')

            const skip = (page - 1) * pageSize;
            items = await runWithLogger(log, () => albumRepository.getPage(skip, pageSize))
        }
        log.debug({ count: items.length });

        log.info('Listed albums');
        res.status(200).json({ status: 'success', data: items });
    } catch (err) {
        runWithLogger(log, () => handleError(res, err));
    }
});

router.get('/avatar/:albumId', auth, async (req, res) => {
    let log = getLogger().child({ module: 'album', route: 'GET /api/album/avatar/:albumId' });

    try {
        log.info('avatar request received');

        log.debug({ params: req.params, query: req.query });
        const { albumId } = await runWithLogger(log, () => validate(avatarParamsSchema, { ...req.params, ...req.query }));
        log.info('Input validated');
        log.debug({ albumId });

        const albumRepository = new AlbumRepository();

        const album = await runWithLogger(log, () => albumRepository.get(albumId));
        log.debug({ album });
        log.info('Checked album ownership');
        if (!album) {
            log.info('Rejected avatar request: album not found or has no avatar');
            return res.status(404).json({ status: 'error', error_code: 'ALBUM_NOT_FOUND' });
        }
        if (!album.avatarKey) {
            log.info('Rejected avatar request: album not found or has no avatar');
            return res.status(404).json({ status: 'error', error_code: 'AVATAR_NOT_FOUND' });
        }

        const result = await getS3ObjectStream(album.avatarKey);
        log.debug({ result });
        if (!result) {
            log.warn('avatar object has no body');
            return res.status(404).json({ status: 'error', error_code: 'COVER_ART_NOT_FOUND' });
        }

        const { stream, contentLength, contentType } = result
        log.debug({ stream, contentLength, contentType });

        if (!stream) {
            log.warn('avatar object has no body');
            return res.status(404).json({ status: 'error', error_code: 'COVER_ART_NOT_FOUND' });
        }

        res.setHeader('Accept-Ranges', 'bytes');
        res.setHeader('Content-Type', contentType || 'application/octet-stream');
        res.status(200);
        res.setHeader('Content-Length', contentLength ?? '');

        log.info('Streaming avatar to client');
        stream.pipe(res);
    } catch (err) {
        runWithLogger(log, () => handleError(res, err));
    }
});

router.put('/avatar/:albumId', auth, isAdminIfAuthenticated, async (req, res) => {
    let log = getLogger().child({ module: 'album', route: 'GET /api/album/avatar/:albumId' });

    try {
        log.info('avatar request received');

        log.debug({ params: req.params });
        const { albumId } = await runWithLogger(log, () => validate(avatarParamsSchema, { ...req.params }));
        log.info('Input validated');
        log.debug({ albumId });

        const albumRepository = new AlbumRepository();

        const album = await runWithLogger(log, () => albumRepository.get(albumId));
        log.debug({ album });
        log.info('Checked album ownership');
        if (!album) {
            log.info('Rejected avatar request: album not found or has no avatar');
            return res.status(404).json({ status: 'error', message: 'Album not found' });
        }

        // ------------------------------------------------------------------------- make the temporary directory
        log.info('make the temporary directory')

        const jobDir = join(imageUploadTmpDir, 'avatars', albumId)
        await mkdir(jobDir, { recursive: true });
        log.debug({ jobDir });
        log.info('Created job scratch directory');

        const cleanupPaths: string[] = [];
        const cleanup = async () => {
            log.debug({ cleanupPaths, jobDir });
            log.info('Cleaning up temp files');
            await Promise.all(cleanupPaths.map((p) => unlink(p).catch(() => { })));
            await rm(jobDir, { recursive: true, force: true }).catch(() => { });
        };

        try {
            // ------------------------------------------------------------------------- store upload stream on disk
            log.info('store upload stream on disk')

            const { path: inputPath, size: inputSize } = await runWithLogger(log, () => receiveUpload(req, undefined, jobDir))
            cleanupPaths.push(inputPath)
            log.debug({ inputSize, inputPath })
            log.info('Upload received and stored to disk')

            const contentType = await runWithLogger(log, () => detectContentType(inputPath))
            log.debug({ contentType })

            if (album.avatarKey) {
                log.info('deleting old avatar')
                try { await runWithLogger(log, () => deleteFromS3(album.avatarKey!)) } catch (err) { log.warn({ err }, 'failed to delete old avatar') }
            }

            const key = getAvatarKey(albumId)
            await runWithLogger(log, () => uploadToS3(createReadStream(inputPath), key, contentType.mimeType, true))
        } catch (err) {
            log.error({ err }, 'caught an error while trying to upload files')
            cleanup()
        }

        res.status(201).json({ status: 'success' })
    } catch (err) {
        runWithLogger(log, () => handleError(res, err));
    }
});

router.delete('/:albumId', auth, isAdminIfAuthenticated, async (req, res) => {
    let log = getLogger().child({ module: 'album', route: 'DELETE /api/album/:albumId' });

    let db: MongoDB | undefined = undefined
    try {
        log.info('Album delete request received');

        log.debug({ params: req.params });
        const { albumId } = await runWithLogger(log, () => validate(deleteParamsSchema, req.params));
        log.info('Input validated');
        log.debug({ albumId });

        db = MongoDB.getDbInstance()

        // sessions are set after in case s3 storage deletion process gets interrupted
        const session = await db.startTransaction()

        const albumRepository = new AlbumRepository();
        albumRepository.setTransactionSession(session)

        const album = await runWithLogger(log, () => albumRepository.get(albumId));
        log.debug({ album });
        if (!album) {
            log.info('Rejected album delete request: album not found');
            res.status(404).json({ status: 'error', message: 'Album not found' });
            await db.abortTransaction()
            return
        }

        const r = await runWithLogger(log, () => albumRepository.unsafeUpdate(albumId, { name: `deletionQueued${ALBUM_NAME_SEPARATOR}${album.name}`, deletionQueued: true }));
        log.debug({ updateResult: r });
        if (!r.acknowledged || r.matchedCount) {
            log.error({ updateResult: r }, 'Failed to mark album temporary before delete');
            res.status(500).json({ status: 'error', message: 'Error deleting album' });
            await db.abortTransaction()
            return
        }
        log.info('Marked album temporary before delete');

        const promises = []
        if (album?.avatarKey) {
            log.info('Deleting album file from storage');
            promises.push(runWithLogger(log, () => deleteFromS3(album.avatarKey!)))
            log.debug({ key: album.avatarKey });
        }

        const results = await Promise.allSettled(promises)
        log.debug({ results })
        const rejected = results.filter((r): r is PromiseRejectedResult => r.status === 'rejected');
        log.info(
            {
                fulfilledCount: results.length - rejected.length,
                rejectedCount: rejected.length,
                ...(rejected.length > 0 && { errors: rejected.map(r => r.reason instanceof Error ? r.reason.message : r.reason) }),
            },
            'handled all the object deletions from s3 storage'
        );

        if (rejected.length > 0) {
            log.info({ rejectedLength: rejected.length }, `failed to delete objects in s3 storage`)
            res.status(500).json({ status: 'error', error_code: 'INTERNAL_ERROR' })
            await db.abortTransaction()
            return
        }

        const rr = await runWithLogger(log, () => albumRepository.delete(albumId));
        log.debug({ deleteResult: rr });
        if (!rr.acknowledged) {
            log.error({ deleteResult: rr }, 'Failed to delete album record from DB');
            await db.abortTransaction()
            res.status(500).json({ status: 'error', message: 'Error deleting album' });
            return
        }
        log.info('Deleted album record in DB')

        await db.commitTransaction()

        log.info('album deleted successfully');
        res.status(204).json({ status: 'success' });
    } catch (err) {
        runWithLogger(log, () => handleError(res, err));
        await db?.abortTransaction()
    }
});

export { router as albumRoutes };
