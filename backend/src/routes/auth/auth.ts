import { Router, Request, Response } from 'express';
import bcrypt from 'bcrypt';
import { UserRepository } from '../../db/MongoDB/UserRepository';
import { auth, authenticateRequest, REFRESH_COOKIE_NAME, unAuth } from '../../middlewares/auth';
import { getAuthSettings, updateAuthSettings } from './auth_settings';
import { requestOtp, verifyOtp } from '../../services/OTP/otp_management';
import { rotateRefreshToken, revokeFamily, revokeAllSessions, revokeSessionByTokenId, listSessions } from './session_management';
import { signAccessToken, blacklistAccessToken } from './token_management';
import { otpRequestSchema, adminSettingsSchema, loginSchema, refreshSchema, emailRegisterSchema, otpVerifySchema, emailVerifySchema, emailPasswordResetSchema, emailPasswordResetVerifySchema } from './schemas';
import { clearAuthCookies, issueTokens, setAuthCookies } from './lib';
import { isAdminIfAuthenticated } from '../../middlewares/auth';
import { string } from 'yup';
import { getLogger, runWithLogger } from '../../observability/requestLoggerContext';
import { handleError, validate } from '../../lib';
import { Redis } from '../../db/redis';
import { requestSmtp, verifySmtp } from '../../services/SMTP/smtp_management';
import { isProduction } from '../../configs';

const router = Router();

router.get('/supported_auth_methods', async (req: Request, res: Response) => {
    const log = getLogger().child({ module: 'auth', route: 'POST /api/auth/supported_auth_methods' });

    try {
        log.info('auth methods request received');

        log.info('Fetching auth settings')
        const settings = await runWithLogger(log, () => getAuthSettings())
        log.debug({ settings });

        const authMethods = []
        if (settings.allowEmailRegistration === true)
            authMethods.push('email')

        if (settings.allowOtp === true)
            authMethods.push('phone')

        log.debug({ authMethods })

        log.info('responding with auth settings')
        res.status(200).json({ status: 'success', data: authMethods })
    } catch (err: any) {
        runWithLogger(log, () => handleError(res, err))
    }
});

router.post('/otp/reset', auth, async (req: Request, res: Response) => { })

router.post('/otp/reset/verify', auth, async (req: Request, res: Response) => { })

router.post('/otp/request', unAuth, async (req: Request, res: Response) => {
    const log = getLogger().child({ module: 'auth', route: 'POST /api/auth/otp/request' });

    try {
        log.info('OTP verify request received');

        log.debug({ body: req.body })
        const { phoneNumber, locale } = await runWithLogger(log, () => validate(otpRequestSchema, req.body))
        log.info('input validated');
        log.debug({ phoneNumber, locale });

        const settings = await runWithLogger(log, () => getAuthSettings())
        if (settings?.allowOtp !== true) {
            log.info('OTP feature is disabled');
            return res.status(400).json({ status: 'error', error: 'feature unavailable' })
        }

        const result = await runWithLogger(log, () => requestOtp(phoneNumber, locale))
        log.debug({ requestOtpResult: result });
        if (result === 'cooldown') {
            log.info('Rejected OTP request: cooldown active');
            return res.status(429).json({ status: 'error', error_code: 'OTP_COOLDOWN' });
        }

        if (result === 'failed') {
            log.info('Rejected OTP request');
            return res.status(429).json({ status: 'error', error_code: 'OTP_FAILED' });
        }

        log.info('OTP sent');
        res.json({ status: 'success', message: 'Code sent' });
    } catch (err: any) {
        runWithLogger(log, () => handleError(res, err))
    }
});

