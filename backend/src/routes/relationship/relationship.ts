import express from 'express';
import { auth, isAdminIfAuthenticated } from '../../middlewares/auth';
import { getLogger, runWithLogger } from '../../observability/requestLoggerContext';
import { handleError, validate } from '../../lib';
import ArtistAlbumAudioRepository from '../../db/MongoDB/ArtistAlbumAudioRepository';
import { albumNamePagePageSizeSchema, artistIdPagePageSizeSchema, audioAlbumArtistSchema, audioAlbumSchema, audioArtistAlbumSchema, audioArtistSchema, createSchema, fetchSchema, filterSchema, updateSchema } from './schemas';

const router = express.Router();

router.post('/', auth, async (req, res) => {
    let log = getLogger().child({ module: 'relationship', route: 'POST /api/relationship/' });

    try {
        log.info('relationship request received');

        log.debug({ query: req.query });
        const create = await runWithLogger(log, () => validate(createSchema, req.body))
        log.debug({ create });
        log.info('input validated');

        const artistAlbumAudioRepository = new ArtistAlbumAudioRepository();

        const results = await runWithLogger(log, () => artistAlbumAudioRepository.insert(create))
        log.debug({ results });

        res.status(200).json({ status: 'success', data: results });
    } catch (err) {
        runWithLogger(log, () => handleError(res, err));
    }
});

router.get('/', auth, async (req, res) => {
    let log = getLogger().child({ module: 'relationship', route: 'GET /api/relationship/' });

    try {
        log.info('relationship request received');

        log.debug({ query: req.query });
        const { page, pageSize, ...filter } = await runWithLogger(log, () => validate(fetchSchema, req.body))
        log.debug({ page, pageSize, filter });
        log.info('input validated');

        if (filter.artistId === null) delete filter.artistId
        if (filter.albumId === null) delete filter.albumId
        if (filter.audioId === null) delete filter.audioId
        log.debug({ filter })

        const artistAlbumAudioRepository = new ArtistAlbumAudioRepository();

        const results = await runWithLogger(log, () => artistAlbumAudioRepository.getBy(filter as any, (page - 1) * pageSize, pageSize))
        log.debug({ results });

        res.status(200).json({ status: 'success', data: results });
    } catch (err) {
        runWithLogger(log, () => handleError(res, err));
    }
});

// --------------------------------------------------------------- Artist

router.get('/artist/album', auth, async (req, res) => {
    let log = getLogger().child({ module: 'relationship', route: 'GET /api/relationship/artist/album' });

    try {
        log.info('relationship artist album request received');

        log.debug({ query: req.query });
        const { artistId, page, pageSize } = await runWithLogger(log, () => validate(artistIdPagePageSizeSchema, req.query));
        log.info('Input validated');
        log.debug({ artistId, page, pageSize });

        const userId = req.user!.userId;
        log = log.child({ userId });

        const artistAlbumAudioRepository = new ArtistAlbumAudioRepository();

        let albums = await runWithLogger(log, () => artistAlbumAudioRepository.getManyAlbumByArtistId(artistId, (page - 1) * pageSize, pageSize))
        log.debug({ albums });

        res.status(200).json({ status: 'success', data: albums });
    } catch (err) {
        runWithLogger(log, () => handleError(res, err));
    }
});

/**
 * fetches all the audios of an artist, with no album filter
 */
router.get('/artist/audio', auth, async (req, res) => {
    let log = getLogger().child({ module: 'relationship', route: 'GET /api/relationship/artist/audio' });

    try {
        log.info('relationship artist audio request received');

        log.debug({ query: req.query });
        const { artistId, page, pageSize } = await runWithLogger(log, () => validate(artistIdPagePageSizeSchema, req.query));
        log.info('Input validated');
        log.debug({ artistId, page, pageSize });

        const artistAlbumAudioRepository = new ArtistAlbumAudioRepository();

        let audios = await runWithLogger(log, () => artistAlbumAudioRepository.getManyAudioByArtistId(artistId, (page - 1) * pageSize, pageSize))
        log.debug({ audios });

        res.status(200).json({ status: 'success', data: audios });
    } catch (err) {
        runWithLogger(log, () => handleError(res, err));
    }
});

router.get('/artist/audio/singles', auth, async (req, res) => {
    let log = getLogger().child({ module: 'relationship', route: 'GET /api/relationship/artist/audio/singles' });

    try {
        log.info('relationship artist audio singles request received');

        log.debug({ query: req.query });
        const { artistId, page, pageSize } = await runWithLogger(log, () => validate(artistIdPagePageSizeSchema, req.query));
        log.info('Input validated');
        log.debug({ artistId, page, pageSize });

        const artistAlbumAudioRepository = new ArtistAlbumAudioRepository();

        let audios = await runWithLogger(log, () => artistAlbumAudioRepository.getManyAudioByArtistIdByAlbumId(artistId, undefined, (page - 1) * pageSize, pageSize))
        log.debug({ audios });

        res.status(200).json({ status: 'success', data: audios });
    } catch (err) {
        runWithLogger(log, () => handleError(res, err));
    }
});

