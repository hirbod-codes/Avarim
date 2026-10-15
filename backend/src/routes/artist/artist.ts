import express from 'express';
import { auth, isAdminIfAuthenticated } from '../../middlewares/auth';
import { getLogger, runWithLogger } from '../../observability/requestLoggerContext';
import { handleError, validate } from '../../lib';
import { albumListQuerySchema, avatarParamsSchema, deleteParamsSchema, infoQuerySchema, isNameUnique, listQuerySchema, postSchema } from './schemas';
import ArtistRepository from '../../db/MongoDB/ArtistRepository';
import { meiliArtist } from '../../db/meilisearch';
import { Artist, getAvatarKey, getBannerKey } from '../../db/models/Artist';
import { deleteFromS3, detectContentType, getS3ObjectStream, receiveUpload, uploadToS3 } from '../../lib/file_management';
import { imageUploadTmpDir } from '../../configs';
import { join } from 'node:path';
import { mkdir, rm, unlink } from 'node:fs/promises';
import { createReadStream } from 'node:fs';
import { MongoDB } from '../../db/MongoDB/mongodb';
import ArtistAlbumAudioRepository from '../../db/MongoDB/ArtistAlbumAudioRepository';

const router = express.Router();

const ARTIST_NAME_SEPARATOR = '__ARTIST_NAME_SEPARATOR__'

router.get('/is_title_unique', auth, isAdminIfAuthenticated, async (req, res) => {
    let log = getLogger().child({ module: 'artist', route: 'Get /api/artist/is_title_unique' });

    try {
        log.info('artist title uniqueness check request received');

        log.debug({ query: req.query });
        const { name } = await runWithLogger(log, () => validate(isNameUnique, req.query))
        log.info('input validated');
        log.debug({ name });

        const userId = req.user!.userId
        log = log.child({ userId });

        const artistRepository = new ArtistRepository()

        log.info('checking whether title already exists')
        const artist = await runWithLogger(log, () => artistRepository.getByName(name));
        log.debug({ artist });
        if (artist) {
            log.info('Rejected artist upload: title already exists');
            return res.status(400).json({ status: 'error', error_code: 'NAME_NOT_UNIQUE' });
        }

        res.status(204).json({ status: 'success', data: true })
    } catch (err) {
        runWithLogger(log, () => handleError(res, err))
    }
})

router.post('/', auth, isAdminIfAuthenticated, async (req, res) => {
    let log = getLogger().child({ module: 'artist', route: 'GET /api/artist/' });

    try {
        log.info('artist list request received');

        log.debug({ query: req.query });
        const { name } = await runWithLogger(log, () => validate(postSchema, req.query));
        log.info('Input validated');
        log.debug({ name });

        const artistRepository = new ArtistRepository();

        const duplicateNameCheck = await runWithLogger(log, () => artistRepository.getByName(name))
        log.debug({ duplicateNameCheck })
        if (duplicateNameCheck) {
            log.info('provided name already exists')
            return res.status(400).json({ status: 'error', error_code: 'NAME_NOT_UNIQUE' })
        }

        const result = await runWithLogger(log, () => artistRepository.insert({ name }))
        log.debug({ result })
        if (!result.acknowledged) {
            log.info('failed to create artist')
            return res.status(500).json({ status: 'error', error_code: 'INTERNAL_ERROR' })
        }

        const meiliResult = await runWithLogger(log, () => meiliArtist.create({ name }))
        log.debug({ meiliResult })
        if (meiliResult.status !== 'succeeded') {
            log.warn('Failed to create artist')
            return res.status(500).json({ status: 'error', error_code: 'INTERNAL_ERROR' })
        }

        log.info('artist created');
        res.status(201).json({ status: 'success' });
    } catch (err) {
        runWithLogger(log, () => handleError(res, err));
    }
});

