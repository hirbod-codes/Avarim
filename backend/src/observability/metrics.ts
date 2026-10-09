import client from 'prom-client';
import type { NextFunction, Request, Response } from 'express';
import { nodeEnv } from '../configs';

export const registry = new client.Registry();

registry.setDefaultLabels({ service: 'avarim-backend', env: nodeEnv ?? 'development' });

// CPU, memory, event loop lag, GC pauses, active handles — free, and usually
// the first place you look when something's slow.
client.collectDefaultMetrics({ register: registry });

// ---------------------------------------------------------------------------
// HTTP
// ---------------------------------------------------------------------------

export const httpRequestsTotal = new client.Counter({
  name: 'http_requests_total',
  help: 'Total number of HTTP requests',
  labelNames: ['method', 'route', 'status_code'] as const,
  registers: [registry],
});

export const httpRequestDuration = new client.Histogram({
  name: 'http_request_duration_seconds',
  help: 'HTTP request duration in seconds',
  labelNames: ['method', 'route', 'status_code'] as const,
  // Tuned for a mix of fast JSON endpoints and slower streaming/upload routes.
  buckets: [0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10, 30],
  registers: [registry],
});

export const httpRequestsInFlight = new client.Gauge({
  name: 'http_requests_in_flight',
  help: 'Number of HTTP requests currently being processed',
  registers: [registry],
});

/**
 * Express middleware recording request count / duration / in-flight for
 * every route. Mount this before your routes (and before httpLogger, order
 * between the two doesn't matter, but it must wrap everything downstream).
 *
 * Labels on `route`, not `url` — Express's matched route pattern
 * (e.g. "/videos/:id") keeps cardinality bounded. Raw URLs with resource IDs
 * in them will blow up Prometheus's label cardinality over time.
 */
export function metricsMiddleware() {
  return (req: Request, res: Response, next: NextFunction) => {
    const stopTimer = httpRequestDuration.startTimer();
    httpRequestsInFlight.inc();

    res.on('finish', () => {
      httpRequestsInFlight.dec();

      const route = req.route?.path ? `${req.baseUrl}${req.route.path}` : 'unmatched';
      const labels = { method: req.method, route, status_code: String(res.statusCode) };

      httpRequestsTotal.inc(labels);
      stopTimer(labels);
    });

    next();
  };
}

// ---------------------------------------------------------------------------
// ffmpeg / media pipeline
//
// Generic HTTP metrics won't show you a stalled transcode or a backpressure
// bug in the tee/stream pipeline — instrument the pipeline stages directly.
// Wire `.inc()` / the timer at the call sites in your ffmpeg wrapper code
// (decodeVideoStreamToDisk, teeStream, HLS segment generation, etc).
// ---------------------------------------------------------------------------

export const ffmpegJobsTotal = new client.Counter({
  name: 'ffmpeg_jobs_total',
  help: 'Total ffmpeg pipeline jobs, by stage and outcome',
  labelNames: ['stage', 'outcome'] as const, // outcome: success | error | timeout
  registers: [registry],
});

export const ffmpegJobDuration = new client.Histogram({
  name: 'ffmpeg_job_duration_seconds',
  help: 'Duration of ffmpeg pipeline stages',
  labelNames: ['stage'] as const,
  buckets: [1, 5, 15, 30, 60, 120, 300, 600, 1800],
  registers: [registry],
});

export const ffmpegActiveJobs = new client.Gauge({
  name: 'ffmpeg_active_jobs',
  help: 'Number of ffmpeg jobs currently running, by stage',
  labelNames: ['stage'] as const,
  registers: [registry],
});

/**
 * Wrap an async ffmpeg pipeline stage to get duration/outcome/in-flight
 * metrics for free:
 *
 *   await withFfmpegMetrics('transcode_hls', () => runTranscode(input));
 */
export async function withFfmpegMetrics<T>(stage: string, fn: () => Promise<T>): Promise<T> {
  const stopTimer = ffmpegJobDuration.startTimer({ stage });
  ffmpegActiveJobs.inc({ stage });
  try {
    const result = await fn();
    ffmpegJobsTotal.inc({ stage, outcome: 'success' });
    return result;
  } catch (err) {
    ffmpegJobsTotal.inc({ stage, outcome: 'error' });
    throw err;
  } finally {
    ffmpegActiveJobs.dec({ stage });
    stopTimer();
  }
}