// --------------------------------------------------------------- Album

router.get('/album/artist', auth, async (req, res) => {
    let log = getLogger().child({ module: 'relationship', route: 'GET /api/relationship/album/artist' });

    try {
        log.info('relationship album artist request received');

        log.debug({ query: req.query });
        const { albumId, page, pageSize } = await runWithLogger(log, () => validate(albumNamePagePageSizeSchema, req.query));
        log.debug({ albumId, page, pageSize });
        log.info('Input validated');

        const artistAlbumAudioRepository = new ArtistAlbumAudioRepository();

        let artists = await runWithLogger(log, () => artistAlbumAudioRepository.getManyArtistByAlbumId(albumId, (page - 1) * pageSize, pageSize))
        log.debug({ artists });

        res.status(200).json({ status: 'success', data: artists });
    } catch (err) {
        runWithLogger(log, () => handleError(res, err));
    }
});

router.get('/album/audio', auth, async (req, res) => {
    let log = getLogger().child({ module: 'relationship', route: 'GET /api/relationship/album/audio' });

    try {
        log.info('relationship album audio request received');

        log.debug({ query: req.query });
        const { albumId, page, pageSize } = await runWithLogger(log, () => validate(albumNamePagePageSizeSchema, req.query));
        log.info('Input validated');
        log.debug({ albumId, page, pageSize });

        const userId = req.user!.userId;
        log = log.child({ userId });

        const artistAlbumAudioRepository = new ArtistAlbumAudioRepository();

        let audios = await runWithLogger(log, () => artistAlbumAudioRepository.getManyAudioByAlbumId(albumId, (page - 1) * pageSize, pageSize))
        log.debug({ audios });

        res.status(200).json({ status: 'success', data: audios });
    } catch (err) {
        runWithLogger(log, () => handleError(res, err));
    }
});

// --------------------------------------------------------------- Audio

/**
 * to fetch a list of albums that the audio and the artist belongs to.
 * the artist can be undefined, some audios don't have an artist
 */
router.get('/audio/album/artist', auth, async (req, res) => {
    let log = getLogger().child({ module: 'relationship', route: 'GET /api/relationship/audio/album/artist' });

    try {
        log.info('relationship audio album artist request received');

        log.debug({ query: req.query });
        const { audioId, artistId, page, pageSize } = await runWithLogger(log, () => validate(audioAlbumArtistSchema, req.query));
        log.debug({ audioId, artistId, page, pageSize });
        log.info('Input validated');

        const artistAlbumAudioRepository = new ArtistAlbumAudioRepository();

        const albums = await runWithLogger(log, () => artistAlbumAudioRepository.getManyAlbumByAudioIdByArtistId(audioId, artistId, (page - 1) * pageSize, pageSize))
        log.debug({ albums })

        log.info('albums successfully fetched');
        res.status(200).json({ status: 'success', data: albums });
    } catch (err) {
        runWithLogger(log, () => handleError(res, err));
    }
})

/**
 * to fetch a list of albums that the audio belongs to. 
 */
router.get('/audio/album', auth, async (req, res) => {
    let log = getLogger().child({ module: 'relationship', route: 'GET /api/relationship/audio/album' });

    try {
        log.info('relationship audio album request received');

        log.debug({ query: req.query });
        const { audioId, page, pageSize } = await runWithLogger(log, () => validate(audioAlbumSchema, req.query));
        log.debug({ audioId, page, pageSize });
        log.info('Input validated');

        const artistAlbumAudioRepository = new ArtistAlbumAudioRepository();

        const albums = await runWithLogger(log, () => artistAlbumAudioRepository.getManyAlbumByAudioId(audioId, (page - 1) * pageSize, pageSize))
        log.debug({ albums })

        log.info('albums successfully fetched');
        res.status(200).json({ status: 'success', data: albums });
    } catch (err) {
        runWithLogger(log, () => handleError(res, err));
    }
})

/**
 * to fetch a list of artists that the audio and the album belongs to.
 * the album can be undefined, some audios don't have an album
 */