router.get('/', auth, async (req, res) => {
    let log = getLogger().child({ module: 'artist', route: 'GET /api/artist/' });

    try {
        log.info('artist list request received');

        log.debug({ query: req.query });
        const { page, pageSize, search } = await runWithLogger(log, () => validate(listQuerySchema, req.query));
        log.info('Input validated');
        log.debug({ page, pageSize, search });

        const userId = req.user!.userId;
        log = log.child({ userId, page, pageSize });

        const artistRepository = new ArtistRepository();

        let items: Artist[]
        if (search) {
            log.info('search in meilisearch')

            const searchResult = await meiliArtist.search(search, { page, hitsPerPage: pageSize })
            const { totalHits, totalPages, hits } = searchResult
            log.debug({ totalHits, totalPages, hits })

            const ids = hits.map(m => m._id)

            log.info('fetch from artistRepository')
            items = await runWithLogger(log, () => artistRepository.getMany(ids))
        } else {
            log.info('fetch from artistRepository')

            const skip = (page - 1) * pageSize;
            items = await runWithLogger(log, () => artistRepository.getPage(skip, pageSize))
        }
        log.debug({ count: items.length });

        log.info('Listed artists');
        res.status(200).json({ status: 'success', data: items });
    } catch (err) {
        runWithLogger(log, () => handleError(res, err));
    }
});

router.get('/info', auth, async (req, res) => {
    let log = getLogger().child({ module: 'artist', route: 'GET /api/artist/info' });

    try {
        log.info('artist info request received');

        log.debug({ query: req.query });
        const { artistId, name } = await runWithLogger(log, () => validate(infoQuerySchema, req.query));
        log.info('Input validated');
        log.debug({ artistId, name });

        const userId = req.user!.userId;
        log = log.child({ userId });

        const artistRepository = new ArtistRepository();

        log.info('fetch from artistRepository')

        let artist
        if (artistId)
            artist = await runWithLogger(log, () => artistRepository.get(artistId))
        else
            artist = await runWithLogger(log, () => artistRepository.getByName(name!))

        log.debug({ artist });

        if (!artist) {
            log.info('artist not found')
            return res.status(404).json({ status: 'error', error_code: 'ARTIST_NOT_FOUND' });
        }

        res.status(200).json({ status: 'success', data: artist });
    } catch (err) {
        runWithLogger(log, () => handleError(res, err));
    }
});

