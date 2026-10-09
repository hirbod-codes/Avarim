import { Response } from "express";
import { signAccessToken } from './token_management';
import { ClientType, createSessionFamily } from "./session_management";
import { getLogger } from '../../observability/requestLoggerContext';
import { ACCESS_COOKIE_NAME, REFRESH_COOKIE_NAME } from "../../middlewares/auth";

const REFRESH_TTL_SECONDS = 30 * 24 * 60 * 60;

export function setAuthCookies(res: Response, accessToken: string, refreshTokenId: string, accessExpSeconds: number) {
    const log = getLogger().child({ step: 'setAuthCookies' });

    log.debug({ accessExpSeconds });

    res.cookie(ACCESS_COOKIE_NAME, accessToken, { httpOnly: true, secure: true, sameSite: 'strict', maxAge: accessExpSeconds * 1000, path: '/', });

    res.cookie(REFRESH_COOKIE_NAME, refreshTokenId, { httpOnly: true, secure: true, sameSite: 'strict', maxAge: REFRESH_TTL_SECONDS * 1000, path: '/', });

    log.info('Set auth cookies');
}

export function clearAuthCookies(res: Response) {
    const log = getLogger().child({ step: 'issueTokens' });

    res.clearCookie(ACCESS_COOKIE_NAME, { path: '/' });
    res.clearCookie(REFRESH_COOKIE_NAME, { path: '/auth' });

    log.info("cleared auth cookies at '/' and '/auth' paths");
}

export async function issueTokens(res: Response, userId: string, client: ClientType, userAgent?: string) {
    const log = getLogger().child({ step: 'issueTokens' });

    log.debug({ userId, client, userAgent })

    const { tokenId } = await createSessionFamily({ userId, client, userAgent });
    const { token: accessToken, exp } = signAccessToken(userId);
    log.debug({ accessTokenLength: accessToken.length, refreshTokenLength: tokenId.length, exp, expirationDate: (new Date(exp)).toUTCString() })
    log.info('Issued access + refresh tokens');

    if (client === 'web') {
        setAuthCookies(res, accessToken, tokenId, exp - Math.floor(Date.now() / 1000));
        log.info('store access and refresh tokens in cookies')
    }

    return { accessToken, refreshToken: tokenId }
}
