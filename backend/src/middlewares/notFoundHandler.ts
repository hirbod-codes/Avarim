import type { NextFunction, Request, Response } from 'express';
import { NotFoundError } from '../errors/AppError';
import { getLogger } from '../observability/requestLoggerContext';

/**
 * Mount AFTER all routes, BEFORE the error handler. Converts any request
 * that didn't match a route into a proper operational NotFoundError, so
 * it flows through the same centralized handling/logging as every other
 * error instead of falling through to Express's default HTML 404 page.
 */
export function notFoundHandler(req: Request, _res: Response, next: NextFunction): void {
    const log = getLogger().child({ middleware: 'notFoundHandler' });
    log.info('route not found')

    next(new NotFoundError(`Route not found: ${req.method} ${req.originalUrl}`));
}