import { AsyncLocalStorage } from 'node:async_hooks';
import { logger as baseLogger, Logger } from './logger';

const als = new AsyncLocalStorage<Logger>();

export function setRequestLogger(log: Logger) {
    als.enterWith(log);
}

export function getLogger(): Logger {
    return als.getStore() ?? baseLogger;
}

/**
 * For temporarily descending into nested logic with a richer child logger
 * and coming back — NOT for the initial per-request setup (that stays
 * setRequestLogger/enterWith, called once by requestContextMiddleware,
 * since there's no single bounded callback representing "the rest of this
 * request" to wrap).
 */
export function runWithLogger<T>(log: Logger, fn: () => T): T {
    return als.run(log, fn);
}
