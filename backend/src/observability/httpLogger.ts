import { randomUUID } from 'node:crypto';
import pinoHttp, { ReqId } from 'pino-http';
import type { IncomingMessage, ServerResponse } from 'node:http';
import { logger } from './logger';
import { Request, Response, NextFunction } from 'express';

type LoggableResponse = Response & { _loggedBody?: unknown };

const pinoMiddleware = pinoHttp({
    logger,

    // Reuse an inbound x-request-id if a client/proxy already set one (nginx,
    // a mobile client, another service), otherwise mint one. Echoed back on the
    // response so a user's bug report ("it broke at 14:32") maps to one line
    // in Loki via `req.id`.
    genReqId: (req: IncomingMessage, res: ServerResponse) => {
        const existing = req.headers['x-request-id'];
        const id = typeof existing === 'string' && existing.length > 0 ? existing : randomUUID();
        res.setHeader('x-request-id', id);
        return id;
    },

    customLogLevel: (_req, res, err) => {
        if (err || res.statusCode >= 500) return 'error';
        if (res.statusCode >= 400) return 'warn';
        return 'info';
    },

    customSuccessMessage: (req, res) => `${req.method} ${req.url} -> ${res.statusCode}`,
    customErrorMessage: (req, res, err) => `${req.method} ${req.url} -> ${res.statusCode} (${err.message})`,

    // Lean by default — just enough to correlate a request across log lines.
    // Full detail (headers/query/body) only when THIS request's logger is at
    // debug level, checked via req.log rather than the base `logger`: an
    // admin hitting a route with ?logLevel=debug (see toggleDebugMode) swaps
    // in a debug-level child logger for that one request only, and the base
    // `logger`'s level never changes to reflect that. Serializers run at
    // response-finish, by which point toggleDebugMode (which runs later in
    // the middleware chain than this file) has already made its decision for
    // this request — so checking here, this late, sees it correctly.
    serializers: {
        req(req: Request) {
            const base = { method: req.method, url: req.url, id: req.id };
            if (!req.log?.isLevelEnabled('debug')) return base;
            return { ...base, query: req.query, headers: req.headers, body: req.body };
        },
        res(res: Response) {
            const base = { statusCode: res.statusCode };
            const req = res.req as Request | undefined;
            if (!req?.log?.isLevelEnabled('debug')) return base;
            const loggedBody = (res as LoggableResponse)._loggedBody;
            return {
                ...base,
                headers: res.getHeaders(),
                ...(loggedBody !== undefined ? { body: loggedBody } : {}),
            };
        },
    },

    // Skip noisy, low-value routes so /healthz and /metrics polling doesn't
    // drown out real traffic in Loki.
    autoLogging: {
        ignore: (req) => req.url === '/healthz' || req.url === '/metrics',
    },
});

/**
 * Node's ServerResponse never exposes what was actually written to the
 * socket, so the `res` serializer above can't get a response body on its
 * own — res.json()/res.send() have to be patched to stash it somewhere the
 * serializer can read (`res._loggedBody`).
 *
 * This patches UNCONDITIONALLY, on every request, rather than checking
 * whether debug is enabled first: at the point this middleware runs, that
 * isn't decided yet (toggleDebugMode, which can escalate an admin's request
 * to debug, runs later in the chain) — so the patch has to already be in
 * place just in case. The cost is two wrapped functions per request, which
 * is cheap; the actual decision about whether to USE what's captured lives
 * in the serializers above, at response-finish, once it's actually known.
 *
 * A route that pipes a stream straight to `res` (file/video downloads)
 * never calls res.json/res.send, so streamed responses are excluded from
 * body logging automatically — no content-type sniffing needed.
 */
function captureResponseBody(req: Request, res: Response, next: NextFunction) {
    const originalJson = res.json.bind(res);
    const originalSend = res.send.bind(res);

    res.json = ((body: unknown) => {
        (res as LoggableResponse)._loggedBody = body;
        return originalJson(body);
    }) as typeof res.json;

    res.send = ((body: unknown) => {
        // res.json() calls this.send() internally — this guard keeps the
        // readable pre-serialization object from json() (if it fired) rather
        // than overwriting it with the stringified version send() sees on
        // that internal call.
        const r = res as LoggableResponse;
        if (r._loggedBody === undefined) r._loggedBody = body;
        return originalSend(body);
    }) as typeof res.send;

    next();
}

export function httpLogger(req: Request, res: Response, next: NextFunction) {
    captureResponseBody(req, res, () => pinoMiddleware(req, res, next));
}

// Augment Express's Request type so `req.log` and `req.id` are typed
// wherever this middleware is used.
declare module 'http' {
    interface IncomingMessage {
        id: ReqId;
        log: import('pino').Logger;
    }
}
