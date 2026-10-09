import crypto from 'crypto';
import { streamSigningSecret } from '../configs';
import { getLogger } from '../observability/requestLoggerContext';

export function generateStreamToken(videoId: string, userId: string, ttlSeconds = 60 * 60 * 6): string {
    const log = getLogger().child({ step: 'generateStreamToken' });

    const exp = Math.floor(Date.now() / 1000) + ttlSeconds;
    const payload = `${videoId}.${userId}.${exp}`;
    const signature = crypto.createHmac('sha256', streamSigningSecret).update(payload).digest('hex');

    // token = payload + signature, base64url-encoded so it's URL-safe
    const token = Buffer.from(`${payload}.${signature}`).toString('base64url');

    log.debug({ exp, expirationDate: (new Date(exp)).toUTCString(), payload, signature })
    return token;
}

export function verifyStreamToken(token: string, videoId: string): { valid: boolean; userId?: string } {
    const log = getLogger().child({ step: 'verifyStreamToken' });

    try {
        log.debug({ token, videoId })

        const decoded = Buffer.from(token, 'base64url').toString('utf8');
        const [tokenVideoId, userId, expStr, signature] = decoded.split('.');
        const exp = parseInt(expStr, 10);
        const now = Date.now() / 1000
        log.debug({ tokenVideoId, userId, expStr, exp, now })

        if (tokenVideoId !== videoId) {
            log.info('invalid video id provided')
            return { valid: false };
        }
        log.info('token\'s video id is valid')

        if (now > exp) {
            log.info('token expired')
            return { valid: false };
        }
        log.info('token is not expired')

        const payload = `${tokenVideoId}.${userId}.${expStr}`;
        log.debug({ payload })

        const expectedSig = crypto.createHmac('sha256', streamSigningSecret).update(payload).digest('hex');

        // timing-safe compare
        const sigBuf = Buffer.from(signature, 'hex');
        const expectedBuf = Buffer.from(expectedSig, 'hex');
        if (sigBuf.length !== expectedBuf.length || !crypto.timingSafeEqual(sigBuf, expectedBuf)) {
            log.info('invalid signature')
            return { valid: false };
        }

        log.info('token verified')
        return { valid: true, userId };
    } catch (error) {
        log.debug({ error }, 'verifying stream token failed with error')
        return { valid: false };
    }
}