import express from 'express';
import { auth, isAdminIfAuthenticated } from '../../middlewares/auth';
import { getLogger, runWithLogger } from '../../observability/requestLoggerContext';
import { handleError, validate } from '../../lib';
import { avatarParamsSchema, deleteParamsSchema, infoQuerySchema, listQuerySchema, postSchema } from './schemas';
import PlaylistRepository from '../../db/MongoDB/PlaylistRepository';
import { meiliPlaylist } from '../../db/meilisearch';
import { Playlist, getAvatarKey } from '../../db/models/Playlist';
import { deleteFromS3, detectContentType, getS3ObjectStream, receiveUpload, uploadToS3 } from '../../lib/file_management';
import { imageUploadTmpDir } from '../../configs';
import { join } from 'node:path';
import { mkdir, rm, unlink } from 'node:fs/promises';
import { createReadStream } from 'node:fs';
import { MongoDB } from '../../db/MongoDB/mongodb';
import PlaylistAudioRepository from '../../db/MongoDB/PlaylistAudioRepository';

const PLAYLIST_NAME_SEPARATOR = '__PLAYLIST_NAME_SEPARATOR__'

const router = express.Router();

router.post('/', auth, isAdminIfAuthenticated, async (req, res) => {
    let log = getLogger().child({ module: 'playlist', route: 'GET /api/playlist/' });

    try {
        log.info('playlist list request received');

        log.debug({ query: req.query });
        const { name } = await runWithLogger(log, () => validate(postSchema, req.query));
        log.info('Input validated');
        log.debug({ name });

        const userId = req.user!.userId
        log.debug({ userId })

        const playlistRepository = new PlaylistRepository();

        const duplicateNameCheck = await runWithLogger(log, () => playlistRepository.getByName(name))
        log.debug({ duplicateNameCheck })
        if (duplicateNameCheck) {
            log.info('provided name already exists')
            return res.status(400).json({ status: 'error', error_code: 'NAME_NOT_UNIQUE' })
        }

        const result = await runWithLogger(log, () => playlistRepository.insert({ name, userId }))
        log.debug({ result })
        if (!result.acknowledged) {
            log.info('failed to create playlist')
            return res.status(500).json({ status: 'error', error_code: 'INTERNAL_ERROR' })
        }

        log.info('playlist created');
        res.status(201).json({ status: 'success' });
    } catch (err) {
        runWithLogger(log, () => handleError(res, err));
    }
});

router.get('/', auth, async (req, res) => {
    let log = getLogger().child({ module: 'playlist', route: 'GET /api/playlist/' });

    try {
        log.info('playlist list request received');

        log.debug({ query: req.query });
        const { page, pageSize, search } = await runWithLogger(log, () => validate(listQuerySchema, req.query));
        log.info('Input validated');
        log.debug({ page, pageSize, search });

        const userId = req.user!.userId;
        log = log.child({ userId, page, pageSize });

        const playlistRepository = new PlaylistRepository();

        let items: Playlist[]
        if (search) {
            log.info('search in meilisearch')

            const searchResult = await meiliPlaylist.search(search, { page, hitsPerPage: pageSize })
            const { totalHits, totalPages, hits } = searchResult
            log.debug({ totalHits, totalPages, hits })

            const ids = hits.map(m => m._id)

            log.info('fetch from playlistRepository')
            items = await runWithLogger(log, () => playlistRepository.getMany(ids))
        } else {
            log.info('fetch from playlistRepository')

            const skip = (page - 1) * pageSize;
            items = await runWithLogger(log, () => playlistRepository.getPage(skip, pageSize))
        }
        log.debug({ count: items.length });

        log.info('Listed playlists');
        res.status(200).json({ status: 'success', data: items });
    } catch (err) {
        runWithLogger(log, () => handleError(res, err));
    }
});

router.get('/info', auth, async (req, res) => {
    let log = getLogger().child({ module: 'playlist', route: 'GET /api/playlist/info' });

    try {
        log.info('playlist info request received');

        log.debug({ query: req.query });
        const { playlistId, name } = await runWithLogger(log, () => validate(infoQuerySchema, req.query));
        log.info('Input validated');
        log.debug({ playlistId, name });

        const userId = req.user!.userId;
        log = log.child({ userId });

        const playlistRepository = new PlaylistRepository();

        log.info('fetch from playlistRepository')

        let playlist
        if (playlistId)
            playlist = await runWithLogger(log, () => playlistRepository.get(playlistId))
        else
            playlist = await runWithLogger(log, () => playlistRepository.getByName(name!))

        log.debug({ playlist });

        if (!playlist) {
            log.info('playlist not found')
            return res.status(404).json({ status: 'error', error_code: 'ALBUM_NOT_FOUND' });
        }

        res.status(200).json({ status: 'success', data: playlist });
    } catch (err) {
        runWithLogger(log, () => handleError(res, err));
    }
});

router.get('/list', auth, async (req, res) => {
    let log = getLogger().child({ module: 'playlist', route: 'GET /api/playlist/list' });

    try {
        log.info('playlist info request received');

        log.debug({ query: req.query });
        const { playlistId, name } = await runWithLogger(log, () => validate(infoQuerySchema, req.query));
        log.info('Input validated');
        log.debug({ playlistId, name });

        const userId = req.user!.userId;
        log = log.child({ userId });

        const playlistRepository = new PlaylistAudioRepository();

        let playlists
        if (name)
            playlists = await runWithLogger(log, () => playlistRepository.getByPlaylistNameForUser(userId, name))
        else
            playlists = await runWithLogger(log, () => playlistRepository.getByPlaylistIdForUser(userId, playlistId!))

        log.debug({ playlists });

        res.status(200).json({ status: 'success', data: playlists });
    } catch (err) {
        runWithLogger(log, () => handleError(res, err));
    }
});