router.post('/otp/verify', unAuth, async (req: Request, res: Response) => {
    const log = getLogger().child({ module: 'auth', route: 'POST /api/auth/otp/verify' });

    try {
        log.info('Register request received');

        log.debug({ body: req.body })
        const { client, code, phoneNumber } = await runWithLogger(log, () => validate(otpVerifySchema, req.body))
        log.info('input validated');
        log.debug({ client, code, phoneNumber });

        const settings = await runWithLogger(log, () => getAuthSettings())
        log.debug({ settings });

        log.info('verifying OTP verification code');
        if (!(await runWithLogger(log, () => verifyOtp(phoneNumber!, code!)))) {
            log.info('Rejected OTP verification: invalid OTP code');
            return res.status(400).json({ status: 'error', error_code: 'INVALID_CODE' });
        }
        log.info('OTP code verified successfully.');

        let userId: string

        const ur = new UserRepository();

        log.info('fetching user...')
        let user = await runWithLogger(log, () => ur.getByPhoneNumber(phoneNumber!))
        log.debug({ user });
        if (!user) {
            log.info('User not found, registering new user');

            // phone registration
            if (!settings.allowOtp) {
                log.info('Rejected registration: phone registration disabled');
                return res.status(403).json({ status: 'error', error_code: 'PHONE_REGISTRATION_DISABLED' });
            }

            const created = await runWithLogger(log, () => ur.create({
                authMethod: 'phone',
                role: 'user',
                phoneNumber: phoneNumber,
                temporaryAvatar: true,
                language: 'fa',
                calendar: 'persian',
                timezone: 'utc',
            }))
            log.debug({ creationResult: created });
            if (!created || !created.acknowledged) {
                log.error('User creation failed');
                return res.status(500).json({ status: 'error', error_code: 'CREATE_FAILED' });
            }

            userId = created.insertedId.toString()

            user = await runWithLogger(log, () => ur.get(userId))
            if (!user) {
                log.error({ userId }, 'User fetch failed');
                return res.status(500).json({ status: 'error', error_code: 'FETCH_FAILED' });
            }
        }
        else userId = user._id.toString()

        let tokens
        if (user) {
            log.info({ userId }, 'Login succeeded (phone)');
            tokens = await runWithLogger(log, () => issueTokens(res, userId, client, req.headers['user-agent']))
        } else {
            log.info({ userId }, 'Registered new user (phone)');
            tokens = await runWithLogger(log, () => issueTokens(res, userId, client, req.headers['user-agent']))
        }

        if (client === 'web')
            return res.json({ status: 'success', data: { user, accessToken: tokens.accessToken } });

        return res.json({ status: 'success', data: { user, accessToken: tokens.accessToken, refreshToken: tokens.refreshToken } });
    } catch (err: any) {
        runWithLogger(log, () => handleError(res, err))
    }
});

router.post('/email/reset', auth, async (req: Request, res: Response) => { })

router.post('/email/reset/verify', auth, async (req: Request, res: Response) => { })

router.post('/email/register', unAuth, async (req: Request, res: Response) => {
    const log = getLogger().child({ module: 'auth', route: 'POST /api/auth/email/register' });

    try {
        const { client, email, password, locale } = await runWithLogger(log, () => validate(emailRegisterSchema, req.body))
        log.debug({ client, email, password, locale }, 'Register request received');

        const settings = await runWithLogger(log, () => getAuthSettings())
        const ur = new UserRepository();

        log.info('checking app settings');
        if (!settings.allowEmailRegistration) {
            log.info('Rejected registration: email registration disabled');
            return res.status(403).json({ status: 'error', error_code: 'EMAIL_REGISTRATION_DISABLED' });
        }

        log.info('fetching user data');
        if (await runWithLogger(log, () => ur.getByEmail(email!))) {
            log.info({ email }, 'Rejected registration: email already taken');
            // successful response is sent, to improve users privacy
            return res.status(204).json({ status: 'success' });
        }

        const passwordHash = await bcrypt.hash(password!, 12);
        log.debug({ passwordHash })
        log.info('hashed user\'s password')

        const redis = await Redis.getClient()

        log.info('storing user email and hashed password in redis')
        await redis.set(`email_registration:${email}`, `${email}:${passwordHash}`, 'EX', 120)

        log.info('sending SMTP verification code');
        const result = await runWithLogger(log, () => requestSmtp(email, locale))
        log.debug({ requestSmtpResult: result });
        if (result === 'cooldown') {
            log.info('Rejected SMTP request: cooldown active');
            return res.status(429).json({ status: 'error', error_code: 'SMTP_COOLDOWN' });
        }

        return res.status(204).json({ status: 'success' });
    } catch (err: any) {
        runWithLogger(log, () => handleError(res, err))
    }
});

