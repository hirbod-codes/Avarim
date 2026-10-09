// import express, { } from 'express';
// import { auth, authenticateToken } from '../../middlewares/auth';
// import { audioUploadTmpDir, BUCKET_NAME, ttsApiKey } from '../../configs';
// import AudioRepository from '../../db/MongoDB/AudioRepository';
// import { GetObjectCommand } from '@aws-sdk/client-s3';
// import { generateStreamToken, verifyStreamToken } from '../../lib/signed_urls';
// import { UserRepository } from '../../db/MongoDB/UserRepository';
// import { httpsStreamRequest } from '../../utils';
// import { s3 } from '../..';
// import { pipeline } from 'stream/promises';
// import { getLogger, runWithLogger } from '../../observability/requestLoggerContext';
// import { listQuerySchema, infoQuerySchema, signedTokenQuerySchema, ttsQuerySchema, fileParamsSchema, webFileParamsSchema, coverArtParamsSchema, deleteParamsSchema, postSchema } from './schemas';
// import { handleError, validate } from '../../lib';
// import { authorizeAllowedContentTypes, authorizeStorageQuota, rollbackStorageQuota } from '../../middlewares/authorization';
// import { deleteFromS3, detectContentType, getS3ObjectSize, receiveUpload, uploadToS3 } from '../../lib/file_management';
// import { extractCoverArt, generateWebCompatibleCopy, isWebCompatible, probeFile } from '../../ffmpeg';
// import { InvalidMediaError } from '../../errors/InvalidMediaError';
// import { join, basename } from 'path';
// import { Usage } from '../../db/models/Usage';
// import { UploadTooLargeError } from '../../errors/UploadTooLargeError';
// import { mkdir, unlink, rm, stat } from 'fs/promises';
// import { createWriteStream, createReadStream } from 'fs';
// import { streamAudioFile } from './lib';
// import UsageRepository from '../../db/MongoDB/UsageRepository';
// import { MongoDB } from '../../db/mongodb';
// import { subscriptionGate } from '../../middlewares/planGate';
// import { randomUUID } from 'crypto';

// const router = express.Router();

// const ALLOWED_AUDIO_CODECS = new Set([
//     'aac', 'mp3', 'opus', 'vorbis', 'flac', 'alac',
//     'pcm_s16le', 'pcm_s24le', 'pcm_f32le',
// ]);

// router.post('/', auth, subscriptionGate, async (req, res) => {
//     let log = getLogger().child({ module: 'audio', route: 'POST /api/audio/' });

//     try {
//         log.info('audio upload request received');

//         if (authorizeAllowedContentTypes(req, 'audio', res) !== true) {
//             log.info('authorization of allowed content types has failed')
//             return
//         }

//         log.debug({ query: req.query });
//         const { title } = await runWithLogger(log, () => validate(postSchema, req.query))
//         log.info('input validated');
//         log.debug({ title });

//         const userId = req.user!.userId
//         log = log.child({ userId });

//         const usageRepository = new UsageRepository();
//         const audioRepository = new AudioRepository()

//         // ------------------------------------------------------------------------- checking whether title already exists
//         log.info('checking whether title already exists')

//         const audio = await runWithLogger(log, () => audioRepository.getForUserByTitle(title, userId));
//         log.debug({ audio });
//         log.info('Checked title uniqueness');
//         if (audio) {
//             log.info('Rejected audio upload: title already exists');
//             return res.status(400).json({ status: 'error', message: 'Audio title must be unique.' });
//         }

//         // ------------------------------------------------------------------------- inserting audio
//         log.info('inserting audio')

//         const audioInsertResult = await runWithLogger(log, () => audioRepository.insert({ title: `${randomUUID()}__UNIQUE_SEPARATOR__${title}`, userId, temporary: true }))
//         log.debug({ audioInsertResult });
//         if (!audioInsertResult.acknowledged || !audioInsertResult.insertedId) {
//             log.error({ audioInsertResult }, 'temporary audio info creation failed');
//             return res.status(500).json({ status: 'error', message: 'Audio info creation failed' })
//         }
//         log.info('Inserted temporary audio info record');

//         const audioId = audioInsertResult.insertedId.toString()
//         log.debug({ audioId })

