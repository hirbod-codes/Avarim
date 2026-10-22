import path from 'node:path';
import pino from 'pino';
import { isProduction, logDir, logLevel, lokiPushUrl, nodeEnv } from '../configs';
import { trace, context } from '@opentelemetry/api';
import { getRequestId } from '../middlewares/requestContext';

// Where Pino writes its rotating JSON log file. This is the path Alloy tails
// (see docker-compose / config.alloy) — set it to the SAME absolute path on
// both sides in prod, and to a local ./logs folder in dev.
const logDirectory = logDir ?? path.join(process.cwd(), 'logs');

const VALID_LEVELS = new Set<pino.Level>(['fatal', 'error', 'warn', 'info', 'debug', 'trace']);

/**
 * logLevel comes from getStringEnv as a plain string, but pino's Level type
 * is a fixed string-literal union — a bare `as pino.Level` cast would
 * compile but silently accept a typo'd LOG_LEVEL at runtime. Validate once
 * here instead, with a safe fallback and a loud stderr warning if it's
 * wrong (can't use `logger` itself yet — this runs before it's constructed).
 */
function resolveLevel(): pino.Level {
    if (logLevel && VALID_LEVELS.has(logLevel as pino.Level))
        return logLevel as pino.Level;

    if (logLevel)
        console.error(`Invalid LOG_LEVEL "${logLevel}" — falling back to "info". Valid values: ${[...VALID_LEVELS].join(', ')}`);

    return 'info';
}

const effectiveLevel = resolveLevel();

// Never let these hit disk or stdout in plaintext, no matter how deep they're nested.
// req.headers.*/res.headers[...] below only start doing anything once
// httpLogger.ts's serializers actually include headers (debug level only) —
// before that change these three paths matched nothing and were dead entries.
const REDACT_PATHS = !isProduction ? [] : [
    'req.headers.authorization',
    'req.headers.cookie',
    'res.headers["set-cookie"]',
    'password',
    'newPassword',
    'token',
    'accessToken',
    'refreshToken',
    '*.password',
    '*.token',
    '*.accessToken',
    '*.refreshToken',

    // fast-redact's `*` wildcard matches exactly one path segment, so
    // `*.password` does NOT reach two segments deep — req.body.password
    // needs its own explicit entry. Same reasoning for every field below.
    'req.body.password',
    'req.body.newPassword',
    'req.body.confirmPassword',
    'req.body.token',
    'req.body.accessToken',
    'req.body.refreshToken',
    'req.query.token',
    // Auth login/register/refresh responses return a live access token in
    // the body — without these, turning on debug logging would put a
    // usable JWT in plaintext into every one of those log lines.
    'res.body.accessToken',
    'res.body.refreshToken',
    'res.body.token',
];

/**
 * A single pino.transport({ target: '...' }) call — ONE target, not an`
 * array — spins up its own dedicated worker thread. This is deliberate:
 * pino.transport({ targets: [...] }) with 2+ entries runs every target
 * inside one SHARED worker, and a failure in any single target (module
 * load, file open, network setup) can silently take the whole shared
 * worker down without the failure ever reaching this process's
 * transport.on('error') handler — a known rough edge in pino's
 * worker-thread transport system, not something specific to this app.
 * Building each target as its own independent worker and combining them
 * with pino.multistream() below avoids that failure mode: one broken
 * target degrades gracefully instead of taking every target dark with it.
 */
function namedTransport(name: string, opts: pino.TransportSingleOptions): pino.DestinationStream {
    const stream = pino.transport(opts);
    stream.on('error', (err) => {
        console.error(`pino transport error [${name}]:`, err);
    });
    return stream;
}

const streams: pino.StreamEntry[] = [
    {
        // Structured JSON, one line per event — this is the file Alloy tails and
        // ships to Loki. Rotates daily or at 50MB, keeps the last 14 files.
        level: effectiveLevel,
        stream: namedTransport('roll', {
            target: 'pino-roll',
            options: {
                file: path.join(logDirectory, 'backend.log'),
                frequency: 'daily',
                size: '50m',
                mkdir: true,
                limit: { count: 14 },
            },
        }),
    },
    {
        // Console output. Pretty-printed in dev; raw JSON to stdout in prod so
        // `docker logs` / your platform's log driver still gets something useful
        // without duplicating the pretty-printer's formatting cost.
        level: effectiveLevel,
        stream: namedTransport('console', {
            target: isProduction ? 'pino/file' : 'pino-pretty',
            options: isProduction
                ? { destination: 1 } // fd 1 = stdout
                : { colorize: true, translateTime: 'SYS:HH:MM:ss', ignore: 'pid,hostname' },
        }),
    },
    {
        level: effectiveLevel,
        stream: namedTransport('loki', {
            target: 'pino-loki',
            options: {
                batching: true,
                interval: 5,
                host: lokiPushUrl,
                silenceErrors: false,
                labels: {
                    service: isProduction ? 'avarim-backend' : 'dev-avarim-backend',
                    env: 'development',
                },
            },
        }),
    },
];

const transport = pino.multistream(streams);

export const logger = pino(
    {
        serializers: { err: pino.stdSerializers.err },
        level: logLevel ?? 'info',
        redact: { paths: REDACT_PATHS, censor: '[REDACTED]' },
        base: { service: isProduction ? 'avarim-backend' : 'dev-avarim-backend', env: nodeEnv ?? 'development' },
        timestamp: pino.stdTimeFunctions.epochTime, // ms epoch — matches the loki.process timestamp stage
        formatters: {
            level(label) {
                // "level":"info" instead of "level":30 — much nicer to filter on in Loki/Grafana.
                return { level: label };
            },
        },
        // Runs once per log call — adds trace_id/span_id only when a span is
        // actually active (e.g. inside a traced HTTP request), no-ops otherwise.
        mixin() {
            const r: any = {}

            const requestId = getRequestId()
            if (requestId)
                r.requestId = requestId

            const span = trace.getSpan(context.active())
            if (!span)
                return r

            const { traceId, spanId } = span.spanContext()
            r.trace_id = traceId
            r.span_id = spanId

            return r
        },
    },
    transport,
);

/**
 * Convenience helper so call sites read naturally:
 *   logAppError(logger, err)
 * instead of repeating the isOperational -> level mapping everywhere.
 */
export function severityForStatus(statusCode: number): pino.Level {
    if (statusCode >= 500) return 'error';
    if (statusCode >= 400) return 'warn';
    return 'info';
}


export type Logger = typeof logger;
