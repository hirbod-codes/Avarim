/**
 * Base class for all *operational* errors — expected failure modes that
 * should be caught, logged appropriately, and turned into a clean HTTP
 * response (invalid input, missing resource, auth failure, etc).
 *
 * Anything thrown that is NOT an instance of AppError is treated by the
 * central error handler as a programmer error / bug: logged at `fatal`
 * severity and (in most setups) allowed to crash the process so it can
 * be restarted clean.
 */
export class AppError extends Error {
    public readonly statusCode: number;
    public readonly errorCode: string;
    public readonly isOperational: boolean = true;
    public readonly details?: unknown;

    constructor(message: string, statusCode: number, errorCode: string, details?: unknown) {
        super(message);

        // Restore prototype chain (needed when targeting ES5, harmless otherwise)
        Object.setPrototypeOf(this, new.target.prototype);

        this.name = this.constructor.name;
        this.statusCode = statusCode;
        this.errorCode = errorCode;
        this.details = details;

        Error.captureStackTrace(this, this.constructor);
    }
}

export class ValidationError extends AppError {
    constructor(message = 'Validation failed', details?: unknown) {
        super(message, 400, 'VALIDATION_ERROR', details);
    }
}

export class BadRequestError extends AppError {
    constructor(message = 'Bad request', details?: unknown) {
        super(message, 400, 'BAD_REQUEST', details);
    }
}

export class UnauthorizedError extends AppError {
    constructor(message = 'Authentication required', details?: unknown) {
        super(message, 401, 'UNAUTHORIZED', details);
    }
}

export class ForbiddenError extends AppError {
    constructor(message = 'Access denied', details?: unknown) {
        super(message, 403, 'FORBIDDEN', details);
    }
}

export class NotFoundError extends AppError {
    constructor(message = 'Resource not found', details?: unknown) {
        super(message, 404, 'NOT_FOUND', details);
    }
}

export class ConflictError extends AppError {
    constructor(message = 'Resource conflict', details?: unknown) {
        super(message, 409, 'CONFLICT', details);
    }
}

export class RateLimitError extends AppError {
    constructor(message = 'Too many requests', details?: unknown) {
        super(message, 429, 'RATE_LIMITED', details);
    }
}

/**
 * Use for known-external failures you still want to treat as operational
 * (e.g. a downstream S3/Stripe/Redis call that failed in an expected way,
 * as opposed to a bug in your own code).
 */
export class ExternalServiceError extends AppError {
    constructor(service: string, message = `Upstream service failed: ${service}`, details?: unknown) {
        super(message, 502, 'EXTERNAL_SERVICE_ERROR', details);
    }
}

export function isAppError(err: unknown): err is AppError {
    return err instanceof AppError;
}