//         // ------------------------------------------------------------------------- make the temporary directory
//         log.info('make the temporary directory')

//         const jobDir = join(audioUploadTmpDir, audioId)
//         await mkdir(jobDir, { recursive: true });
//         log.debug({ jobDir });
//         log.info('Created job scratch directory');

//         const cleanupPaths: string[] = [];
//         const cleanup = async () => {
//             log.debug({ cleanupPaths, jobDir });
//             log.info('Cleaning up temp files');
//             await Promise.all(cleanupPaths.map((p) => unlink(p).catch(() => { })));
//             await rm(jobDir, { recursive: true, force: true }).catch(() => { });
//         };

//         let rollbackPromises: undefined | Promise<any> = undefined
//         try {
//             // ------------------------------------------------------------------------- fetch available storage bytes
//             log.info('fetch available storage bytes for user from user subscription and usage')

//             const maxTotalStorageBytes = req.user!.privileges!.storageBytes;
//             log.debug({ maxTotalStorageBytes }, 'Resolved plan storage limit');

//             const usage: Usage | undefined = await runWithLogger(log, () => usageRepository.getByUserId(userId))
//             log.debug({ usage })
//             if (!usage) {
//                 log.error("failed to find authenticated user's usage data")
//                 return res.status(500).json({ status: 'error', error_code: 'INTERNAL_ERROR' })
//             }
//             const allowedStorageBytes = maxTotalStorageBytes - usage.storageBytes
//             log.debug({ availableStorageBytes: allowedStorageBytes })

//             // ------------------------------------------------------------------------- store upload stream on disk
//             log.info('store upload stream on disk')

//             const { path: inputPath, size: inputSize } = await runWithLogger(log, () => receiveUpload(req, allowedStorageBytes, jobDir))
//             cleanupPaths.push(inputPath)
//             log.debug({ inputSize, inputPath })
//             log.info('Upload received and stored to disk')

//             // ------------------------------------------------------------------------- probe received file, get info and validate it
//             log.info('probe received file, get info and validate it')

//             const info = await runWithLogger(log, () => probeFile(inputPath))
//             const audioStream = info.streams.find((s) => s.codec_type === 'audio')
//             log.debug({ audioCodec: audioStream?.codec_name })
//             log.info('Probed uploaded file')
//             if (!audioStream || !ALLOWED_AUDIO_CODECS.has(audioStream.codec_name)) {
//                 log.warn({ codec: audioStream?.codec_name }, 'Rejected audio upload: unsupported codec')
//                 throw new InvalidMediaError('Unsupported or unrecognized audio format')
//             }

//             // ------------------------------------------------------------------------- set bucket keys
//             log.info('set bucket keys')

//             const isUploadWebCompatible = runWithLogger(log, () => isWebCompatible(undefined, audioStream))
//             const audioFileBucketKey = `audio/${userId}/${audioId}`
//             const webCompatibleAudioFileBucketKey = isUploadWebCompatible ? undefined : `audio/${userId}/web/${audioId}`
//             const coverArtBucketKey = `audio/cover_art/${userId}/${audioId}`
//             log.debug({ isUploadWebCompatible, audioFileBucketKey, webCompatibleAudioFileBucketKey, coverArtBucketKey })
//             log.info('Computed bucket keys')

//             // ------------------------------------------------------------------------- set file paths
//             log.info('set file paths')

//             const webCopyPath = isUploadWebCompatible ? undefined : join(jobDir, `${audioId}-web.m4a`)
//             if (webCopyPath) cleanupPaths.push(webCopyPath);

//             // ffmpeg writes to this intermediate file; its stream is then copied to webCopyPath.
//             // It MUST differ from webCopyPath, otherwise the copy truncates its own source.
//             const webCopyGenName = `${audioId}-web-gen`
//             log.debug({ webCopyPath, webCopyGenName });
//             log.info('Resolved output paths');

//             // ------------------------------------------------------------------------- generate web copy, extract cover art, detect content type
//             log.info('wait for web compatible file and cover art to be generated and content type to be collected')

