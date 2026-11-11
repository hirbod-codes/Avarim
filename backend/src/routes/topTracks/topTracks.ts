import express from 'express';
import { auth, isAdminIfAuthenticated } from '../../middlewares/auth';
import { getLogger, runWithLogger } from '../../observability/requestLoggerContext';
import { handleError, validate } from '../../lib';
import { deleteSchema, fetchSchema, listSchema, postSchema } from './schemas';
import TopTracksRepository from '../../db/MongoDB/TopTracksRepository';

const router = express.Router();

router.post('/', auth, isAdminIfAuthenticated, async (req, res) => {
    let log = getLogger().child({ module: 'topTracks', route: 'POST /api/topTracks/' });

    try {
        log.info('topTracks create request received');

        log.debug({ body: req.body });
        const { audioId, artistId, sortId } = await runWithLogger(log, () => validate(postSchema, req.query))
        log.debug({ audioId, artistId, sortId });
        log.info('input validated');

        const topTracksRepository = new TopTracksRepository();

        const insertionResult = await runWithLogger(log, () => topTracksRepository.insert({ audioId, artistId, sortId }))
        log.debug({ insertionResult });
        if (!insertionResult.acknowledged) {
            log.info('failed to insert a new document')
            return res.status(500).json({ status: 'error', error_code: 'INTERNAL_ERROR' })
        }

        res.status(200).json({ status: 'success', data: { id: insertionResult.insertedId } });
    } catch (err) {
        runWithLogger(log, () => handleError(res, err));
    }
})

router.get('/list', auth, isAdminIfAuthenticated, async (req, res) => {
    let log = getLogger().child({ module: 'topTracks', route: 'GET /api/topTracks/list' });

    try {
        log.info('topTracks list request received');

        log.debug({ query: req.query });
        const { page, pageSize, artistId } = await runWithLogger(log, () => validate(listSchema, req.query))
        log.debug({ page, pageSize, artistId });
        log.info('input validated');

        const topTracksRepository = new TopTracksRepository();

        const audios = await runWithLogger(log, () => topTracksRepository.getManyAudio({ artistId }, (page - 1) * pageSize, pageSize))
        log.debug({ audios });

        res.status(200).json({ status: 'success', data: audios });
    } catch (err) {
        runWithLogger(log, () => handleError(res, err));
    }
})

router.get('/', auth, isAdminIfAuthenticated, async (req, res) => {
    let log = getLogger().child({ module: 'topTracks', route: 'GET /api/topTracks/' });

    try {
        log.info('topTracks request received');

        log.debug({ query: req.query });
        const filter = await runWithLogger(log, () => validate(fetchSchema, req.query))
        log.debug({ filter });
        log.info('input validated');

        const topTracksRepository = new TopTracksRepository();

        const audios = await runWithLogger(log, () => topTracksRepository.getBy(filter))
        log.debug({ audios });

        res.status(200).json({ status: 'success', data: audios });
    } catch (err) {
        runWithLogger(log, () => handleError(res, err));
    }
})

router.delete('/', auth, isAdminIfAuthenticated, async (req, res) => {
    let log = getLogger().child({ module: 'topTracks', route: 'DELETE /api/topTracks/' });

    try {
        log.info('topTracks delete request received');

        log.debug({ query: req.query });
        const { topTracksId } = await runWithLogger(log, () => validate(deleteSchema, req.query))
        log.debug({ topTracksId });
        log.info('input validated');

        const topTracksRepository = new TopTracksRepository();

        const audios = await runWithLogger(log, () => topTracksRepository.delete(topTracksId))
        log.debug({ audios });

        res.status(200).json({ status: 'success', data: audios });
    } catch (err) {
        runWithLogger(log, () => handleError(res, err));
    }
})

export { router as topTracksRoutes };
