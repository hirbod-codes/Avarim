import { AsyncLocalStorage } from 'node:async_hooks';
import type { Request, Response, NextFunction } from 'express';

const als = new AsyncLocalStorage<{ requestId: string }>();

export function requestContextMiddleware(req: Request, _res: Response, next: NextFunction) {
    als.run({ requestId: String(req.id) }, next);
}

export function getRequestId(): string | undefined {
    return als.getStore()?.requestId;
}
