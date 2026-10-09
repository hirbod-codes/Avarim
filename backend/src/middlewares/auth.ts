import jwt from "jsonwebtoken"
import { Request, Response, NextFunction } from "express";
import { accessTokenSecret, isProduction } from '../configs';
import { UserRepository } from "../db/MongoDB/UserRepository";
import { isAccessTokenBlacklisted } from "../routes/auth/token_management";
import { getLogger, runWithLogger, setRequestLogger } from '../observability/requestLoggerContext';

export const ACCESS_COOKIE_NAME = 'accessToken';
export const REFRESH_COOKIE_NAME = 'refreshToken';

/**
 * DOES NOT FORBID unauthenticated users.
 */
export async function isAdminIfAuthenticated(req: Request, res: Response, next: NextFunction) {
    const log = getLogger().child({ module: 'authentication', middleware: 'isAdminIfAuthenticated' });

    try {
        log.info('MIDDLEWARE: isAdminIfAuthenticated')

        const authenticationResult = runWithLogger(log, () => authenticateRequest(req))
        log.debug({ authenticationResult })
        if (!authenticationResult) {
            log.info('User is not authenticated');
            return next();
        }
        log.info('User is authenticated')

        const payload = authenticationResult as jwt.JwtPayload & { userId: string; jti?: string };
        if (payload.jti && await runWithLogger(log, () => isAccessTokenBlacklisted(payload.jti!))) {
            log.info('Rejected: access token blacklisted');
            return res.status(403).send();
        }

        const ur = new UserRepository()

        const u = await runWithLogger(log, () => ur.get(payload.userId))
        log.debug({ user: u })
        if (!u || u.role !== 'admin') {
            log.info('User is not an admin');
            return res.status(403).send();
        }

        log.info('User is an admin');
        next();
    } catch (err) {
        log.error({ err }, 'Error while checking admin status');
        return res.status(500).send();
    }
}

export async function toggleDebugMode(req: Request, res: Response, next: NextFunction) {
    const log = getLogger().child({ module: 'authentication', middleware: 'toggleDebugMode' });

    try {
        log.info('MIDDLEWARE: toggleDebugMode')

        const logLevel = req.query.logLevel
        log.debug({ logLevel });

        if (logLevel !== 'debug') {
            log.info('Requested log level is not debug')
            return next()
        }

        const ur = new UserRepository()

        log.info('trying to fetch user...')
        let userId, user
        if (req?.user) {
            if (req?.user?.userId)
                userId = req?.user?.userId

            if (req.user?.userData)
                user = req.user?.userData
        }

        if (!userId || !user) {
            log.info('authenticating...');

            const authenticationResult = runWithLogger(log, () => authenticateRequest(req))
            log.debug({ authenticationResult })
            if (!authenticationResult) {
                log.info('User is not authenticated');
                return next();
            }

            if (authenticationResult.jti && await runWithLogger(log, () => isAccessTokenBlacklisted(authenticationResult.jti!))) {
                log.warn({ userId: authenticationResult.userId }, 'Rejected: access token blacklisted');
                return res.status(401).send();
            }

            userId = authenticationResult.userId

            user = await runWithLogger(log, () => ur.get(userId!))
            log.debug({ user })
            if (!user) {
                log.warn('User id not found');
                log.info('User is not authenticated');
                return res.status(401).send();
            }

            req.user = {
                userId,
                userData: user,
                jwtPayload: authenticationResult
            }
        }
        log.info('User is authenticated');

        if (user.role !== 'admin') {
            log.info({ userId }, 'User is not an admin');
            return res.status(403).send();
        }

        req.log.info({ logLevel }, 'Switching effective log level to DEBUG')
        req.log = req.log.child({}, { level: 'debug' })

        setRequestLogger(req.log)

        next()
    } catch (err) {
        log.error({ err }, 'Error while checking admin status');
        return res.status(500).send();
    }
}

export async function auth(req: Request, res: Response, next: NextFunction) {
    const log = getLogger().child({ module: 'authentication', middleware: 'auth' });

    try {
        log.info('MIDDLEWARE: auth')

        const result = runWithLogger(log, () => authenticateRequest(req))
        log.debug({ authenticateRequestResult: result })
        if (!result) {
            log.info('User is not authenticated');
            return res.status(401).send();
        }

        if (result.jti && await runWithLogger(log, () => isAccessTokenBlacklisted(result.jti!))) {
            log.info({ userId: result.userId }, 'Rejected: access token blacklisted');
            return res.status(401).send();
        }

        const user = await runWithLogger(log, () => (new UserRepository()).get(result.userId))
        log.debug({ user })
        if (!user) {
            log.warn({ userId: result.userId }, 'Rejected: token valid but user no longer exists');
            return res.status(401).send();
        }

        req.user = {
            userId: result.userId,
            userData: user,
            jwtPayload: result
        }

        log.info('User is authenticated');
        next();
    } catch (err) {
        log.error({ err }, 'Error while checking admin status');
        return res.status(500).send();
    }
}

export function authenticateRequest(req: Request): false | jwt.JwtPayload {
    const log = getLogger().child({ step: 'authenticateRequest' });

    const authToken = runWithLogger(log, () => collectAuthToken(req))
    !isProduction && log.debug({ authToken })
    if (!authToken) {
        log.info('No token found')
        return false
    }

    return runWithLogger(log, () => authenticateToken(authToken))
}

export function authenticateToken(accessToken: string): false | jwt.JwtPayload {
    const log = getLogger().child({ step: 'authenticateToken' })

    log.debug({ token: accessToken })
    if (!accessToken) {
        log.info('No token found')
        return false
    }

    try {
        const decoded = jwt.verify(accessToken, accessTokenSecret);
        log.debug({ decoded })
        if (typeof decoded === 'string')
            throw new Error('INVALID_JWT')

        log.info('JWT token verified')
        return decoded;
    } catch (err) {
        // Expired/invalid tokens are routine (every access token expires
        // every 15 minutes) — debug, not error. err.message is safe to log
        // (e.g. "jwt expired"); the token itself never is.
        log.debug({ reason: (err as Error).message }, 'Access token verification failed');
        return false
    }
}

function collectAuthToken(req: Request): string | undefined | null {
    const log = getLogger().child({ step: 'collectAuthToken' });

    let authToken = req.headers?.authorization || req.cookies?.[ACCESS_COOKIE_NAME]
    !isProduction && log.debug({ authToken })
    if (!authToken) {
        log.info('No token found')
        return undefined
    }

    return req.headers?.authorization ? authToken.split(" ")[1] : authToken;
}

export function unAuth(req: Request, res: Response, next: NextFunction) {
    const log = getLogger().child({ module: 'authentication', middleware: 'unAuth' });

    const authToken = runWithLogger(log, () => collectAuthToken(req))
    !isProduction && log.debug({ authToken })
    if (authToken) {
        log.info('Rejected: expected unauthenticated request but auth header present');
        return res.status(401).send();
    }

    log.info('this is not an authenticated request');
    next();
}
