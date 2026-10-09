import { Request, Response, Router } from "express";
import PlanRepository from "../../db/MongoDB/PlanRepository";
import { getLogger, runWithLogger } from "../../observability/requestLoggerContext";
import { handleError } from "../../lib";

const router = Router();

router.get('/', async (req: Request, res: Response) => {
    const log = getLogger().child({ module: 'plan', route: 'GET /api/plan' });

    try {
        log.info('get all plans request received');

        const pr = new PlanRepository()
        const plans = await runWithLogger(log, () => pr.getAll())
        log.debug({ plans });

        res.status(200).json({ status: 'success', data: { plans } })
    } catch (error) {
        runWithLogger(log, () => handleError(res, error))
    }
})

export { router as planRoutes }