router.post('/email/verify', unAuth, async (req: Request, res: Response) => {
    const log = getLogger().child({ module: 'auth', route: 'POST /api/auth/email/verify' });

    try {
        const { client, code, email, password, locale } = await runWithLogger(log, () => validate(emailVerifySchema, req.body))
        log.debug({ client, code, email, password, locale }, 'Register request received');

        const ur = new UserRepository();

        log.info('verifying SMTP verification code');
        if (!(await runWithLogger(log, () => verifySmtp(email, code!)))) {
            log.info('Rejected SMTP verification: invalid SMTP code');
            return res.status(400).json({ status: 'error', error_code: 'INVALID_INPUT' });
        }
        log.info('SMTP code verified successfully.');

        const redis = await Redis.getClient()

        log.info('fetching user email and hashed password in redis')
        const redisKey = `email_registration:${email}`
        const redisValue = await redis.get(`email_registration:${email}`)
        if (!redisValue) {
            log.info('failed to fetch user email and hashed password from redis')
            return res.status(400).json({ status: 'error', error_code: 'EMAIL_NOT_FOUND' })
        }
        const [redisEmail, redisPassword] = redisValue.split(':')

        log.info('validating user input against redis data')
        if (redisEmail !== email || await bcrypt.compare(password, redisPassword)) {
            log.info('invalid email or password provided')
            return res.status(400).json({ status: 'error', error_code: 'INVALID_INPUT' })
        }

        log.info('creating user data in db');
        const created = await runWithLogger(log, () => ur.create({
            authMethod: 'email',
            role: 'user',
            email,
            temporaryAvatar: true,
            password: redisPassword,
            language: 'fa',
            calendar: 'persian',
            timezone: 'utc',
        }))
        log.debug({ created })
        if (!created || !created.acknowledged) {
            log.error({ email }, 'User creation failed');
            return res.status(500).json({ status: 'error', error_code: 'CREATE_FAILED' });
        }
        const userId = created.insertedId.toString()
        log.info({ userId }, 'Registered new user');

        await redis.del(redisKey)
        log.info('deleted useless redis record')

        log.info('fetching user data');
        const user = await runWithLogger(log, () => ur.get(userId))
        if (!user) {
            log.error({ userId }, 'User fetch failed');
            return res.status(500).json({ status: 'error', error_code: 'FETCH_FAILED' });
        }

        const { accessToken, refreshToken } = await runWithLogger(log, () => issueTokens(res, userId, client, req.headers['user-agent']))

        if (client === 'web')
            return res.json({ status: 'success', data: { user, accessToken } });

        return res.json({ status: 'success', data: { user, accessToken, refreshToken } });
    } catch (err: any) {
        runWithLogger(log, () => handleError(res, err))
    }
});

router.post('/email/password-reset', unAuth, async (req: Request, res: Response) => {
    const log = getLogger().child({ module: 'auth', route: 'POST /api/auth/email/register' });

    try {
        const { client, email, locale } = await runWithLogger(log, () => validate(emailPasswordResetSchema, req.body))
        log.debug({ client, email, locale }, 'Register request received');

        const settings = await runWithLogger(log, () => getAuthSettings())
        const ur = new UserRepository();

        log.info('checking app settings');
        if (!settings.allowEmailRegistration) {
            log.info('Rejected registration: email registration disabled');
            return res.status(403).json({ status: 'error', error_code: 'EMAIL_REGISTRATION_DISABLED' });
        }

        log.info('fetching user with the email');
        if (!await runWithLogger(log, () => ur.getByEmail(email!))) {
            log.info({ email }, 'Rejected registration: email not found');
            // successful response is sent, to improve users privacy
            return res.status(204).json({ status: 'success' });
        }

        log.info('sending SMTP verification code');
        const result = await runWithLogger(log, () => requestSmtp(email, locale))
        log.debug({ requestSmtpResult: result });
        if (result === 'cooldown') {
            log.info('Rejected SMTP request: cooldown active');
            return res.status(429).json({ status: 'error', error_code: 'SMTP_COOLDOWN' });
        }

        return res.status(204).json({ status: 'success' });
    } catch (err: any) {
        runWithLogger(log, () => handleError(res, err))
    }
});