//             const [contentType, coverArtResult] = await Promise.all([
//                 runWithLogger(log, () => detectContentType(inputPath)
//                     .then((ct) => {
//                         log.debug({ contentType: ct }, 'Detected content type');
//                         return ct;
//                     })),
//                 runWithLogger(log, () => extractCoverArt(inputPath, info.streams, jobDir, `${audioId}-thumb`)
//                     .then((r) => {
//                         log.debug({ found: !!r }, 'Cover art extraction attempted');
//                         return r;
//                     })),
//                 isUploadWebCompatible
//                     ? Promise.resolve()
//                     : runWithLogger(log, () => generateWebCompatibleCopy(inputPath, jobDir, webCopyGenName, undefined, audioStream)
//                         .then((result) => pipeline(result.outputStream, createWriteStream(webCopyPath!)))
//                         .then(() => log.debug('Web-compatible copy written to disk'))),
//             ]);
//             // The cover art extension depends on the embedded image's codec (jpg/png/...), so use the real path
//             if (coverArtResult) cleanupPaths.push(coverArtResult.path);
//             log.debug({ isUploadWebCompatible, coverArtResult });
//             log.info('Generated web compatible file and cover art');

//             // ------------------------------------------------------------------------- authorize generated file sizes
//             log.info('authorize generated file sizes')

//             // Only stat files that actually exist
//             const [coverArtStat, webCopyStat] = await Promise.all([
//                 coverArtResult ? stat(coverArtResult.path) : Promise.resolve(undefined),
//                 webCopyPath ? stat(webCopyPath) : Promise.resolve(undefined),
//             ]);
//             const totalFilesBytes = inputSize + (webCopyStat?.size ?? 0) + (coverArtStat?.size ?? 0);
//             log.debug({ inputSize, webCopyBytes: webCopyStat?.size, coverArtBytes: coverArtStat?.size, totalFilesBytes });

//             if ((await authorizeStorageQuota(req, totalFilesBytes, undefined, res)) !== true) {
//                 log.info({ totalFilesBytes }, 'Rejected audio upload: exceeds plan storage limit')
//                 throw new UploadTooLargeError('Generated files exceed plan storage limit')
//             }
//             log.info('Storage quota authorized')

//             try {
//                 // ------------------------------------------------------------------------- upload files to the S3 compatible object storage
//                 log.info('upload files to the S3 compatible object storage')

//                 await Promise.all([
//                     runWithLogger(log, () => uploadToS3(createReadStream(inputPath), audioFileBucketKey, contentType.mimeType)),
//                     ...(webCopyPath ? [runWithLogger(log, () => uploadToS3(createReadStream(webCopyPath), webCompatibleAudioFileBucketKey!, 'audio/mp4'))] : []),
//                     ...(coverArtResult ? [runWithLogger(log, () => uploadToS3(createReadStream(coverArtResult.path), coverArtBucketKey, coverArtResult.mimeType))] : []),
//                 ]);
//                 log.debug({ audioFileBucketKey, webCompatibleAudioFileBucketKey, hasCoverArt: !!coverArtResult, totalFilesBytes });
//                 log.info('Uploaded files to object storage');

//                 // ------------------------------------------------------------------------- update audio info in DB
//                 log.info('update audio info in DB, make it permanent and set content type')

//                 const updateResult = await runWithLogger(log, () => audioRepository.unsafeUpdate(
//                     audioId,
//                     userId,
//                     {
//                         title,
//                         contentType: contentType,
//                         temporary: false,
//                         bucketKey: audioFileBucketKey,
//                         webBucketKey: webCompatibleAudioFileBucketKey,
//                         coverArtKey: coverArtResult ? coverArtBucketKey : undefined,
//                         totalFilesBytes,
//                         coverArtFileName: coverArtResult ? basename(coverArtResult.path) : undefined,
//                     }
//                 ));
//                 log.debug({ updateResult });
//                 if (!updateResult.acknowledged || updateResult.matchedCount !== 1) {
//                     log.info('updating audio record failed');
//                     throw new Error('failed to upload audio')
//                 }
//                 log.info('Updated audio record');
//                 log.info({ totalFilesBytes }, 'Audio upload finalized');
//             } catch (error) {
//                 log.error({ err: error }, 'Post-upload finalization failed, rolling back stored artifacts');
//                 rollbackPromises = Promise.allSettled([
//                     runWithLogger(log, () => deleteFromS3(audioFileBucketKey).catch((err) => { log.error({ err }, 'deleting audio files from cloud storage failed') })),
//                     ...(webCompatibleAudioFileBucketKey ? [runWithLogger(log, () => deleteFromS3(webCompatibleAudioFileBucketKey).catch((err) => { log.error({ err }, 'deleting web compatible audio files from cloud storage failed') }))] : []),
//                     ...(coverArtResult ? [runWithLogger(log, () => deleteFromS3(coverArtBucketKey).catch((err) => { log.error({ err }, 'deleting cover art files from cloud storage failed') }))] : []),
//                     runWithLogger(log, () => audioRepository.delete(audioId).catch((err) => { log.error({ err }, 'deleting audio info from db failed') })),
//                     runWithLogger(log, () => rollbackStorageQuota(userId, totalFilesBytes)).catch((err) => { log.error({ err, userId, totalStorageBytes: totalFilesBytes }, 'failed to decrement user usage') }),
//                 ])

