import express from 'express';
import { auth, isAdminIfAuthenticated } from '../../middlewares/auth';
import { getLogger, runWithLogger } from '../../observability/requestLoggerContext';
import { handleError, validate } from '../../lib';
import { albumIdArtistNameSchema, avatarParamsSchema, deleteParamsSchema, infoQuerySchema, listQuerySchema, postSchema } from './schemas';
import AlbumRepository from '../../db/MongoDB/AlbumRepository';
import { meiliAlbum } from '../../db/meilisearch';
import { Album, getAvatarKey } from '../../db/models/Album';
import { deleteFromS3, detectContentType, getS3ObjectStream, receiveUpload, uploadToS3 } from '../../lib/file_management';
import { imageUploadTmpDir } from '../../configs';
import { join } from 'node:path';
import { mkdir, rm, unlink } from 'node:fs/promises';
import { createReadStream } from 'node:fs';
import { MongoDB } from '../../db/MongoDB/mongodb';
import ArtistAlbumAudioRepository from '../../db/MongoDB/ArtistAlbumAudioRepository';
import AudioRepository from '../../db/MongoDB/AudioRepository';
import { WithId } from '../../db/common_schemas';
import { Audio } from '../../db/models/Audio';
import { AlbumController } from '../../controllers/AlbumController';
import { AudioController } from '../../controllers/AudioController';
import { ArtistAlbumAudioController } from '../../controllers/ArtistAlbumAudioController';

const router = express.Router();