router.post('/email/password-reset/verify', unAuth, async (req: Request, res: Response) => {
    const log = getLogger().child({ module: 'auth', route: 'POST /api/auth/email/verify' });

    try {
        const { client, code, email, password, locale } = await runWithLogger(log, () => validate(emailPasswordResetVerifySchema, req.body))
        log.debug({ client, code, email, password, locale }, 'Register request received');

        const ur = new UserRepository();

        log.info('verifying SMTP verification code');
        if (!(await runWithLogger(log, () => verifySmtp(email, code!)))) {
            log.info('Rejected SMTP verification: invalid SMTP code');
            return res.status(400).json({ status: 'error', error_code: 'INVALID_INPUT' });
        }

        log.info('fetching user with the email');
        const user = await runWithLogger(log, () => ur.getByEmail(email))
        log.debug({ user })
        if (!user) {
            log.info('Rejected registration: email not found');
            // successful response is sent, to improve users privacy
            return res.status(204).json({ status: 'success' });
        }

        log.info('hashing new password and updating user password');
        const passwordHash = await bcrypt.hash(password!, 12);
        const updated = await runWithLogger(log, () => ur.unsafeUpdate(user._id.toString(), { email, password: passwordHash, }))
        log.debug({ updated })
        if (updated !== true) {
            log.error({ email }, 'User update failed');
            return res.status(500).json({ status: 'error', error_code: 'UPDATE_FAILED' });
        }

        log.info('issuing auth tokens');
        const { accessToken, refreshToken } = await runWithLogger(log, () => issueTokens(res, user._id.toString(), client, req.headers['user-agent']))

        if (client === 'web')
            return res.json({ status: 'success', data: { user, accessToken } });

        return res.json({ status: 'success', data: { user, accessToken, refreshToken } });
    } catch (err: any) {
        runWithLogger(log, () => handleError(res, err))
    }
});

router.post('/login', unAuth, async (req: Request, res: Response) => {
    const log = getLogger().child({ module: 'auth', route: 'POST /api/auth/login' });

    try {
        const { client, email, password } = await runWithLogger(log, () => validate(loginSchema, req.body))
        log.debug({ client, email, password }, 'Login request received');

        const ur = new UserRepository();

        const user = await runWithLogger(log, () => ur.getByEmail(email!))
        if (!user || !user.email || !user.password) {
            log.info({ email }, 'Rejected login: no matching account');
            return res.status(401).json({ status: 'error', error_code: 'INVALID_CREDENTIALS' });
        }

        const match = await bcrypt.compare(password!, user.password);
        if (!match) {
            log.info({ userId: user._id!.toString() }, 'Rejected login: password mismatch');
            return res.status(401).json({ status: 'error', error_code: 'INVALID_CREDENTIALS' });
        }

        log.info({ userId: user._id!.toString() }, 'Login succeeded (email)');
        const { accessToken, refreshToken } = await runWithLogger(log, () => issueTokens(res, user._id!.toString(), client, req.headers['user-agent']))

        if (client === 'web')
            return res.json({ status: 'success', data: { user, accessToken } });

        return res.json({ status: 'success', data: { user, accessToken, refreshToken } });
    } catch (err: any) {
        runWithLogger(log, () => handleError(res, err))
    }
});

router.post('/refresh', async (req: Request, res: Response) => {
    const log = getLogger().child({ module: 'auth', route: 'POST /api/auth/refresh' });

    try {
        const body = await runWithLogger(log, () => validate(refreshSchema, req.body ?? {}))

        const oldTokenId = body.refreshToken ?? req.cookies?.[REFRESH_COOKIE_NAME];
        if (!isProduction) log.debug({ oldTokenId })
        if (!oldTokenId) {
            log.info({ client: body.client }, 'Rejected refresh: no refresh token supplied');
            return res.status(401).json({ status: 'error', error_code: 'NO_REFRESH_TOKEN' });
        }

        let rotated;
        try {
            rotated = await runWithLogger(log, () => rotateRefreshToken(oldTokenId))
            if (!isProduction) log.debug({ rotated })
        } catch (err) {
            log.warn({ err, client: body.client }, 'Rejected refresh: token invalid, expired, or reused');
            runWithLogger(log, () => clearAuthCookies(res))
            return res.status(401).json({ status: 'error', error_code: 'REFRESH_INVALID' });
        }

        const { token: accessToken, exp } = signAccessToken(rotated.userId);
        log.info({ userId: rotated.userId, client: body.client }, 'Refreshed session');

        if (body.client === 'web') {
            setAuthCookies(res, accessToken, rotated.newTokenId, exp - Math.floor(Date.now() / 1000));
            return res.json({ status: 'success', data: { accessToken } });
        }

        res.json({ status: 'success', data: { accessToken, refreshToken: rotated.newTokenId } });
    } catch (err: any) {
        runWithLogger(log, () => handleError(res, err))
    }
});

