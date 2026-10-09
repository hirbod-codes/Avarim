import type { NextFunction, Request, Response } from 'express';
import { ZodError } from 'zod';
import { isAppError } from '../errors/AppError';
import { getRequestId } from './requestContext';
import { severityForStatus } from '../observability/logger';
import { getLogger, runWithLogger } from '../observability/requestLoggerContext';
import { isProduction } from '../configs';

interface ErrorResponseBody {
    error: {
        code: string;
        message: string;
        requestId?: string;
        details?: unknown;
    };
}

/**
 * Normalizes anything thrown into a consistent { statusCode, errorCode,
 * message, isOperational, details } shape. This is where the
 * handler learns about error types it doesn't own directly (Zod, Mongo, etc)
 * so they still get treated as operational instead of falling through
 * to the "unknown bug" branch.
 */
function normalize(err: unknown): { statusCode: number, errorCode: string, message: string, isOperational: boolean, details?: unknown } {
    const log = getLogger().child({ step: 'normalize' });

    if (isAppError(err)) {
        log.info({ error: err }, 'Returning an application error')
        return {
            statusCode: err.statusCode,
            errorCode: err.errorCode,
            message: err.message,
            isOperational: err.isOperational,
            details: err.details,
        };
    }

    // Zod validation errors thrown at controller boundaries
    if (err instanceof ZodError) {
        log.info({ error: err }, 'Returning a Zod error')
        return {
            statusCode: 400,
            errorCode: 'VALIDATION_ERROR',
            message: 'Validation failed',
            isOperational: true,
            details: err.flatten(),
        };
    }

    // Mongo duplicate key error (e.g. unique index violation)
    if (err && typeof err === 'object' && 'code' in err && (err as { code: unknown }).code === 11000) {
        log.info({ error: err }, 'Returning a MongoDB error')
        return {
            statusCode: 409,
            errorCode: 'CONFLICT',
            message: 'Resource already exists',
            isOperational: true,
        };
    }

    // Anything else is an unrecognized / programmer error
    const message = err instanceof Error ? err.message : 'Internal server error';
    log.info({ error: err }, 'Returning an unexpected error')
    return {
        statusCode: 500,
        errorCode: 'INTERNAL_ERROR',
        message,
        isOperational: false,
    };
}

/**
 * The single centralized error-handling middleware. Mount this LAST,
 * after all routes and after notFoundHandler. Must keep all four
 * params (err, req, res, next) — Express uses the severity to detect
 * error-handling middleware.
 */
export function errorHandler(err: unknown, req: Request, res: Response, _next: NextFunction): void {
    const log = getLogger().child({ module: 'error', middleware: 'errorHandler' });

    const normalized = runWithLogger(log, () => normalize(err))
    log.debug({ normalized })
    const requestId = getRequestId();
    log.debug({ requestId })

    const logPayload = {
        err,
        requestId,
        method: req.method,
        path: req.originalUrl,
        statusCode: normalized.statusCode,
        errorCode: normalized.errorCode,
        isOperational: normalized.isOperational,
    };
    log.debug({ logPayload })

    // Operational errors are expected traffic (bad input, missing resource,
    // auth failures) — log at warn/info. Non-operational errors are bugs —
    // log at error/fatal so they're loud in Grafana/alerts.
    const level = normalized.isOperational ? severityForStatus(normalized.statusCode) : 'error';
    log.debug({ resolvedLogLevel: level })

    log[level](logPayload, normalized.message);

    const body: ErrorResponseBody = {
        error: {
            code: normalized.errorCode,
            message: normalized.isOperational ? normalized.message
                // Never leak internal error messages/stack details for bugs in
                // production — only the generic message goes to the client.
                : (isProduction ? 'Internal server error' : normalized.message),
            requestId,
        },
    };

    // Operational error details (e.g. Zod field-level validation errors) are
    // safe to expose to the client even in production — they help the caller
    // fix their request. Details on non-operational (bug) errors are only
    // ever shown outside production, to avoid leaking internals.
    if (normalized.details !== undefined && (normalized.isOperational || !isProduction)) {
        body.error.details = normalized.details;
    }
    log.debug({ body })

    res.status(normalized.statusCode).json(body);
}