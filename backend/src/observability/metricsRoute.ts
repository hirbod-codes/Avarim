import { Router } from 'express';
import { registry } from './metrics';

export const metricsRouter = Router();

// Mount BEFORE any auth middleware — Prometheus won't send a bearer token.
// This is safe because the route is only reachable at all if the network
// allows it: bind Prometheus's scrape path to the internal Docker network
// only (see docker-compose), never publish this port publicly.
metricsRouter.get('/metrics', async (_req, res) => {
  try {
    res.set('Content-Type', registry.contentType);
    res.end(await registry.metrics());
  } catch (err) {
    res.status(500).end(err instanceof Error ? err.message : 'metrics collection failed');
  }
});