router.get('/avatar/:playlistId', auth, async (req, res) => {
    let log = getLogger().child({ module: 'playlist', route: 'GET /api/playlist/avatar/:playlistId' });

    try {
        log.info('avatar request received');

        log.debug({ params: req.params, query: req.query });
        const { playlistId } = await runWithLogger(log, () => validate(avatarParamsSchema, { ...req.params, ...req.query }));
        log.info('Input validated');
        log.debug({ playlistId });

        const playlistRepository = new PlaylistRepository();

        const playlist = await runWithLogger(log, () => playlistRepository.get(playlistId));
        log.debug({ playlist });
        log.info('Checked playlist ownership');
        if (!playlist) {
            log.info('Rejected avatar request: playlist not found or has no avatar');
            return res.status(404).json({ status: 'error', error_code: 'PLAYLIST_NOT_FOUND' });
        }
        if (!playlist.avatarKey) {
            log.info('Rejected avatar request: playlist not found or has no avatar');
            return res.status(404).json({ status: 'error', error_code: 'AVATAR_NOT_FOUND' });
        }

        const result = await getS3ObjectStream(playlist.avatarKey);
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

router.put('/avatar/:playlistId', auth, isAdminIfAuthenticated, async (req, res) => {
    let log = getLogger().child({ module: 'playlist', route: 'GET /api/playlist/avatar/:playlistId' });

    try {
        log.info('avatar request received');

        log.debug({ params: req.params });
        const { playlistId } = await runWithLogger(log, () => validate(avatarParamsSchema, { ...req.params }));
        log.info('Input validated');
        log.debug({ playlistId });

        const playlistRepository = new PlaylistRepository();

        const playlist = await runWithLogger(log, () => playlistRepository.get(playlistId));
        log.debug({ playlist });
        log.info('Checked playlist ownership');
        if (!playlist) {
            log.info('Rejected avatar request: playlist not found or has no avatar');
            return res.status(404).json({ status: 'error', message: 'Playlist not found' });
        }

        // ------------------------------------------------------------------------- make the temporary directory
        log.info('make the temporary directory')

        const jobDir = join(imageUploadTmpDir, 'avatars', playlistId)
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

            if (playlist.avatarKey) {
                log.info('deleting old avatar')
                try { await runWithLogger(log, () => deleteFromS3(playlist.avatarKey!)) } catch (err) { log.warn({ err }, 'failed to delete old avatar') }
            }

            const key = getAvatarKey(playlistId)
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

router.delete('/:playlistId', auth, isAdminIfAuthenticated, async (req, res) => {
    let log = getLogger().child({ module: 'playlist', route: 'DELETE /api/playlist/:playlistId' });

    let db: MongoDB | undefined = undefined
    try {
        log.info('Playlist delete request received');

        log.debug({ params: req.params });
        const { playlistId } = await runWithLogger(log, () => validate(deleteParamsSchema, req.params));
        log.info('Input validated');
        log.debug({ playlistId });

        db = MongoDB.getDbInstance()

        // sessions are set after in case s3 storage deletion process gets interrupted
        const session = await db.startTransaction()

        const playlistRepository = new PlaylistRepository();
        playlistRepository.setTransactionSession(session)

        const playlist = await runWithLogger(log, () => playlistRepository.get(playlistId));
        log.debug({ playlist });
        if (!playlist) {
            log.info('Rejected playlist delete request: playlist not found');
            res.status(404).json({ status: 'error', message: 'Playlist not found' });
            await db.abortTransaction()
            return
        }

        const r = await runWithLogger(log, () => playlistRepository.unsafeUpdate(playlistId, { name: `deletionQueued${PLAYLIST_NAME_SEPARATOR}${playlist.name}`, deletionQueued: true }));
        log.debug({ updateResult: r });
        if (!r.acknowledged || r.matchedCount) {
            log.error({ updateResult: r }, 'Failed to mark playlist temporary before delete');
            res.status(500).json({ status: 'error', message: 'Error deleting playlist' });
            await db.abortTransaction()
            return
        }
        log.info('Marked playlist temporary before delete');

        const promises = []
        if (playlist?.avatarKey) {
            log.info('Deleting playlist file from storage');
            promises.push(runWithLogger(log, () => deleteFromS3(playlist.avatarKey!)))
            log.debug({ key: playlist.avatarKey });
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

        const rr = await runWithLogger(log, () => playlistRepository.delete(playlistId));
        log.debug({ deleteResult: rr });
        if (!rr.acknowledged) {
            log.error({ deleteResult: rr }, 'Failed to delete playlist record from DB');
            await db.abortTransaction()
            res.status(500).json({ status: 'error', message: 'Error deleting playlist' });
            return
        }
        log.info('Deleted playlist record in DB')

        await db.commitTransaction()

        log.info('playlist deleted successfully');
        res.status(204).json({ status: 'success' });
    } catch (err) {
        runWithLogger(log, () => handleError(res, err));
        await db?.abortTransaction()
    }
});

export { router as playlistRoutes };
