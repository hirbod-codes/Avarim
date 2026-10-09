import { Redis } from '../../db/redis';
import { smtpService } from '../..';
import { getLogger } from '../../observability/requestLoggerContext';
import { isProduction } from '../../configs';
import { generateCode, hashCode } from '../../lib';

const SMTP_TTL_SECONDS = 5 * 60;
const SMTP_REQUEST_COOLDOWN_SECONDS = 70;
const MAX_ATTEMPTS = 5;

type SmtpPurpose = 'login' | 'register';

interface SmtpRecord {
    codeHash: string;
    attempts: number;
    purpose?: SmtpPurpose;
}

export async function isOnCooldown(email: string) {
    const log = getLogger().child({ module: 'smtp', step: 'checkCooldown' });

    try {
        const redis = await Redis.getClient();

        const cooldownKey = `smtp_cooldown:${email}`;
        if (await redis.exists(cooldownKey)) {
            log.info('SMTP request blocked by cooldown');
            return true;
        }

        log.info('no cooldown found for SMTP request');
        return false
    } catch (error) {
        log.warn('failed to check for smtp message cooldown')
        log.error({ error })
        return true
    }
}

/**
 * `purpose` is tagged onto the record and checked on verify, so a code
 * requested for registration can't be replayed to log into an existing
 * account (or vice versa) if the two flows ever share a phone number window.
 */
export async function requestSmtp(email: string, locale: 'en' | 'fa', purpose?: SmtpPurpose): Promise<'sent' | 'cooldown' | 'failed'> {
    const log = getLogger().child({ module: 'smtp', step: 'requestSmtp' });

    try {
        log.debug({ email, locale, purpose })

        const redis = await Redis.getClient();

        if (await isOnCooldown(email)) {
            log.info('SMTP request blocked by cooldown');
            return 'cooldown';
        }

        const code = generateCode();

        // Never log `code` or the resulting codeHash. codeHash is a fast, unsalted-beyond-phone-number SHA-256 digest of a 6-digit code — for anyone who also knows the phone number
        const codeHash = isProduction ? hashCode(code, email) : `${code}:${email}`
        log.debug({ codeHash })

        const record: SmtpRecord = { codeHash, attempts: 0, purpose };

        await redis.set(`smtp:${email}`, JSON.stringify(record), 'EX', SMTP_TTL_SECONDS);
        await redis.set(`smtp_cooldown:${email}`, '1', 'EX', SMTP_REQUEST_COOLDOWN_SECONDS);
        log.debug('Redis key has been set')

        let result: boolean
        try {
            result = await smtpService.sendVerificationMessage(code, email, locale);
            log.debug({ result }, 'SMTP send result')
        } catch (error) {
            log.warn({ error }, 'Sending SMTP verification code, failed')
            return 'failed'
        }

        if (result) {
            log.info('SMTP verification code sent');
            return 'sent';
        } else {
            log.info('failed to send SMTP verification code');
            return 'failed';
        }
    } catch (error) {
        log.warn('Sending SMTP verification code, failed')
        log.debug({ error })
        return 'failed'
    }
}

export async function verifySmtp(email: string, code: string, purpose?: SmtpPurpose): Promise<boolean> {
    const log = getLogger().child({ module: 'smtp', step: 'verifySmtp' });

    try {
        log.debug({ email, code, purpose })

        const redis = await Redis.getClient();

        const key = `smtp:${email}`;

        const raw = await redis.get(key);
        if (!raw) {
            log.info('SMTP verification failed: no active code (expired or never requested)');
            return false; // expired or never requested
        }

        const record: SmtpRecord = JSON.parse(raw);
        log.debug({ record })

        if ((purpose || record.purpose) && record.purpose !== purpose) {
            log.info({ recordPurpose: record.purpose }, 'SMTP verification failed: purpose mismatch');
            return false;
        }

        if (record.attempts >= MAX_ATTEMPTS) {
            log.info({ attempts: record.attempts }, 'SMTP verification failed: max attempts exceeded, code burned');
            await redis.del(key); // burn it, force a new request
            log.debug('SMTP record deleted in Redis')

            return false;
        }

        const codeHash = isProduction ? hashCode(code, email) : `${code}:${email}`
        log.debug({ codeHash })

        if (record.codeHash !== codeHash) {
            record.attempts += 1;

            const ttl = await redis.ttl(key);
            log.debug({ keyTTL: ttl })
            if (ttl <= 0)
                await redis.del(key); // one-time use

            await redis.set(key, JSON.stringify(record), 'EX', ttl);
            log.debug('attempts field in SMTP field updated in Redis')

            log.info({ attempts: record.attempts }, 'SMTP verification failed: incorrect code');
            return false;
        }

        await redis.del(key); // one-time use
        log.debug('SMTP record deleted in Redis')

        log.info('SMTP verified');
        return true;
    } catch (error) {
        log.warn('SMTP verification failed');
        log.debug({ error })
        return false;
    }
}
