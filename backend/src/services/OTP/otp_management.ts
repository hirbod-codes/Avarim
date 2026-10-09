import { Redis } from '../../db/redis';
import { otpService } from '../..';
import { getLogger, runWithLogger } from '../../observability/requestLoggerContext';
import { isProduction } from '../../configs';
import { generateCode, hashCode } from '../../lib';
import { compare } from 'bcrypt';

const OTP_TTL_SECONDS = 5 * 60;
const OTP_REQUEST_COOLDOWN_SECONDS = 70;
const MAX_ATTEMPTS = 5;

type OtpPurpose = 'login' | 'register';

interface OtpRecord {
    codeHash: string;
    attempts: number;
    purpose?: OtpPurpose;
}

/**
 * `purpose` is tagged onto the record and checked on verify, so a code
 * requested for registration can't be replayed to log into an existing
 * account (or vice versa) if the two flows ever share a phone number window.
 */
export async function requestOtp(phoneNumber: string, locale: 'en' | 'fa', purpose?: OtpPurpose): Promise<'sent' | 'cooldown' | 'failed'> {
    const log = getLogger().child({ module: 'otp', step: 'requestOtp', phoneNumber, purpose });
    log.debug({ phoneNumber, locale, purpose })

    const redis = await Redis.getClient();

    const cooldownKey = `otp_cooldown:${phoneNumber}`;
    if (await redis.exists(cooldownKey)) {
        log.debug('OTP request blocked by cooldown');
        return 'cooldown';
    }

    const code = generateCode();

    // Never log `code` or the resulting codeHash. codeHash is a fast, unsalted-beyond-phone-number SHA-256 digest of a 6-digit code — for anyone who also knows the phone number
    const codeHash = hashCode(code, phoneNumber)
    !isProduction && log.debug({ codeHash: `${code}:${phoneNumber}` })

    const record: OtpRecord = { codeHash, attempts: 0, purpose };

    await redis.set(`otp:${phoneNumber}`, JSON.stringify(record), 'EX', OTP_TTL_SECONDS);
    await redis.set(cooldownKey, '1', 'EX', OTP_REQUEST_COOLDOWN_SECONDS);
    log.debug('Redis key has been set')

    let result: boolean
    try {
        result = await runWithLogger(log, () => otpService.sendVerificationMessage(code, phoneNumber, locale))
        log.debug({ result }, 'OTP send result')
    } catch (error) {
        log.warn({ error }, 'Sending OTP verification code, failed')
        return 'failed'
    }

    if (result) {
        log.info('OTP verification code sent');
        return 'sent';
    } else {
        log.info('failed to send OTP verification code');
        return 'failed';
    }
}

export async function verifyOtp(phoneNumber: string, code: string, purpose?: OtpPurpose): Promise<boolean> {
    const log = getLogger().child({ module: 'otp', step: 'verifyOtp', phoneNumber, purpose });
    log.debug({ phoneNumber, code, purpose })

    const redis = await Redis.getClient();

    const key = `otp:${phoneNumber}`;

    const raw = await redis.get(key);
    if (!raw) {
        log.info('OTP verification failed: no active code (expired or never requested)');
        return false; // expired or never requested
    }

    const record: OtpRecord = JSON.parse(raw);
    log.debug({ record })

    if ((purpose || record.purpose) && record.purpose !== purpose) {
        log.info({ recordPurpose: record.purpose }, 'OTP verification failed: purpose mismatch');
        return false;
    }

    if (record.attempts >= MAX_ATTEMPTS) {
        log.info({ attempts: record.attempts }, 'OTP verification failed: max attempts exceeded, code burned');
        await redis.del(key); // burn it, force a new request
        log.debug('OTP record deleted in Redis')

        return false;
    }

    const codeHash = `${code}:${phoneNumber}`
    !isProduction && log.debug({ code: codeHash, codeHash: hashCode(code, phoneNumber) })

    const match = await compare(codeHash!, record.codeHash);
    log.debug({ match })
    // if (!match) {
    if (hashCode(code, phoneNumber) !== record.codeHash) {
        record.attempts += 1;

        const ttl = await redis.ttl(key);
        log.debug({ keyTTL: ttl })
        if (ttl <= 0)
            await redis.del(key); // one-time use

        await redis.set(key, JSON.stringify(record), 'EX', ttl);
        log.debug('attempts field in OTP field updated in Redis')

        log.info({ attempts: record.attempts }, 'OTP verification failed: incorrect code');
        return false;
    }

    await redis.del(key); // one-time use
    log.debug('OTP record deleted in Redis')

    log.info('OTP verified');
    return true;
}