//                 throw error
//             }
//         } catch (err) {
//             if (err instanceof UploadTooLargeError) {
//                 if (!res.headersSent) res.status(402).json({ status: 'error', error: err.message });
//                 return;
//             } else if (err instanceof InvalidMediaError) {
//                 if (!res.headersSent) res.status(400).json({ status: 'error', error: err.message });
//                 return;
//             } else {
//                 log.error({ err }, 'Audio upload failed');
//                 if (!res.headersSent) res.status(500).json({ status: 'error', error: 'Upload failed' });
//                 return;
//             }
//         } finally {
//             await cleanup();
//             if (rollbackPromises !== undefined) {
//                 await rollbackPromises;
//                 log.info('Rollback of stored artifacts completed');
//             }
//         }

//         res.status(201).json({ status: 'success', data: audioId });
//     } catch (err) {
//         runWithLogger(log, () => handleError(res, err))
//     }
// })

// router.get('/', auth, subscriptionGate, async (req, res) => {
//     let log = getLogger().child({ module: 'audio', route: 'GET /api/audio/' });

//     try {
//         log.info('Audio list request received');

//         log.debug({ query: req.query });
//         const { page, pageSize } = await runWithLogger(log, () => validate(listQuerySchema, req.query));
//         log.info('Input validated');
//         log.debug({ page, pageSize });

//         const userId = req.user!.userId;
//         log = log.child({ userId, page, pageSize });

//         const audioRepository = new AudioRepository();

//         const skip = (page - 1) * pageSize;
//         const [items, total] = await Promise.all([
//             runWithLogger(log, () => audioRepository.getPageForUser(userId, skip, pageSize)),
//             runWithLogger(log, () => audioRepository.countForUser(userId)),
//         ]);
//         log.debug({ count: items.length, total });
//         log.info('Fetched audio page');

//         const totalPages = Math.max(1, Math.ceil(total / pageSize));
//         log.info({ totalPages }, 'Listed audios');

//         res.status(200).json({ status: 'success', data: { items, page, pageSize, total, totalPages, hasMore: page < totalPages, } });
//     } catch (err) {
//         runWithLogger(log, () => handleError(res, err));
//     }
// });

// router.get('/info/', auth, subscriptionGate, async (req, res) => {
//     let log = getLogger().child({ module: 'audio', route: 'GET /api/audio/info/' });

//     try {
//         log.info('Audio info request received');

//         log.debug({ query: req.query });
//         const { audioId, title } = await runWithLogger(log, () => validate(infoQuerySchema, req.query));
//         log.info('Input validated');
//         log.debug({ audioId, title });

//         const userId = req.user!.userId;
//         log = log.child({ userId, audioId, title });

//         const audioRepository = new AudioRepository();

//         const result = audioId
//             ? await runWithLogger(log, () => audioRepository.getForUser(audioId, userId))
//             : await runWithLogger(log, () => audioRepository.getForUserByTitle(title!, userId));
//         log.debug({ result });
//         log.info('Looked up audio info');

//         if (!result) {
//             log.info('Audio not found');
//             return res.status(404).json({ status: 'error', message: 'Audio not found' });
//         }

//         res.status(200).json({ status: 'success', data: result });
//     } catch (err) {
//         runWithLogger(log, () => handleError(res, err));
//     }
// });

// router.get('/singed_token', auth, subscriptionGate, async (req, res) => {
//     let log = getLogger().child({ module: 'audio', route: 'GET /api/audio/singed_token' });

