import { Router } from 'express';

export const healthRouter = Router();

/**
 * Cheap liveness check — "is the process up and responding at all". Used by
 * Docker's HEALTHCHECK / your orchestrator, not by Prometheus.
 */
healthRouter.get('/healthz', (_req, res) => {
  res.status(200).json({ status: 'success', uptimeSeconds: Math.round(process.uptime()) });
});

/**
 * Readiness check — "can this instance actually serve traffic right now".
 * Wire in real checks for your dependencies (Mongo, Redis, S3) as you add
 * them; each should be a fast, bounded-time ping, not a full health audit.
 *
 * Example:
 *   const [mongoOk, redisOk] = await Promise.all([pingMongo(), pingRedis()]);
 *   const ready = mongoOk && redisOk;
 */
healthRouter.get('/readyz', async (_req, res) => {
  const ready = true; // replace with real dependency checks
  res.status(ready ? 200 : 503).json({ status: ready ? 'ready' : 'not_ready' });
});
