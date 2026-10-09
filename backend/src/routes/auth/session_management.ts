import { randomBytes, createHash } from 'crypto';
import { Redis } from '../../db/redis';
import { getLogger } from '../../observability/requestLoggerContext';
import { isProduction } from '../../configs';

const REFRESH_TTL_SECONDS = 30 * 24 * 60 * 60; // 30 days
const REVOKED_TOMBSTONE_TTL_SECONDS = REFRESH_TTL_SECONDS;

export type ClientType = 'web' | 'mobile' | 'desktop';

export interface RefreshRecord {
    userId: string;
    familyId: string;
    client: ClientType;
    userAgent?: string;
    createdAt: number;
}

function newToken(): string {
    return randomBytes(32).toString('base64url');
}

/**
 * tokenId/familyId are themselves bearer secrets (knowing one is enough to
 * rotate/revoke a session), so they're never logged directly. This gives a
 * short, one-way, non-reversible tag that lets you correlate repeated log
 * lines for the same session (e.g. spotting refresh-token replay) without
 * the log itself being a usable credential.
 */
function fingerprint(secret: string): string {
    return createHash('sha256').update(secret).digest('hex').slice(0, 12);
}

/**
 * Call on login/register. Starts a new rotation chain ("family") for this device/browser. 
 * 
 * `familyId` is what "logout this session" / session listing operate on; 
 * `tokenId` is the single-use refresh token handed to the client.
 * 
 * Each userId set has 'family id's and each 'family id' set has token ids
 */
export async function createSessionFamily(data: Omit<RefreshRecord, 'familyId' | 'createdAt'>): Promise<{ tokenId: string; familyId: string }> {
    const redis = await Redis.getClient();
    const familyId = newToken();
    const tokenId = newToken();
    const record: RefreshRecord = { ...data, familyId, createdAt: Date.now() };

    await redis.multi()
        .set(`refresh:${tokenId}`, JSON.stringify(record), 'EX', REFRESH_TTL_SECONDS)
        .sadd(`user_sessions:${data.userId}`, familyId)
        .expire(`user_sessions:${data.userId}`, REFRESH_TTL_SECONDS)
        .sadd(`refresh_family:${familyId}`, tokenId)
        .expire(`refresh_family:${familyId}`, REFRESH_TTL_SECONDS)
        .exec();

    getLogger().debug(
        { module: 'session', userId: data.userId, client: data.client, familyFingerprint: fingerprint(familyId), tokenFingerprint: fingerprint(tokenId) },
        'Created session family'
    );

    return { tokenId, familyId };
}

/**
 * Rotates a refresh token: the old one is destroyed (and tombstoned) and a
 * new one is issued in the same family. If a tombstoned (already-rotated)
 * token is presented again, that's a replay — likely the token was stolen —
 * so the entire family is revoked, killing every token in that chain.
 */
export async function rotateRefreshToken(oldTokenId: string): Promise<RefreshRecord & { newTokenId: string }> {
    const log = getLogger().child({ module: 'session', tokenFingerprint: fingerprint(oldTokenId) });

    if (!isProduction) log.debug({ oldTokenId })

    const redis = await Redis.getClient();

    const raw = await redis.get(`refresh:${oldTokenId}`);
    if (!isProduction) log.debug({ raw })
    if (!raw) {
        const revokedRaw = await redis.get(`revoked:${oldTokenId}`);
        if (!isProduction) log.debug({ revokedRaw })
        if (revokedRaw) {
            const { familyId, userId } = JSON.parse(revokedRaw);
            log.warn({ userId, familyFingerprint: fingerprint(familyId) }, 'Refresh token reuse detected (replay of an already-rotated token) — revoking entire family');
            await revokeFamily(familyId, userId);
        } else {
            log.debug('Refresh token not found (expired or invalid)');
        }
        throw new Error('REFRESH_INVALID');
    }

    const record: RefreshRecord = JSON.parse(raw);
    const newTokenId = newToken();
    if (!isProduction) log.debug({ newTokenId })

    await redis.multi()
        .set(
            `revoked:${oldTokenId}`,
            JSON.stringify({ familyId: record.familyId, userId: record.userId }),
            'EX', REVOKED_TOMBSTONE_TTL_SECONDS
        )
        .del(`refresh:${oldTokenId}`)
        .set(`refresh:${newTokenId}`, JSON.stringify(record), 'EX', REFRESH_TTL_SECONDS)
        .sadd(`refresh_family:${record.familyId}`, newTokenId)
        .srem(`refresh_family:${record.familyId}`, oldTokenId)
        .expire(`refresh_family:${record.familyId}`, REFRESH_TTL_SECONDS)
        .expire(`user_sessions:${record.userId}`, REFRESH_TTL_SECONDS)
        .exec();

    log.debug({ userId: record.userId, newTokenFingerprint: fingerprint(newTokenId) }, 'Rotated refresh token');

    return { ...record, newTokenId };
}

export async function revokeFamily(familyId: string, userId: string): Promise<void> {
    const redis = await Redis.getClient();
    const tokenIds = await redis.smembers(`refresh_family:${familyId}`);

    const pipeline = redis.multi();

    tokenIds.forEach(id => pipeline.del(`refresh:${id}`));

    pipeline.del(`refresh_family:${familyId}`);
    pipeline.srem(`user_sessions:${userId}`, familyId);

    await pipeline.exec();

    getLogger().info(
        { module: 'session', userId, familyFingerprint: fingerprint(familyId), revokedTokenCount: tokenIds.length },
        'Revoked session family'
    );
}

export async function revokeAllSessions(userId: string): Promise<void> {
    const log = getLogger().child({ module: 'session', userId });
    const redis = await Redis.getClient();
    const familyIds = await redis.smembers(`user_sessions:${userId}`);

    log.info({ familyCount: familyIds.length }, 'Revoking all sessions for user');
    for (const familyId of familyIds)
        await revokeFamily(familyId, userId);
}

/** Used by /logout: resolve a raw refresh token cookie/body value to its family and kill just that one */
export async function revokeSessionByTokenId(tokenId: string, userId: string): Promise<void> {
    const log = getLogger().child({ module: 'session', userId, tokenFingerprint: fingerprint(tokenId) });
    const redis = await Redis.getClient();
    const raw = await redis.get(`refresh:${tokenId}`);
    if (!raw) {
        log.debug('Refresh token not found for logout (already expired or rotated)');
        return;
    }
    const record: RefreshRecord = JSON.parse(raw);
    await revokeFamily(record.familyId, userId);
}

/** For a "your active sessions/devices" screen */
export async function listSessions(userId: string) {
    const redis = await Redis.getClient();
    const familyIds = await redis.smembers(`user_sessions:${userId}`);

    const sessions = [];
    for (const familyId of familyIds) {
        const tokenIds = await redis.smembers(`refresh_family:${familyId}`);
        if (tokenIds.length === 0) continue; // family exists but every token expired/rotated away

        // we don't care which token id we grab, we just need any one of them to read the shared metadata back out. tokenIds[0] is an arbitrary pick since SMEMBERS returns an unordered set.
        const raw = await redis.get(`refresh:${tokenIds[0]}`);
        // guard against a race condition, token might already be expired or deleted(e.g rotated out).
        if (!raw) continue;

        const record: RefreshRecord = JSON.parse(raw);
        sessions.push({
            familyId,
            client: record.client,
            userAgent: record.userAgent,
            createdAt: record.createdAt,
        });
    }

    getLogger().debug({ module: 'session', userId, sessionCount: sessions.length }, 'Listed sessions');
    return sessions;
}