//     try {
//         log.info('Signed token request received');

//         log.debug({ query: req.query });
//         const { audioId } = await runWithLogger(log, () => validate(signedTokenQuerySchema, req.query));
//         log.info('Input validated');
//         log.debug({ audioId });

//         const userId = req.user!.userId;
//         log = log.child({ userId, audioId });

//         const audioRepository = new AudioRepository();

//         const audio = await runWithLogger(log, () => audioRepository.getForUser(audioId, userId));
//         log.debug({ audio });
//         log.info('Checked audio ownership');
//         if (!audio) {
//             log.info('Rejected signed token request: audio not found');
//             return res.status(404).json({ status: 'error', message: 'Audio not found' });
//         }

//         const token = generateStreamToken(audioId, userId);
//         log.info('Issued signed stream token');

//         res.status(200).json({ status: 'success', data: token });
//     } catch (err) {
//         runWithLogger(log, () => handleError(res, err));
//     }
// });

// router.get('/tts', auth, subscriptionGate, async (req, res) => {
//     let log = getLogger().child({ module: 'audio', route: 'GET /api/audio/tts' });

//     try {
//         log.info('TTS request received');

//         // Deliberately not logging raw query: contains user content (`text`) and secrets (`token`/`authToken`).
//         const { text, authToken, userTtsApiKey: userTtsApiKeyInput } = await runWithLogger(log, () => validate(ttsQuerySchema, req.query));
//         log.info('Input validated');
//         log.debug({ textLength: text.length, hasUserApiKey: !!userTtsApiKeyInput });

//         const result = authenticateToken(authToken);
//         if (result === false) {
//             log.warn('Rejected TTS request: invalid auth token');
//             return res.status(401).json({ status: 'error', message: 'Unauthorized' });
//         }

//         const userId = (result as any).userId;
//         log = log.child({ userId });

//         let userTtsApiKey = userTtsApiKeyInput;
//         if (!userTtsApiKey) {
//             const ur = new UserRepository();
//             const user = await runWithLogger(log, () => ur.get(userId));
//             log.debug({ user });
//             if (!user) {
//                 log.warn('Rejected TTS request: user not found for authenticated token');
//                 return res.status(401).json({ status: 'error', message: 'Unauthorized' });
//             }

//             if (user.role !== 'admin' && req.user?.planTitle === 'free') {
//                 log.info({ plan: req.user?.planTitle }, 'Rejected TTS request: plan does not include TTS');
//                 return res.status(403).json({ status: 'error', message: 'Your plan does not include text-to-speech' });
//             }

//             if (!ttsApiKey) {
//                 log.warn('Rejected TTS request: no server-side TTS API key configured');
//                 return res.status(400).json({ status: 'error', message: 'This feature is currently unavailable' });
//             }
//             userTtsApiKey = ttsApiKey;
//             log.debug('Using server-side TTS API key');
//         } else {
//             log.debug('Using user-supplied TTS API key');
//         }

//         log.info('Requesting TTS audio from upstream provider');
//         const stream = await runWithLogger(log, () => httpsStreamRequest(
//             { hostname: 'api.gapgpt.app', path: '/v1/audio/speech', method: 'POST', headers: { 'Authorization': `Bearer ${userTtsApiKey}`, 'Content-Type': 'application/json' } },
//             JSON.stringify({ model: 'gemini-2.5-flash-preview-tts', input: text, voice: 'achernar', response_format: 'mp3' })
//         ));

//         stream.on('error', (e) => {
//             log.error({ err: e }, 'TTS upstream stream error');
//             if (!res.headersSent) return runWithLogger(log, () => handleError(res, e));
//             res.destroy();
//         });

//         log.info('Streaming TTS audio to client');
//         stream.pipe(res);
//     } catch (err) {
//         runWithLogger(log, () => handleError(res, err));
//     }
// });

// // there are separate routes for downloading audio because web's media player doesn't support using authorization headers, therefor it uses signed urls instead.
// // For non web applications
// router.get('/file/:audioId', auth, subscriptionGate, async (req, res) => {
//     let log = getLogger().child({ module: 'audio', route: 'GET /api/audio/file/:audioId' });