router.get('/avatar/:artistId', auth, async (req, res) => {
    let log = getLogger().child({ module: 'artist', route: 'GET /api/artist/avatar/:artistId' });

    try {
        log.info('avatar request received');

        log.debug({ params: req.params, query: req.query });
        const { artistId } = await runWithLogger(log, () => validate(avatarParamsSchema, { ...req.params, ...req.query }));
        log.info('Input validated');
        log.debug({ artistId });

        const artistRepository = new ArtistRepository();

        const artist = await runWithLogger(log, () => artistRepository.get(artistId));
        log.debug({ artist });
        log.info('Checked artist ownership');
        if (!artist) {
            log.info('Rejected avatar request: artist not found or has no avatar');
            return res.status(404).json({ status: 'error', error_code: 'ARTIST_NOT_FOUND' });
        }
        if (!artist.avatarKey) {
            log.info('Rejected avatar request: artist not found or has no avatar');
            return res.status(404).json({ status: 'error', error_code: 'AVATAR_NOT_FOUND' });
        }

        const result = await getS3ObjectStream(artist.avatarKey);
        log.debug({ result });
        if (!result) {
            log.warn('avatar object has no body');
            return res.status(404).json({ status: 'error', error_code: 'AVATAR_NOT_FOUND' });
        }

        const { stream, contentLength, contentType } = result
        log.debug({ stream, contentLength, contentType });

        if (!stream) {
            log.warn('avatar object has no body');
            return res.status(404).json({ status: 'error', error_code: 'AVATAR_NOT_FOUND' });
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

router.get('/album', auth, async (req, res) => {
    let log = getLogger().child({ module: 'artist', route: 'GET /api/artist/album' });

    try {
        log.info('artist album list request received');

        log.debug({ query: req.query });
        const { artistName } = await runWithLogger(log, () => validate(albumListQuerySchema, req.query));
        log.info('Input validated');
        log.debug({ artistName });

        const userId = req.user!.userId;
        log = log.child({ userId });

        const artistAlbumAudioRepository = new ArtistAlbumAudioRepository();

        let artistAlbumAudios = await runWithLogger(log, () => artistAlbumAudioRepository.getManyByArtistName(artistName))
        log.debug({ artistAlbumAudios });

        const albums: string[] = []
        artistAlbumAudios.forEach(f => {
            if (!albums.includes(f.albumName))
                albums.push(f.albumName)
        });

        res.status(200).json({ status: 'success', data: albums });
    } catch (err) {
        runWithLogger(log, () => handleError(res, err));
    }
});

router.put('/avatar/:artistId', auth, isAdminIfAuthenticated, async (req, res) => {
    let log = getLogger().child({ module: 'artist', route: 'GET /api/artist/avatar/:artistId' });

    try {
        log.info('avatar request received');

        log.debug({ params: req.params });
        const { artistId } = await runWithLogger(log, () => validate(avatarParamsSchema, { ...req.params }));
        log.info('Input validated');
        log.debug({ artistId });

        const artistRepository = new ArtistRepository();

        const artist = await runWithLogger(log, () => artistRepository.get(artistId));
        log.debug({ artist });
        log.info('Checked artist ownership');
        if (!artist) {
            log.info('Rejected avatar request: artist not found or has no avatar');
            return res.status(404).json({ status: 'error', message: 'Artist not found' });
        }

        // ------------------------------------------------------------------------- make the temporary directory
        log.info('make the temporary directory')

        const jobDir = join(imageUploadTmpDir, 'avatars', artistId)
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

            if (artist.avatarKey) {
                log.info('deleting old avatar')
                try { await runWithLogger(log, () => deleteFromS3(artist.avatarKey!)) } catch (err) { log.warn({ err }, 'failed to delete old avatar') }
            }

            const key = getAvatarKey(artistId)
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

router.get('/banner/:artistId', auth, async (req, res) => {
    let log = getLogger().child({ module: 'artist', route: 'GET /api/artist/banner/:artistId' });

    try {
        log.info('banner request received');

        log.debug({ params: req.params, query: req.query });
        const { artistId } = await runWithLogger(log, () => validate(avatarParamsSchema, { ...req.params, ...req.query }));
        log.info('Input validated');
        log.debug({ artistId });

        const artistRepository = new ArtistRepository();

        const artist = await runWithLogger(log, () => artistRepository.get(artistId));
        log.debug({ artist });
        log.info('Checked artist ownership');
        if (!artist) {
            log.info('Rejected banner request: artist not found or has no banner');
            return res.status(404).json({ status: 'error', error_code: 'ARTIST_NOT_FOUND' });
        }
        if (!artist.bannerKey) {
            log.info('Rejected banner request: artist not found or has no banner');
            return res.status(404).json({ status: 'error', error_code: 'BANNER_NOT_FOUND' });
        }

        const result = await getS3ObjectStream(artist.bannerKey);
        log.debug({ result });
        if (!result) {
            log.warn('banner object has no body');
            return res.status(404).json({ status: 'error', error_code: 'BANNER_NOT_FOUND' });
        }

        const { stream, contentLength, contentType } = result
        log.debug({ stream, contentLength, contentType });

        if (!stream) {
            log.warn('banner object has no body');
            return res.status(404).json({ status: 'error', error_code: 'BANNER_NOT_FOUND' });
        }

        res.setHeader('Accept-Ranges', 'bytes');
        res.setHeader('Content-Type', contentType || 'application/octet-stream');
        res.status(200);
        res.setHeader('Content-Length', contentLength ?? '');

        log.info('Streaming banner to client');
        stream.pipe(res);
    } catch (err) {
        runWithLogger(log, () => handleError(res, err));
    }
});

router.put('/banner/:artistId', auth, isAdminIfAuthenticated, async (req, res) => {
    let log = getLogger().child({ module: 'artist', route: 'GET /api/artist/banner/:artistId' });

    try {
        log.info('banner request received');

        log.debug({ params: req.params });
        const { artistId } = await runWithLogger(log, () => validate(avatarParamsSchema, { ...req.params }));
        log.info('Input validated');
        log.debug({ artistId });

        const artistRepository = new ArtistRepository();

        const artist = await runWithLogger(log, () => artistRepository.get(artistId));
        log.debug({ artist });
        log.info('Checked artist ownership');
        if (!artist) {
            log.info('Rejected banner request: artist not found or has no banner');
            return res.status(404).json({ status: 'error', message: 'Artist not found' });
        }

        // ------------------------------------------------------------------------- make the temporary directory
        log.info('make the temporary directory')

        const jobDir = join(imageUploadTmpDir, 'banners', artistId)
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

            if (artist.bannerKey) {
                log.info('deleting old banner')
                try { await runWithLogger(log, () => deleteFromS3(artist.bannerKey!)) } catch (err) { log.warn({ err }, 'failed to delete old banner') }
            }

            const key = getBannerKey(artistId)
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

router.delete('/:artistId', auth, isAdminIfAuthenticated, async (req, res) => {
    let log = getLogger().child({ module: 'artist', route: 'DELETE /api/artist/:artistId' });

    let db: MongoDB | undefined = undefined
    try {
        log.info('Artist delete request received');

        log.debug({ params: req.params });
        const { artistId } = await runWithLogger(log, () => validate(deleteParamsSchema, req.params));
        log.info('Input validated');
        log.debug({ artistId });

        db = MongoDB.getDbInstance()

        // sessions are set after in case s3 storage deletion process gets interrupted
        const session = await db.startTransaction()

        const artistRepository = new ArtistRepository();
        artistRepository.setTransactionSession(session)

        const artist = await runWithLogger(log, () => artistRepository.get(artistId));
        log.debug({ artist });
        if (!artist) {
            log.info('Rejected artist delete request: artist not found');
            res.status(404).json({ status: 'error', message: 'Artist not found' });
            await db.abortTransaction()
            return
        }

        const r = await runWithLogger(log, () => artistRepository.unsafeUpdate(artistId, { name: `deletionQueued${ARTIST_NAME_SEPARATOR}${artist.name}`, deletionQueued: true }));
        log.debug({ updateResult: r });
        if (!r.acknowledged || r.matchedCount) {
            log.error({ updateResult: r }, 'Failed to mark artist temporary before delete');
            res.status(500).json({ status: 'error', message: 'Error deleting artist' });
            await db.abortTransaction()
            return
        }
        log.info('Marked artist temporary before delete');

        const promises = []
        if (artist?.avatarKey) {
            log.info('Deleting artist file from storage');
            promises.push(runWithLogger(log, () => deleteFromS3(artist.avatarKey!)))
            log.debug({ key: artist.avatarKey });
        }

        if (artist?.bannerKey) {
            log.info('Deleting web artist file from storage');
            promises.push(runWithLogger(log, () => deleteFromS3(artist.bannerKey!)))
            log.debug({ key: artist.bannerKey });
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

        const rr = await runWithLogger(log, () => artistRepository.delete(artistId));
        log.debug({ deleteResult: rr });
        if (!rr.acknowledged) {
            log.error({ deleteResult: rr }, 'Failed to delete artist record from DB');
            await db.abortTransaction()
            res.status(500).json({ status: 'error', message: 'Error deleting artist' });
            return
        }
        log.info('Deleted artist record in DB')

        await db.commitTransaction()

        log.info('artist deleted successfully');
        res.status(204).json({ status: 'success' });
    } catch (err) {
        runWithLogger(log, () => handleError(res, err));
        await db?.abortTransaction()
    }
});

export { router as artistRoutes };
