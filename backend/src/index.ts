// Must be imported before models
import { addYupMethods } from './db/common_schemas';
addYupMethods();

import express from 'express';
import https from 'https';
import fs from 'fs';

import { dbConfig, isProduction, allowedOrigins, hostPort, hostName, s3Endpoint, s3AccessKey, s3SecretKey } from './configs';

import { metricsMiddleware } from './observability/metrics';
import { metricsRouter } from './observability/metricsRoute';
import { healthRouter } from './observability/health';
import { httpLogger } from './observability/httpLogger';
import { logger } from './observability/logger';
import { startMetricsPush } from './observability/pushgateway';
import { setRequestLogger } from './observability/requestLoggerContext';

import { tryAndWait } from './utils';

import { MeiliCrud } from './db/meilisearch';

import { MongoDB } from './db/MongoDB/mongodb';
import { UserRepository } from './db/MongoDB/UserRepository';
import { InvalidTokensRepository } from './db/MongoDB/InvalidTokensRepository';
import AudioRepository from './db/MongoDB/AudioRepository';
import AppSettingsRepository from './db/MongoDB/AppSettingsRepository';
// import PlanRepository from './DB/repositories/PlanRepository';
// import SubscriptionRepository from './DB/repositories/SubscriptionRepository';
// import UsageRepository from './DB/repositories/UsageRepository';

import { runCronjobs } from './cronjobs';

// Must be before route imports
import { platform } from "os";
import path from 'path';
import ffmpeg from "fluent-ffmpeg";

const platformName = platform();

const ffmpegBinaryPath = platformName === "win32" ? path.join(process.cwd(), "src", "ffmpeg-8.1-essentials_build", "bin", "ffmpeg.exe") : path.join(process.cwd(), "src", "ffmpeg-7.0.2-amd64-static", "ffmpeg");
ffmpeg.setFfmpegPath(ffmpegBinaryPath);

const ffprobeBinaryPath = platformName === "win32" ? path.join(process.cwd(), "src", "ffmpeg-8.1-essentials_build", "bin", "ffprobe.exe") : path.join(process.cwd(), "src", "ffmpeg-7.0.2-amd64-static", "ffprobe");
ffmpeg.setFfprobePath(ffprobeBinaryPath);

export { ffmpeg };

import { audioRoutes } from './routes/audio/audio';
import { userRoutes } from './routes/user/user';
import { authRoutes } from './routes/auth/auth';
// import { planRoutes } from './routes/plan/plan';
// import { subscriptionRoutes } from './routes/subscription/subscription';

import { S3Client } from "@aws-sdk/client-s3";

import { Redis } from './db/redis';

import { generalRateLimiter } from './middlewares/rateLimiting';
import { toggleDebugMode } from './middlewares/auth';
import { notFoundHandler } from './middlewares/notFoundHandler';
import { errorHandler } from './middlewares/errorHandler';
import { requestContextMiddleware } from './middlewares/requestContext';
import { registerProcessErrorHandlers } from './middlewares/processErrorHandlers';

import { OtpFactory } from './services/OTP/OtpFactory';
import { PaymentFactory } from './services/Payments/factory';
import { SmtpFactory } from './services/SMTP/SmtpFactory';

export const s3 = new S3Client({
    region: 'us-east-1',
    followRegionRedirects: true,
    endpoint: s3Endpoint,
    credentials: {
        accessKeyId: s3AccessKey,
        secretAccessKey: s3SecretKey
    },
    forcePathStyle: true // often required for S3-compatible services
})

export const otpService = OtpFactory.instantiate()

export const smtpService = SmtpFactory.instantiate()

export const payments = {
    zarinpal: PaymentFactory.instantiate('zarinpal'),
    zibal: PaymentFactory.instantiate('zibal'),
    paypal: undefined!,
    bitcoin: undefined!,
};

(async () => {
    await MeiliCrud.setup();

    if (!await tryAndWait({
        onThrow(e) { console.error('redis tryAndWait throw and error', e); },
        callback: async () => {
            await Redis.connect()
        }
    }))
        throw new Error('Failed to prepare the Redis database.')

    if (!await tryAndWait({
        onThrow(e) { console.error('MongoDB tryAndWait throw and error', e); },
        callback: async () => {
            MongoDB.config = dbConfig

            const db = MongoDB.getDbInstance()

            await db.reset();

            db.addRepository(new AppSettingsRepository())
            // db.addRepository(new PlanRepository())
            // db.addRepository(new SubscriptionRepository())
            // db.addRepository(new UsageRepository())
            db.addRepository(new UserRepository())
            db.addRepository(new InvalidTokensRepository())
            db.addRepository(new AudioRepository())

            // if (!isProduction)
            //     await MongoDB.getDbInstance().dropSeedableCollections()

            await db.createCollections()

            // if (!isProduction)
            //     await db.seedCollections()
        }
    }))
        throw new Error('Failed to prepare the MongoDB database.')

    const app = express()

    // --- Observability middleware first, so it wraps everything downstream ---
    app.use(metricsMiddleware());

    app.use(httpLogger);

    app.use(requestContextMiddleware);

    app.use((req, res, next) => {
        setRequestLogger(req.log);
        next();
    });

    // --- Unauthenticated, network-restricted endpoints ---
    app.use(healthRouter); // /healthz, /readyz
    app.use(metricsRouter); // /metrics — scraped by Prometheus, not by users

    if (isProduction)
        app.set("trust proxy", 1);

    app.use(generalRateLimiter);

    app.use(toggleDebugMode)

    app.use(express.json())

    app.disable('x-powered-by')

    // CORS
    app.use((req, res, next) => {
        res.header('Access-Control-Allow-Origin', allowedOrigins)
        res.header('Access-Control-Allow-Credentials', 'true')
        res.header('Access-Control-Allow-Method', 'GET,POST,PUT,DELETE,OPTIONS')
        res.header('Access-Control-Allow-Headers', '*,authorization,Authorization,Content-Type')

        if (req.method === 'OPTIONS')
            res.sendStatus(204)
        else
            next()
    });

    const cookieParser = require('cookie-parser')
    app.use(cookieParser())

    if (!isProduction)
        app.get('/is_seeding', (req, res) => { res.status(200).json({ isSeeding: MongoDB.isSeeding() }) })

    if (!isProduction)
        app.get('/', (req, res) => {
            res.send('test route' + (new Date()).toISOString());
        });

    app.use('/api/auth', authRoutes);
    app.use('/api/user', userRoutes);
    app.use('/api/audio', audioRoutes);
    // app.use('/api/subscription', subscriptionRoutes);
    // app.use('/api/plan', planRoutes);

    app.use(notFoundHandler);
    app.use(errorHandler);

    let server
    if (!isProduction)
        server = https.createServer({
            key: fs.readFileSync('localhost+2-key.pem'),
            cert: fs.readFileSync('localhost+2.pem')
        }, app)
            .listen(hostPort, hostName, () => logger.info({ hostName, hostPort }, `listening on ${hostName}:${hostPort}...`))
    else
        // Server is behind NginX proxy in production
        server = app.listen(hostPort, hostName, () => logger.info({ hostName, hostPort }, `listening on ${hostName}:${hostPort}...`))

    startMetricsPush();

    runCronjobs()

    registerProcessErrorHandlers(server);
})()