//     try {
//         log.info('Audio file request received');

//         log.debug({ params: req.params, query: req.query, range: req.headers.range });
//         const { audioId, download: temp } = await runWithLogger(log, () => validate(fileParamsSchema, { ...req.params, ...req.query }));
//         let download: boolean = temp === 'true'
//         log.info('Input validated');
//         log.debug({ audioId, download });

//         log = log.child({ userId: req.user!.userId, audioId, download });

//         await streamAudioFile(audioId, req.user!.userId, req, res, false, download, log);
//     } catch (err) {
//         runWithLogger(log, () => handleError(res, err));
//     }
// });

// // For web applications
// router.get('/file/web/:audioId/:token', async (req, res) => {
//     let log = getLogger().child({ module: 'audio', route: 'GET /api/audio/file/:audioId/:token' });

//     try {
//         log.info('Web audio file request received');

//         log.debug({ params: { audioId: req.params.audioId }, query: req.query, range: req.headers.range });
//         const { audioId, token, download: temp } = await runWithLogger(log, () => validate(webFileParamsSchema, { ...req.params, ...req.query }));
//         let download: boolean = temp === 'true'
//         log.info('Input validated');
//         log.debug({ audioId, download });

//         log = log.child({ audioId, download });

//         const { valid, userId } = verifyStreamToken(token, audioId);
//         log.debug({ valid });
//         log.info('Verified stream token');
//         if (valid !== true || !userId) {
//             log.warn('Rejected web audio file request: invalid or expired token');
//             return res.status(401).json({ status: 'error', message: 'Unauthorized' });
//         }
//         log = log.child({ userId });

//         await streamAudioFile(audioId, userId, req, res, true, download, log);
//     } catch (err) {
//         runWithLogger(log, () => handleError(res, err));
//     }
// });

// router.get('/coverArt/:audioId', auth, subscriptionGate, async (req, res) => {
//     let log = getLogger().child({ module: 'audio', route: 'GET /api/audio/coverArt/:audioId' });

//     try {
//         log.info('Cover art request received');

//         log.debug({ params: req.params, query: req.query });
//         const { audioId, download: temp } = await runWithLogger(log, () => validate(coverArtParamsSchema, { ...req.params, ...req.query }));
//         let download: boolean = temp === 'true'
//         log.info('Input validated');
//         log.debug({ audioId, download });

//         log = log.child({ userId: req.user!.userId, audioId, download });

//         const userId = req.user!.userId;

//         const audioRepository = new AudioRepository();

//         const audio = await runWithLogger(log, () => audioRepository.getForUser(audioId, userId));
//         log.debug({ audio });
//         log.info('Checked audio ownership');
//         if (!audio || !audio.coverArtKey || !audio.coverArtFileName) {
//             log.info('Rejected cover art request: audio not found or has no cover art');
//             return res.status(404).json({ status: 'error', message: 'Audio not found' });
//         }

//         const result = await runWithLogger(log, () => s3.send(new GetObjectCommand({
//             Bucket: BUCKET_NAME,
//             Key: audio.coverArtKey,
//             ResponseContentDisposition: download ? `attachment; filename="${audio.coverArtFileName}"` : undefined,
//         })));
//         log.debug({ contentLength: result.ContentLength, contentType: result.ContentType });
//         log.info('Fetched cover art from storage');

//         const stream = result.Body as any;
//         if (stream === undefined || stream === null) {
//             log.warn('Cover art object has no body');
//             return res.status(404).json({ status: 'error', message: 'Audio not found' });
//         }

//         res.setHeader('Accept-Ranges', 'bytes');
//         res.setHeader('Content-Type', result.ContentType || 'application/octet-stream');
//         res.status(200);
//         res.setHeader('Content-Length', result.ContentLength ?? '');

//         log.info('Streaming cover art to client');
//         stream.pipe(res);
//     } catch (err) {
//         runWithLogger(log, () => handleError(res, err));
//     }
// });

// router.delete('/:audioId', auth, subscriptionGate, async (req, res) => {
//     let log = getLogger().child({ module: 'audio', route: 'DELETE /api/audio/:audioId' });

//     let db: MongoDB | undefined = undefined
//     try {
//         log.info('Audio delete request received');