router.post('/logout', async (req: Request, res: Response) => {
    const log = getLogger().child({ module: 'auth', route: 'POST /api/auth/logout' });

    try {
        const payload = runWithLogger(log, () => authenticateRequest(req))
        log.debug({ payload })
        if (!payload) {
            log.info('User is not authenticated');
            return res.status(401).send();
        }

        log.debug({ userId: payload?.userId }, 'Logout request received');
        const tokenId = req.body?.refreshToken ?? req.cookies?.[REFRESH_COOKIE_NAME];

        if (payload?.jti && payload?.exp)
            await runWithLogger(log, () => blacklistAccessToken(payload.jti!, payload.exp!))

        if (tokenId)
            await revokeSessionByTokenId(tokenId, payload.userId);

        runWithLogger(log, () => clearAuthCookies(res))
        log.info({ userId: payload?.userId }, 'Logged out');
        res.json({ status: 'success', data: null });
    } catch (err) {
        runWithLogger(log, () => handleError(res, err))
    }
});

router.post('/logout-all', auth, async (req: Request, res: Response) => {
    const log = getLogger().child({ module: 'auth', route: 'POST /api/auth/logout-all' });

    try {
        const payload = req.user as any;
        log.debug({ userId: payload?.userId }, 'Logout-all request received');

        await runWithLogger(log, () => revokeAllSessions(payload.userId))
        // Same jti/exp caveat as /logout above.
        if (payload?.jti && payload?.exp)
            await runWithLogger(log, () => blacklistAccessToken(payload.jti, payload.exp))

        runWithLogger(log, () => clearAuthCookies(res))
        log.info({ userId: payload?.userId }, 'Logged out of all sessions');
        res.json({ status: 'success', data: null });
    } catch (err) {
        runWithLogger(log, () => handleError(res, err))
    }
});

router.get('/sessions', auth, async (req: Request, res: Response) => {
    const log = getLogger().child({ module: 'auth', route: 'GET /api/auth/sessions' });

    try {
        const payload = req.user as any;
        log.debug({ userId: payload.userId }, 'Listing sessions');
        const sessions = await runWithLogger(log, () => listSessions(payload.userId))
        log.debug({ userId: payload.userId, sessionCount: sessions.length }, 'Sessions listed');
        res.json({ status: 'success', data: { sessions } });
    } catch (err) {
        runWithLogger(log, () => handleError(res, err))
    }
});

router.delete('/sessions/:familyId', auth, async (req: Request, res: Response) => {
    const log = getLogger().child({ module: 'auth', route: 'DELETE /api/auth/sessions/:familyId' });

    try {
        const familyId = await string().required().validate(req.params.familyId)
        const payload = req.user as any;
        log.debug({ userId: payload.userId, familyId }, 'Revoking session family');

        await runWithLogger(log, () => revokeFamily(req.params.familyId.toString(), payload.userId))

        log.info({ userId: payload.userId, familyId }, 'Session family revoked');
        res.json({ status: 'success', data: null });
    } catch (err) {
        runWithLogger(log, () => handleError(res, err))
    }
});

router.get('/admin/settings', auth, isAdminIfAuthenticated, async (req: Request, res: Response) => {
    const log = getLogger().child({ module: 'auth', route: 'GET /api/auth/admin/settings' });

    const settings = await runWithLogger(log, () => getAuthSettings())
    log.debug({ settings }, 'Fetched auth settings');
    res.json({ status: 'success', data: settings });
});

router.patch('/admin/settings', auth, isAdminIfAuthenticated, async (req: Request, res: Response) => {
    const log = getLogger().child({ module: 'auth', route: 'PATCH /api/auth/admin/settings' });

    try {
        const patch = await runWithLogger(log, () => validate(adminSettingsSchema, req.body))
        log.debug({ patch }, 'Updating auth settings');

        const updated = await updateAuthSettings(patch);
        log.info({ updated }, 'Auth settings updated');

        res.json({ status: 'success', data: updated });
    } catch (err: any) {
        runWithLogger(log, () => handleError(res, err))
    }
});

export { router as authRoutes }
