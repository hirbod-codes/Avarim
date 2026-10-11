import jwt from 'jsonwebtoken';
import { randomBytes } from 'crypto';
import { accessTokenSecret, isProduction } from '../../configs';
import { Redis } from '../../db/redis';
import { getLogger } from '../../observability/requestLoggerContext';

const ACCESS_TOKEN_TTL_SECONDS = isProduction ? 15 * 60 : 60 * 60;

export interface AccessTokenPayload extends jwt.JwtPayload {
    userId: string;
    jti: string;
}

/**
 * `exp` is set explicitly in the payload (rather than via jsonwebtoken's
 * `expiresIn` option) so we can reuse the same value to size the blacklist
 * TTL on logout without re-decoding the token.
 */
export function signAccessToken(userId: string): { token: string; jti: string; exp: number } {
    const jti = randomBytes(16).toString('hex');
    const exp = Math.floor(Date.now() / 1000) + ACCESS_TOKEN_TTL_SECONDS;

    const token = jwt.sign({ userId, jti, exp }, accessTokenSecret);

    // jti is an opaque identifier used only to look up blacklist entries —
    // unlike the signed `token` itself, it can't be used to forge a session,
    // so it's fine to log directly.
    getLogger().debug({ module: 'token', userId, jti, exp }, 'Signed access token');

    return { token, jti, exp };
}

export async function blacklistAccessToken(jti: string, exp: number): Promise<void> {
    const log = getLogger().child({ module: 'token', jti });
    const redis = await Redis.getClient();
    const ttl = exp - Math.floor(Date.now() / 1000);
    if (ttl >= 0) {
        await redis.set(`access_blacklist:${jti}`, '1', 'EX', ttl);
        log.info({ ttl }, 'Blacklisted access token');
    } else {
        log.debug({ ttl }, 'Skipped blacklisting already-expired access token');
    }
}

export async function isAccessTokenBlacklisted(jti: string): Promise<boolean> {
    const redis = await Redis.getClient();
    const blacklisted = (await redis.exists(`access_blacklist:${jti}`)) === 1;
    if (blacklisted)
        getLogger().debug({ module: 'token', jti }, 'Rejected: access token is blacklisted');
    return blacklisted;
}