//         log.debug({ params: req.params });
//         const { audioId } = await runWithLogger(log, () => validate(deleteParamsSchema, req.params));
//         log.info('Input validated');
//         log.debug({ audioId });

//         const userId = req.user!.userId;
//         log = log.child({ userId, audioId });

//         db = MongoDB.getDbInstance()

//         // sessions are set after in case s3 storage deletion process gets interrupted
//         const session = await db.startTransaction()

//         const audioRepository = new AudioRepository();
//         audioRepository.setTransactionSession(session)

//         const usageRepository = new UsageRepository();
//         usageRepository.setTransactionSession(session)

//         const audio = await runWithLogger(log, () => audioRepository.getForUser(audioId, userId));
//         log.debug({ audio });
//         log.info('Checked audio ownership');
//         if (!audio) {
//             log.info('Rejected audio delete request: audio not found');
//             res.status(404).json({ status: 'error', message: 'Audio not found' });
//             await db.abortTransaction()
//             return
//         }

//         const r = await runWithLogger(log, () => audioRepository.unsafeUpdate(audioId, userId, { title: `deletionQueued_${audio.title}`, deletionQueued: true }));
//         log.debug({ updateResult: r });
//         if (!r.acknowledged || r.matchedCount) {
//             log.error({ updateResult: r }, 'Failed to mark audio temporary before delete');
//             res.status(500).json({ status: 'error', message: 'Error deleting audio' });
//             await db.abortTransaction()
//             return
//         }
//         log.info('Marked audio temporary before delete');

//         const promises = []
//         if (audio?.bucketKey) {
//             log.info('Deleting audio file from storage');
//             promises.push(runWithLogger(log, () => deleteFromS3(audio.bucketKey!)))
//             log.debug({ key: audio.bucketKey });
//         }

//         if (audio?.webBucketKey) {
//             log.info('Deleting web audio file from storage');
//             promises.push(runWithLogger(log, () => deleteFromS3(audio.webBucketKey!)))
//             log.debug({ key: audio.webBucketKey });
//         }

//         if (audio?.coverArtKey) {
//             log.info('Deleting cover art from storage');
//             promises.push(runWithLogger(log, () => deleteFromS3(audio.coverArtKey!)))
//             log.debug({ key: audio.coverArtKey });
//         }

//         const results = await Promise.allSettled(promises)
//         log.debug({ results })
//         const rejected = results.filter((r): r is PromiseRejectedResult => r.status === 'rejected');
//         log.info(
//             {
//                 fulfilledCount: results.length - rejected.length,
//                 rejectedCount: rejected.length,
//                 ...(rejected.length > 0 && { errors: rejected.map(r => r.reason instanceof Error ? r.reason.message : r.reason) }),
//             },
//             'handled all the object deletions from s3 storage'
//         );

//         if (rejected.length > 0) {
//             log.info({ rejectedLength: rejected.length }, `failed to delete objects in s3 storage`)
//             res.status(500).json({ status: 'error', error_code: 'INTERNAL_ERROR' })
//             await db.abortTransaction()
//             return
//         }

//         if (audio.totalFilesBytes) {
//             if (!(await runWithLogger(log, () => rollbackStorageQuota(userId, audio.totalFilesBytes!, usageRepository)))) {
//                 log.info(`failed to decrease user storage bytes usage by ${audio.totalFilesBytes}`)
//                 await db.abortTransaction()
//                 res.status(500).json({ status: 'error', error_code: 'INTERNAL_ERROR' })
//                 return
//             }
//             log.info(`decreased user storage bytes usage by ${audio.totalFilesBytes}`)
//         }

//         const rr = await runWithLogger(log, () => audioRepository.delete(audioId));
//         log.debug({ deleteResult: rr });
//         if (!rr.acknowledged) {
//             log.error({ deleteResult: rr }, 'Failed to delete audio record from DB');
//             await db.abortTransaction()
//             res.status(500).json({ status: 'error', message: 'Error deleting audio' });
//             return
//         }
//         log.info('Deleted audio record in DB')

//         await db.commitTransaction()

//         log.info('audio deleted successfully');
//         res.status(204).json({ status: 'success' });
//     } catch (err) {
//         runWithLogger(log, () => handleError(res, err));
//         await db?.abortTransaction()
//     }
// });

// export { router as audioRoutes };