router.get('/audio/artist/album', auth, async (req, res) => {
    let log = getLogger().child({ module: 'relationship', route: 'GET /api/relationship/audio/artist/album' });

    try {
        log.info('relationship audio artist album request received');

        log.debug({ query: req.query });
        const { audioId, albumId, page, pageSize } = await runWithLogger(log, () => validate(audioArtistAlbumSchema, req.query));
        log.debug({ audioId, albumId, page, pageSize });
        log.info('Input validated');

        const artistAlbumAudioRepository = new ArtistAlbumAudioRepository();

        const artists = await runWithLogger(log, () => artistAlbumAudioRepository.getManyArtistByAudioIdByAlbumId(audioId, albumId, (page - 1) * pageSize, pageSize))
        log.debug({ artists })

        log.info('artists successfully fetched');
        res.status(200).json({ status: 'success', data: artists });
    } catch (err) {
        runWithLogger(log, () => handleError(res, err));
    }
})

/**
 * to fetch a list of albums that the audio belongs to. 
 */
router.get('/audio/artist', auth, async (req, res) => {
    let log = getLogger().child({ module: 'relationship', route: 'GET /api/relationship/audio/artist' });

    try {
        log.info('relationship audio artist request received');

        log.debug({ query: req.query });
        const { audioId, page, pageSize } = await runWithLogger(log, () => validate(audioArtistSchema, req.query));
        log.debug({ audioId, page, pageSize });
        log.info('Input validated');

        const artistAlbumAudioRepository = new ArtistAlbumAudioRepository();

        const artists = await runWithLogger(log, () => artistAlbumAudioRepository.getManyArtistByAudioId(audioId, (page - 1) * pageSize, pageSize))
        log.debug({ artists })

        log.info('artists successfully fetched');
        res.status(200).json({ status: 'success', data: artists });
    } catch (err) {
        runWithLogger(log, () => handleError(res, err));
    }
})

/**
 * a cronjob will remove any ArtistAlbumAudio record with an id field that doesn't exist, so we don't need to check document existence here.
 */
router.patch('/', auth, isAdminIfAuthenticated, async (req, res) => {
    let log = getLogger().child({ module: 'relationship', route: 'PATCH /api/relationship' });

    try {
        log.info('update relationship request received');

        log.debug({ body: req.body });
        const filter = await runWithLogger(log, () => validate(filterSchema, req.body))
        log.debug({ filter });
        const update = await runWithLogger(log, () => validate(updateSchema, req.body))
        log.debug({ update });
        log.info('input validated');

        if (filter.artistId === null) delete filter.artistId
        if (filter.albumId === null) delete filter.albumId
        if (filter.audioId === null) delete filter.audioId
        log.debug({ filter })

        if (update.artistId === null) delete update.artistId
        if (update.albumId === null) delete update.albumId
        if (!update.audioId) delete update.audioId
        log.debug({ update })

        if (Object.keys(update).length < 1) {
            log.info('there is nothing to update');
            return res.status(400).json({ status: 'error', error_code: 'NOTHING_TO_UPDATE' });
        }

        const artistAlbumAudioRepository = new ArtistAlbumAudioRepository()

        const updateRelationshipResult = await runWithLogger(log, () => artistAlbumAudioRepository.updateBy(filter as any, update as any));
        log.debug({ updateRelationshipResult });
        if (!updateRelationshipResult?.acknowledged) {
            log.info('update failed');
            return res.status(500).json({ status: 'error', error_code: 'INTERNAL_ERROR' });
        }

        return res.status(200).json({ status: 'success' })
    } catch (err) {
        runWithLogger(log, () => handleError(res, err))
    }
})

router.delete('/', auth, isAdminIfAuthenticated, async (req, res) => {
    let log = getLogger().child({ module: 'relationship', route: 'DELETE /api/relationship' });

    try {
        log.info('delete relationship request received');

        log.debug({ body: req.body });
        const filter = await runWithLogger(log, () => validate(filterSchema, req.body))
        log.debug({ filter });
        log.info('input validated');

        if (filter.artistId === null) delete filter.artistId
        if (filter.albumId === null) delete filter.albumId
        if (filter.audioId === null) delete filter.audioId
        log.debug({ filter })

        if (Object.keys(filter).length < 1) {
            log.info('there is nothing to update');
            return res.status(400).json({ status: 'error', error_code: 'INVALID_PARAMETER' });
        }

        const artistAlbumAudioRepository = new ArtistAlbumAudioRepository()

        const updateRelationshipResult = await runWithLogger(log, () => artistAlbumAudioRepository.deleteBy(filter as any));
        log.debug({ updateRelationshipResult });
        if (!updateRelationshipResult?.acknowledged) {
            log.info('update failed');
            return res.status(500).json({ status: 'error', error_code: 'INTERNAL_ERROR' });
        }

        return res.status(200).json({ status: 'success' })
    } catch (err) {
        runWithLogger(log, () => handleError(res, err))
    }
})