router.post('/', auth, isAdminIfAuthenticated, async (req, res) => {
    let log = getLogger().child({ module: 'album', route: 'GET /api/album/' });

    try {
        log.info('album list request received');

        log.debug({ query: req.query });
        const { name } = await runWithLogger(log, () => validate(postSchema, req.query));
        log.debug({ name });
        log.info('Input validated');

        const albumId = await runWithLogger(log, () => new AlbumController().create(name))
        log.debug({ albumId });

        log.info('album created');
        res.status(201).json({ status: 'success', data: { albumId } });
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

/**
 * if name is provided, client will receive many albums
 */
router.get('/info', auth, async (req, res) => {
    let log = getLogger().child({ module: 'album', route: 'GET /api/album/info' });

    try {
        log.info('album info request received');

        log.debug({ query: req.query });
        const { albumId, name } = await runWithLogger(log, () => validate(infoQuerySchema, req.query));
        log.info('Input validated');
        log.debug({ albumId, name });

        const userId = req.user!.userId;
        log = log.child({ userId });

        const albumRepository = new AlbumRepository();

        log.info('fetch from albumRepository')

        let album
        if (albumId)
            album = await runWithLogger(log, () => albumRepository.get(albumId))
        else
            album = await runWithLogger(log, () => albumRepository.getByName(name!))

        log.debug({ album });

        if (!album) {
            log.info('album not found')
            return res.status(404).json({ status: 'error', error_code: 'ALBUM_NOT_FOUND' });
        }

        res.status(200).json({ status: 'success', data: album });
    } catch (err) {
        runWithLogger(log, () => handleError(res, err));
    }
});

router.patch('/name', auth, isAdminIfAuthenticated, async (req, res) => {
    let log = getLogger().child({ module: 'album', route: 'PATCH /api/album/name' });

    let db: MongoDB | undefined = undefined
    try {
        log.info('audio approve request received');

        log.debug({ body: req.body });
        const { albumId, albumName } = await runWithLogger(log, () => validate(albumIdArtistNameSchema, req.body))
        log.debug({ albumId, albumName });
        log.info('input validated');

        const userId = req.user!.userId
        log.debug({ userId });

        db = MongoDB.getDbInstance()
        const session = await db.startTransaction()

        const albumRepository = new AlbumRepository()
        albumRepository.setTransactionSession(session)

        const audioRepository = new AudioRepository()
        audioRepository.setTransactionSession(session)

        const artistAlbumAudioRepository = new ArtistAlbumAudioRepository()
        artistAlbumAudioRepository.setTransactionSession(session)

        const album = await runWithLogger(log, () => albumRepository.get(albumId));
        log.debug({ album });
        if (!album) {
            log.info('album not found');
            return res.status(400).json({ status: 'error', error_code: 'ALBUM_NOT_FOUND' });
        }

        if (album.name === albumName) {
            db.commitTransaction()
            return res.status(200).json({ status: 'success' })
        }

        const updateAlbumResult = await runWithLogger(log, () => albumRepository.unsafeUpdate(album._id.toString(), { name: albumName }));
        log.debug({ updateAlbumResult });
        if (updateAlbumResult) {
            log.info('failed to update album');
            return res.status(500).json({ status: 'error', error_code: 'INTERNAL_ERROR' });
        }

        const updateMeiliAlbumResult = await runWithLogger(log, () => meiliAlbum.updateBy({ _id: albumId }, { name: albumName }))
        log.debug({ updateMeiliAlbumResult });
        if (updateMeiliAlbumResult.task?.status !== 'succeeded') {
            log.info("failed to update albumNames in meilisearch in album collection");
            await db?.abortTransaction()
            return res.status(500).json({ status: 'error', error_code: 'INTERNAL_ERROR' });
        }

        await db.commitTransaction()

        return res.status(200).json({ status: 'success' })
    } catch (err) {
        try { await db?.abortTransaction() } catch (_) { }

        runWithLogger(log, () => handleError(res, err))
    }
})

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

        let avatarKey = album.avatarKey
        if (!avatarKey && album.doNotUseFirstAudioCoverArt !== true) {
            log.info('trying to use first cover art of the first audio of this album audios as avatar');

            const artistAlbumAudioRepository = new ArtistAlbumAudioRepository();

            const audio = await runWithLogger(log, () => artistAlbumAudioRepository.getManyAudioByAlbumId(album._id.toString(), 0, 1))
            log.debug({ audio });

            avatarKey = audio[0]?.coverArtKey
        }

        if (!avatarKey) {
            log.info('Rejected avatar request: album not found or has no avatar');
            return res.status(404).json({ status: 'error', error_code: 'AVATAR_NOT_FOUND' });
        }

        const result = await getS3ObjectStream(avatarKey);
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

            const tmpUpdateResult = await runWithLogger(log, () => albumRepository.unsafeUpdate(albumId, { temporaryAvatar: true }));
            log.debug({ tmpUpdateResult });
            if (!tmpUpdateResult) {
                log.info('failed to update the album');
                return res.status(500).json({ status: 'error', error_code: 'INTERNAL_ERROR' });
            }

            const key = getAvatarKey(albumId)
            await runWithLogger(log, () => uploadToS3(createReadStream(inputPath), key, contentType.mimeType, true))

            const updateResult = await runWithLogger(log, () => albumRepository.unsafeUpdate(albumId, { avatarKey: key, temporaryAvatar: true }));
            log.debug({ updateResult });
            if (!updateResult) {
                log.info('failed to update the album');
                return res.status(500).json({ status: 'error', error_code: 'INTERNAL_ERROR' });
            }
        } catch (err) {
            log.error({ err }, 'caught an error while trying to upload files')
            cleanup()
            throw err
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
        const { albumId, shouldDeleteAudios } = await runWithLogger(log, () => validate(deleteParamsSchema, req.params));
        log.info('Input validated');
        log.debug({ albumId, shouldDeleteAudios });

        db = MongoDB.getDbInstance()
        const session = await db.startTransaction()

        const artistAlbumAudio = new ArtistAlbumAudioRepository()
        artistAlbumAudio.setTransactionSession(session)

        const audioRepository = new AudioRepository()
        audioRepository.setTransactionSession(session)

        const albumRepository = new AlbumRepository()
        audioRepository.setTransactionSession(session)

        if (shouldDeleteAudios === true) {
            let audios: WithId<Audio>[] = [], skip = 0
            do {
                audios = await runWithLogger(log, () => new ArtistAlbumAudioController().getAlbumAudios(albumId, skip, 10, artistAlbumAudio))
                if (audios.length === 0) break;

                for (const audio of audios)
                    await runWithLogger(log, () => new AudioController().delete(audio, audioRepository))

                skip += audios.length
            } while (audios.length !== 0);
        }

        await runWithLogger(log, () => new AlbumController().delete(albumId, albumRepository));

        await db.commitTransaction()

        log.info('album deleted successfully');
        res.status(204).json({ status: 'success' });
    } catch (err) {
        runWithLogger(log, () => handleError(res, err));
        await db?.abortTransaction()
    }
});

export { router as albumRoutes };
