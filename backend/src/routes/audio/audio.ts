import express from 'express';
import { auth, isAdminIfAuthenticated } from '../../middlewares/auth';
import { audioUploadTmpDir } from '../../configs';
import AudioRepository from '../../db/MongoDB/AudioRepository';
import { generateStreamToken, verifyStreamToken } from '../../lib/signed_urls';
import { pipeline } from 'stream/promises';
import { getLogger, runWithLogger } from '../../observability/requestLoggerContext';
import { listQuerySchema, infoQuerySchema, signedTokenQuerySchema, fileParamsSchema, webFileParamsSchema, coverArtParamsSchema, deleteParamsSchema, postSchema, isUploadFinished, isTitleUnique, titleUpdateSchema, lyricsUpdateSchema, albumUpdateSchema, artistUpdateSchema, tagUpdateSchema } from './schemas';
import { handleError, validate } from '../../lib';
import { deleteFromS3, detectContentType, getS3ObjectStream, receiveUpload, uploadToS3 } from '../../lib/file_management';
import { generateWebCompatibleCopy, isWebCompatible } from '../../ffmpeg';
import { InvalidMediaError } from '../../errors/InvalidMediaError';
import { join, basename } from 'path';
import { UploadTooLargeError } from '../../errors/UploadTooLargeError';
import { mkdir, unlink, rm } from 'fs/promises';
import { createWriteStream, createReadStream } from 'fs';
import { ExtractedCover, extractMetadata, prepareAudioInDb, streamAudioFile } from './lib';
import { MongoDB } from '../../db/MongoDB/mongodb';
import { randomUUID } from 'crypto';
import { meiliAlbum, meiliArtist, meiliAudio, meiliPlaylistAudio } from '../../db/meilisearch';
import { Audio } from '../../db/models/Audio';
import { Readable } from 'stream';
import ArtistRepository from '../../db/MongoDB/ArtistRepository';
import AlbumRepository from '../../db/MongoDB/AlbumRepository';
import ArtistAlbumAudioRepository from '../../db/MongoDB/ArtistAlbumAudioRepository';

const router = express.Router();

const ALLOWED_AUDIO_CODECS = new Set([
    'aac', 'mp3', 'opus', 'vorbis', 'flac', 'alac',
    'pcm_s16le', 'pcm_s24le', 'pcm_f32le', 'wav'
]);

const AUDIO_TITLE_SEPARATOR = '__AUDIO_TITLE_SEPARATOR__'

router.get('/is_title_unique', auth, isAdminIfAuthenticated, async (req, res) => {
    let log = getLogger().child({ module: 'audio', route: 'Get /api/audio/is_title_unique' });

    try {
        log.info('audio title uniqueness check request received');

        log.debug({ query: req.query });
        const { title } = await runWithLogger(log, () => validate(isTitleUnique, req.query))
        log.info('input validated');
        log.debug({ title });

        const userId = req.user!.userId
        log = log.child({ userId });

        const audioRepository = new AudioRepository()

        // ------------------------------------------------------------------------- checking whether title already exists
        log.info('checking whether title already exists')

        const audio = await runWithLogger(log, () => audioRepository.getByTitle(title));
        log.debug({ audio });
        if (audio) {
            log.info('Rejected audio upload: title already exists');
            return res.status(400).json({ status: 'error', error_code: 'TITLE_NOT_UNIQUE' });
        }

        res.status(204).json({ status: 'success', data: true })
    } catch (err) {
        runWithLogger(log, () => handleError(res, err))
    }
})

router.get('/is_upload_finished', auth, isAdminIfAuthenticated, async (req, res) => {
    let log = getLogger().child({ module: 'audio', route: 'GET /api/audio/is_upload_finished' });

    try {
        log.info('audio upload finish check request received');

        log.debug({ query: req.query });
        const { audioId } = await runWithLogger(log, () => validate(isUploadFinished, req.query))
        log.info('input validated');
        log.debug({ audioId });

        const userId = req.user!.userId
        log = log.child({ userId });

        const audioRepository = new AudioRepository()

        // ------------------------------------------------------------------------- checking whether title already exists
        log.info('checking whether title already exists')

        const audio = await runWithLogger(log, () => audioRepository.getUnsafe(audioId));
        log.debug({ audio });

        if (!audio) return res.status(400).json({ status: 'error', error_code: 'JOB_FAILED' });

        audio.temporary !== true ? res.status(201).json({ status: 'success', data: true }) : res.status(200).json({ status: 'queued', error_code: 'UNFINISHED_UPLOAD' })
    } catch (err) {
        runWithLogger(log, () => handleError(res, err))
    }
})

router.post('/', auth, isAdminIfAuthenticated, async (req, res) => {
    let log = getLogger().child({ module: 'audio', route: 'POST /api/audio/' });

    try {
        log.info('audio upload request received');

        log.debug({ query: req.query });
        const { title: userTitle } = await runWithLogger(log, () => validate(postSchema, req.query));
        log.info('Input validated');
        log.debug({ userTitle });

        const userId = req.user!.userId
        log = log.child({ userId });

        const audioRepository = new AudioRepository()

        if (userTitle) {
            // ------------------------------------------------------------------------- checking whether title already exists
            log.info('checking whether title already exists')

            const sameTitleCheck = await runWithLogger(log, () => audioRepository.getByTitle(userTitle));
            log.debug({ sameTitleCheck });
            if (sameTitleCheck) {
                log.info('Rejected audio upload: audio title already exists');
                return res.status(400).json({ status: 'error', error_code: 'AUDIO_TITLE_NOT_UNIQUE' });
            }
        }

        // ------------------------------------------------------------------------- make the temporary directory
        log.info('make the temporary directory')

        const jobDir = join(audioUploadTmpDir, randomUUID() + Date.now().toString())
        await mkdir(jobDir, { recursive: true });
        log.debug({ jobDir });
        log.info('Created job scratch directory');

        const cleanupPaths: string[] = [];
        const cleanup = async () => {
            log.debug({ cleanupPaths, jobDir });
            log.info('Cleaning up temp files');
            await Promise.all(cleanupPaths.map((p) => unlink(p).catch(() => { })));
            await rm(jobDir, { recursive: true, force: true }).catch(() => { });
        };

        let rollbackPromises: undefined | Promise<any> = undefined
        let temporaryAudio: Audio & { _id?: any }
        try {
            // ------------------------------------------------------------------------- store upload stream on disk
            log.info('store upload stream on disk')

            const { path: inputPath, size: inputSize } = await runWithLogger(log, () => receiveUpload(req, undefined, jobDir))
            cleanupPaths.push(inputPath)
            log.debug({ inputSize, inputPath })
            log.info('Upload received and stored to disk')

            // ------------------------------------------------------------------------- extract metadata from received file
            log.info('extract metadata from received file')

            const metadata = await runWithLogger(log, () => extractMetadata(inputPath, basename(inputPath)))
            log.debug({ metadata: { ...metadata, covers: metadata.covers.map(m => ({ ...m, data: [] })) } }) // removing cover arts bytes from logs
            const audioStream = metadata.probe.streams.find((s) => s.codec_type === 'audio');
            log.debug({ audioStream })
            log.info('extracted metadata from uploaded file')

            if (!audioStream || !ALLOWED_AUDIO_CODECS.has(audioStream.codec_name)) {
                log.warn({ codec: audioStream?.codec_name }, 'Rejected audio upload: unsupported codec')
                throw new InvalidMediaError('Unsupported or unrecognized audio format')
            }

            // ------------------------------------------------------------------------- resolving cover art
            log.info('resolving cover art')

            let cover: ExtractedCover | undefined = undefined
            if (metadata.covers.length > 0)
                cover = metadata.covers[metadata.suggestedCoverIndex ?? 0]
            log.debug({ cover: { ...cover, data: [] } })

            // ------------------------------------------------------------------------- resolving title
            log.info('resolving title')

            const fileNameSegments = basename(inputPath).split('.')
            if (fileNameSegments.length > 1) fileNameSegments.pop()
            const title = metadata.tags.audioTitle ?? userTitle ?? fileNameSegments[fileNameSegments.length - 1]
            log.debug({ title })

            // ------------------------------------------------------------------------- checking whether title or sha256 already exists
            log.info('checking whether title or sha256 already exists')

            const uniquenessCheck = await runWithLogger(log, () => audioRepository.getByAudioSha256(metadata.technical.audioSha256));
            log.debug({ uniquenessCheck });
            if (uniquenessCheck) {
                log.info('Rejected audio upload: audio already exists');
                return res.status(400).json({ status: 'error', error_code: 'AUDIO_NOT_UNIQUE' });
            }

            // ------------------------------------------------------------------------- inserting audio
            log.info('inserting audio')

            temporaryAudio = { title: `${randomUUID()}${AUDIO_TITLE_SEPARATOR}${title}`, temporary: true, isPrepared: false, tags: metadata.tags, technical: metadata.technical }
            const audioInsertResult = await runWithLogger(log, () => audioRepository.insert(temporaryAudio))
            log.debug({ audioInsertResult });
            if (!audioInsertResult.acknowledged || !audioInsertResult.insertedId) {
                log.error({ audioInsertResult }, 'temporary audio info creation failed');
                return res.status(500).json({ status: 'error', message: 'Audio info creation failed' })
            }
            temporaryAudio._id = audioInsertResult.insertedId;
            log.info('Inserted temporary audio info record');

            const audioId = audioInsertResult.insertedId.toString()
            log.debug({ audioId })

            res.status(200).json({ status: 'queued', data: { id: temporaryAudio._id.toString() } })

            // ------------------------------------------------------------------------- set bucket keys
            log.info('set bucket keys')

            const isUploadWebCompatible = runWithLogger(log, () => isWebCompatible(undefined, audioStream))
            const audioFileBucketKey = `avarim/audio/${audioId}`
            const webCompatibleAudioFileBucketKey = isUploadWebCompatible ? undefined : `avarim/audio/web/${audioId}`
            const coverArtBucketKey = `avarim/audio/cover_art/${audioId}`
            log.debug({ isUploadWebCompatible, audioFileBucketKey, webCompatibleAudioFileBucketKey, coverArtBucketKey })
            log.info('Computed bucket keys')

            // ------------------------------------------------------------------------- set file paths
            log.info('set file paths')

            const webCopyPath = isUploadWebCompatible ? undefined : join(jobDir, `${audioId}-web.m4a`)
            if (webCopyPath) cleanupPaths.push(webCopyPath);

            // ffmpeg writes to this intermediate file; its stream is then copied to webCopyPath.
            // It MUST differ from webCopyPath, otherwise the copy truncates its own source.
            const webCopyGenName = `${audioId}-web-gen`
            log.debug({ webCopyPath, webCopyGenName });
            log.info('Resolved output paths');

            // ------------------------------------------------------------------------- generate web copy, extract cover art, detect content type
            log.info('wait for web compatible file and cover art to be generated and content type to be collected')

            const [contentType] = await Promise.all([
                runWithLogger(log, () => detectContentType(inputPath)
                    .then((ct) => {
                        log.debug({ contentType: ct }, 'Detected content type');
                        return ct;
                    })),
                isUploadWebCompatible
                    ? Promise.resolve(true)
                    : runWithLogger(log, () => generateWebCompatibleCopy(inputPath, jobDir, webCopyGenName, undefined, audioStream)
                        .then((result) => pipeline(result.outputStream, createWriteStream(webCopyPath!)))
                        .then(() => log.debug('Web-compatible copy written to disk'))),
            ]);
            log.debug({ isUploadWebCompatible });
            log.info('Generated web compatible file and cover art');

            try {
                // ------------------------------------------------------------------------- upload files to the S3 compatible object storage
                log.info('upload files to the S3 compatible object storage')

                await Promise.all([
                    runWithLogger(log, () => uploadToS3(createReadStream(inputPath), audioFileBucketKey, contentType.mimeType)),
                    ...(webCopyPath ? [runWithLogger(log, () => uploadToS3(createReadStream(webCopyPath), webCompatibleAudioFileBucketKey!, 'audio/mp4'))] : []),
                    ...(cover ? [runWithLogger(log, () => uploadToS3(Readable.from(Buffer.from(cover.data), { objectMode: false }), coverArtBucketKey, cover.mime))] : []),
                ]);
                log.debug({ audioFileBucketKey, webCompatibleAudioFileBucketKey, hasCoverArt: !!cover });
                log.info('Uploaded files to object storage');

                // ------------------------------------------------------------------------- create audio in meilisearch
                log.info('create audio in meilisearch')

                const meiliCreateResult = await runWithLogger(log, () => meiliAudio.create({ _id: temporaryAudio._id.toString(), title, lyrics: metadata.tags.lyrics }))
                log.debug({ meiliCreateResult })
                if (meiliCreateResult.status !== 'succeeded') {
                    log.error('failed to audio in meilisearch')
                    throw new Error('failed to upload audio')
                }

                // ------------------------------------------------------------------------- prepare audio in db
                log.info('prepare audio in db')
                await runWithLogger(log, () => prepareAudioInDb(metadata))

                // ------------------------------------------------------------------------- update audio info in DB, make it permanent and set content type
                log.info('update audio info in DB, make it permanent and set content type')

                const updateResult = await runWithLogger(log, () => audioRepository.unsafeUpdate(
                    audioId,
                    {
                        contentType: contentType,
                        title,
                        temporary: false,
                        bucketKey: audioFileBucketKey,
                        webBucketKey: webCompatibleAudioFileBucketKey,
                        coverArtKey: cover ? coverArtBucketKey : undefined,
                        tags: metadata.tags,
                        technical: metadata.technical,
                    }
                ));
                log.debug({ updateResult });
                if (!updateResult.acknowledged || updateResult.matchedCount !== 1) {
                    log.info('updating audio record failed');
                }
                log.info('Updated audio record');
            } catch (error) {
                log.error({ err: error }, 'Post-upload finalization failed, rolling back stored artifacts');
                rollbackPromises = Promise.allSettled([
                    runWithLogger(log, () => deleteFromS3(audioFileBucketKey).catch((err) => { log.error({ err }, 'deleting audio files from cloud storage failed') })),
                    ...(webCompatibleAudioFileBucketKey ? [runWithLogger(log, () => deleteFromS3(webCompatibleAudioFileBucketKey).catch((err) => { log.error({ err }, 'deleting web compatible audio files from cloud storage failed') }))] : []),
                    ...(cover ? [runWithLogger(log, () => deleteFromS3(coverArtBucketKey).catch((err) => { log.error({ err }, 'deleting cover art files from cloud storage failed') }))] : []),
                    runWithLogger(log, () => audioRepository.delete(audioId).catch((err) => { log.error({ err }, 'deleting audio info from db failed') })),
                    runWithLogger(log, () => meiliAudio.deleteBy({ title }, { wait: true })),
                ])

                throw error
            }
        } catch (err) {
            if (err instanceof UploadTooLargeError) {
                // if (!res.headersSent) res.status(402).json({ status: 'error', error: err.message });
                return;
            } else if (err instanceof InvalidMediaError) {
                // if (!res.headersSent) res.status(400).json({ status: 'error', error: err.message });
                return;
            } else {
                log.error({ err }, 'Audio upload failed');
                // if (!res.headersSent) res.status(500).json({ status: 'error', error: 'Upload failed' });
                return;
            }
        } finally {
            await cleanup();
            if (rollbackPromises !== undefined) {
                await rollbackPromises;
                log.info('Rollback of stored artifacts completed');
            }
        }

        // res.status(201).json({ status: 'success', data: temporaryAudio });
    } catch (err) {
        runWithLogger(log, () => handleError(res, err))
    }
})

router.patch('/tag', auth, isAdminIfAuthenticated, async (req, res) => {
    let log = getLogger().child({ module: 'audio', route: 'PATCH /api/audio/tag' });

    let db
    try {
        log.info('audio approve request received');

        log.debug({ body: req.body });
        const updates = await runWithLogger(log, () => validate(tagUpdateSchema, req.body))
        log.debug({ updates });

        delete updates.tags?.audioTitle
        delete updates.tags?.lyrics

        if (!updates.tags || Object.keys(updates.tags).length < 1) {
            log.info('invalid update tags field provided')
            return res.status(400).json({ status: 'error', error_code: 'INVALID_UPDATE_PARAMETER' })
        }

        log.info('input validated');

        const userId = req.user!.userId
        log.debug({ userId });

        db = MongoDB.getDbInstance()
        const session = await db.startTransaction()

        const audioRepository = new AudioRepository()
        audioRepository.setTransactionSession(session)

        const artistAlbumAudioRepository = new ArtistAlbumAudioRepository()
        artistAlbumAudioRepository.setTransactionSession(session)

        // ------------------------------------------------------------------------- fetch the requested audio
        log.info('fetch the requested audio')

        const audio = await runWithLogger(log, () => audioRepository.get(updates.audioId));
        log.debug({ audio });
        if (!audio) {
            log.info('audio not found');
            await db.abortTransaction()
            return res.status(400).json({ status: 'error', error_code: 'AUDIO_NOT_FOUND' });
        }

        // ------------------------------------------------------------------------- update audio
        log.info('update audio')

        const updateResult = await runWithLogger(log, () => audioRepository.unsafeUpdate(updates.audioId, { tags: { ...audio.tags, ...updates.tags } }));
        log.debug({ updateResult })
        if (!updateResult.acknowledged) {
            log.warn('failed to update audio record in db');
            await db.abortTransaction()
            return res.status(500).json({ status: 'error', error_code: 'INTERNAL_ERROR' });
        }

        await db.commitTransaction()

        res.status(204).send();
    } catch (err) {
        try { await db?.abortTransaction() } catch (_) { }

        runWithLogger(log, () => handleError(res, err))
    }
})

router.patch('/title', auth, isAdminIfAuthenticated, async (req, res) => {
    let log = getLogger().child({ module: 'audio', route: 'PATCH /api/audio/title' });

    let db
    try {
        log.info('audio approve request received');

        log.debug({ body: req.body });
        const updates = await runWithLogger(log, () => validate(titleUpdateSchema, req.body))
        log.debug({ updates });
        log.info('input validated');

        const userId = req.user!.userId
        log.debug({ userId });

        db = MongoDB.getDbInstance()
        const session = await db.startTransaction()

        const audioRepository = new AudioRepository()
        audioRepository.setTransactionSession(session)

        const artistAlbumAudioRepository = new ArtistAlbumAudioRepository()
        artistAlbumAudioRepository.setTransactionSession(session)

        // ------------------------------------------------------------------------- fetch the requested audio
        log.info('fetch the requested audio')

        const audio = await runWithLogger(log, () => audioRepository.get(updates.audioId));
        log.debug({ audio });
        if (!audio) {
            log.info('audio not found');
            await db.abortTransaction()
            return res.status(400).json({ status: 'error', error_code: 'AUDIO_NOT_FOUND' });
        }

        // ------------------------------------------------------------------------- update audio
        log.info('update audio')

        const updateResult = await runWithLogger(log, () => audioRepository.unsafeUpdate(updates.audioId, { title: updates.title }));
        log.debug({ updateResult })
        if (!updateResult.acknowledged) {
            log.warn('failed to update audio record in db');
            await db.abortTransaction()
            return res.status(500).json({ status: 'error', error_code: 'INTERNAL_ERROR' });
        }

        // ------------------------------------------------------------------------- update audio title in ArtistAlbumAudio repository
        log.info('update audio title in ArtistAlbumAudio repository')

        const updateTitlesResult = await runWithLogger(log, () => artistAlbumAudioRepository.updateManyByAudioTitle(audio.title, { audioTitle: updates.title }));
        log.debug({ updateTitlesResult })
        if (!updateTitlesResult.acknowledged) {
            log.warn('failed to update audio record in db');
            await db.abortTransaction()
            return res.status(500).json({ status: 'error', error_code: 'INTERNAL_ERROR' })
        }

        // ------------------------------------------------------------------------- update audio title in meilisearch
        log.info('update audio title in meilisearch audio')

        const meiliAudioUpsertResult = await meiliAudio.upsert({ _id: updates.audioId, title: updates.title }, { wait: true })
        log.debug({ meiliAudioUpsertResult })
        if (meiliAudioUpsertResult.status !== 'succeeded') {
            log.warn('failed to create audio title in meilisearch')
            await db.abortTransaction()
            res.status(500).json({ status: 'error', error_code: 'INTERNAL_ERROR' })
            throw new Error('failed to create artist in meilisearch')
        }

        // ------------------------------------------------------------------------- update audio title in meilisearch playlist audio
        log.info('update audio title in meilisearch playlist audio')

        const meiliPlaylistAudioUpsertResult = await meiliPlaylistAudio.updateBy({ audioId: updates.audioId }, { audioTitle: updates.title }, { wait: true })
        log.debug({ meiliPlaylistAudioUpsertResult })
        if (meiliPlaylistAudioUpsertResult.task?.status !== 'succeeded') {
            log.warn('failed to create audio title in meilisearch')
            await db.abortTransaction()
            res.status(500).json({ status: 'error', error_code: 'INTERNAL_ERROR' })
            throw new Error('failed to create artist in meilisearch')
        }

        await db.commitTransaction()

        res.status(204).send();
    } catch (err) {
        try { await db?.abortTransaction() } catch (_) { }

        runWithLogger(log, () => handleError(res, err))
    }
})

router.patch('/lyrics', auth, isAdminIfAuthenticated, async (req, res) => {
    let log = getLogger().child({ module: 'audio', route: 'PATCH /api/audio/lyrics' });

    let db
    try {
        log.info('audio approve request received');

        log.debug({ body: req.body });
        const updates = await runWithLogger(log, () => validate(lyricsUpdateSchema, req.body))
        log.debug({ updates });
        log.info('input validated');

        const userId = req.user!.userId
        log.debug({ userId });

        db = MongoDB.getDbInstance()
        const session = await db.startTransaction()

        const audioRepository = new AudioRepository()
        audioRepository.setTransactionSession(session)

        // ------------------------------------------------------------------------- fetch the requested audio
        log.info('fetch the requested audio')

        const audio = await runWithLogger(log, () => audioRepository.get(updates.audioId));
        log.debug({ audio });
        if (!audio) {
            log.info('audio not found');
            await db.abortTransaction()
            return res.status(400).json({ status: 'error', error_code: 'AUDIO_NOT_FOUND' });
        }

        // ------------------------------------------------------------------------- update audio
        log.info('update audio')

        const updateResult = await runWithLogger(log, () => audioRepository.unsafeUpdate(updates.audioId, { tags: { ...audio.tags, lyrics: updates.lyrics } }));
        log.debug({ updateResult })
        if (!updateResult.acknowledged) {
            log.warn('failed to update audio record in db');
            await db.abortTransaction()
            return res.status(500).json({ status: 'error', error_code: 'INTERNAL_ERROR' });
        }

        // ------------------------------------------------------------------------- update audio lyrics in meilisearch
        log.info('update audio lyrics in meilisearch audio')

        const meiliAudioUpsertResult = await meiliAudio.updateBy({ title: audio.title }, { lyrics: updates.lyrics }, { wait: true })
        log.debug({ meiliAudioUpsertResult })
        if (meiliAudioUpsertResult.task?.status !== 'succeeded') {
            log.warn('failed to create audio lyrics in meilisearch')
            await db.abortTransaction()
            res.status(500).json({ status: 'error', error_code: 'INTERNAL_ERROR' })
            throw new Error('failed to create artist in meilisearch')
        }

        await db.commitTransaction()

        res.status(204).send();
    } catch (err) {
        try { await db?.abortTransaction() } catch (_) { }

        runWithLogger(log, () => handleError(res, err))
    }
})

router.patch('/album', auth, isAdminIfAuthenticated, async (req, res) => {
    let log = getLogger().child({ module: 'audio', route: 'PATCH /api/audio/album' });

    let db
    try {
        log.info('audio approve request received');

        log.debug({ body: req.body });
        const updates = await runWithLogger(log, () => validate(albumUpdateSchema, req.body))
        log.debug({ updates });
        log.info('input validated');

        const userId = req.user!.userId
        log.debug({ userId });

        db = MongoDB.getDbInstance()
        const session = await db.startTransaction()

        const audioRepository = new AudioRepository()
        audioRepository.setTransactionSession(session)

        const albumRepository = new AlbumRepository()
        albumRepository.setTransactionSession(session)

        const artistAlbumAudioRepository = new ArtistAlbumAudioRepository()
        artistAlbumAudioRepository.setTransactionSession(session)

        // ------------------------------------------------------------------------- fetch the requested audio
        log.info('fetch the requested audio')

        const audio = await runWithLogger(log, () => audioRepository.get(updates.audioId));
        log.debug({ audio });
        if (!audio) {
            log.info('audio not found');
            await db.abortTransaction()
            return res.status(400).json({ status: 'error', error_code: 'AUDIO_NOT_FOUND' });
        }

        // ------------------------------------------------------------------------- update audio
        log.info('update audio')

        const updateResult = await runWithLogger(log, () => audioRepository.unsafeUpdate(updates.audioId, { tags: { ...audio.tags, album: updates.album } }));
        log.debug({ updateResult })
        if (!updateResult.acknowledged) {
            log.warn('failed to update audio record in db');
            await db.abortTransaction()
            return res.status(500).json({ status: 'error', error_code: 'INTERNAL_ERROR' });
        }

        // ------------------------------------------------------------------------- create the album if doesn't exist
        log.info("create the album if doesn't exist")

        const albumExistenceCheck = await runWithLogger(log, () => albumRepository.getByName(updates.album!));
        log.debug({ albumExistenceCheck })
        if (!albumExistenceCheck) {
            const createResult = await runWithLogger(log, () => albumRepository.insert({ name: updates.album! }));
            log.debug({ createResult })
            if (!createResult.acknowledged) {
                log.warn('failed to create new album');
                await db.abortTransaction()
                return res.status(500).json({ status: 'error', error_code: 'INTERNAL_ERROR' })
            }
        }

        // ------------------------------------------------------------------------- update album name in ArtistAlbumAudio repository
        log.info('update album name in ArtistAlbumAudio repository')

        const updateTitlesResult = await runWithLogger(log, () => artistAlbumAudioRepository.updateManyByAudioTitle(audio.title!, { albumName: updates.album }));
        log.debug({ updateTitlesResult })
        if (!updateTitlesResult.acknowledged) {
            log.warn('failed to update audio record in db');
            await db.abortTransaction()
            return res.status(500).json({ status: 'error', error_code: 'INTERNAL_ERROR' })
        }


        // ------------------------------------------------------------------------- update audio album in meilisearch
        log.info('update audio album in meilisearch audio')

        const meiliAudioUpsertResult = await meiliAlbum.updateBy({ name: audio.tags?.album }, { name: updates.album }, { wait: true })
        log.debug({ meiliAudioUpsertResult })
        if (meiliAudioUpsertResult.task?.status !== 'succeeded') {
            log.warn('failed to create audio album in meilisearch')
            await db.abortTransaction()
            res.status(500).json({ status: 'error', error_code: 'INTERNAL_ERROR' })
            throw new Error('failed to create artist in meilisearch')
        }

        await db.commitTransaction()

        res.status(204).send();
    } catch (err) {
        try { await db?.abortTransaction() } catch (_) { }

        runWithLogger(log, () => handleError(res, err))
    }
})

router.patch('/artist', auth, isAdminIfAuthenticated, async (req, res) => {
    let log = getLogger().child({ module: 'audio', route: 'PATCH /api/audio/artist' });

    let db
    try {
        log.info('audio approve request received');

        log.debug({ body: req.body });
        const updates = await runWithLogger(log, () => validate(artistUpdateSchema, req.body))
        log.debug({ updates });
        log.info('input validated');

        const userId = req.user!.userId
        log.debug({ userId });

        db = MongoDB.getDbInstance()
        const session = await db.startTransaction()

        const audioRepository = new AudioRepository()
        audioRepository.setTransactionSession(session)

        const albumRepository = new AlbumRepository()
        albumRepository.setTransactionSession(session)

        const artistRepository = new ArtistRepository()
        artistRepository.setTransactionSession(session)

        const artistAlbumAudioRepository = new ArtistAlbumAudioRepository()
        artistAlbumAudioRepository.setTransactionSession(session)

        // ------------------------------------------------------------------------- fetch the requested audio
        log.info('fetch the requested audio')

        const audio = await runWithLogger(log, () => audioRepository.get(updates.audioId));
        log.debug({ audio });
        if (!audio) {
            log.info('audio not found');
            await db.abortTransaction()
            return res.status(400).json({ status: 'error', error_code: 'AUDIO_NOT_FOUND' });
        }

        // ------------------------------------------------------------------------- update audio
        log.info('update audio')

        const updateResult = await runWithLogger(log, () => audioRepository.unsafeUpdate(updates.audioId, { tags: { ...audio.tags, artists: updates.artists } }));
        log.debug({ updateResult })
        if (!updateResult.acknowledged) {
            log.warn('failed to update audio record in db');
            await db.abortTransaction()
            return res.status(500).json({ status: 'error', error_code: 'INTERNAL_ERROR' });
        }

        // ------------------------------------------------------------------------- create the artist if doesn't exist
        log.info("create the artist if doesn't exist")

        let artistCreatePromises: Promise<void>[] = []
        for (const artist of updates.artists) {
            artistCreatePromises.push((async () => {
                const artistExistenceCheck = await runWithLogger(log, () => artistRepository.getByName(artist));
                log.debug({ artistExistenceCheck })
                if (!artistExistenceCheck) {
                    const createResult = await runWithLogger(log, () => artistRepository.insert({ name: artist }));
                    log.debug({ createResult })
                    if (!createResult.acknowledged) {
                        log.warn('failed to create new artist');
                        await db.abortTransaction()
                        throw new Error('failed to create new artist')
                    }
                }
            })().catch((err) => { log.error({ err }, 'caught error in promise in audio update artist route') }))
        }

        await Promise.all(artistCreatePromises)

        // ------------------------------------------------------------------------- update audio artist in meilisearch
        log.info('update audio artist in meilisearch audio')

        let meiliArtistCreatePromises: Promise<void>[] = []
        for (const artist of updates.artists) {
            meiliArtistCreatePromises.push((async () => {
                const meiliAudioUpsertResult = await meiliArtist.upsert({ name: artist })
                log.debug({ meiliAudioUpsertResult })
                if (meiliAudioUpsertResult.status !== 'succeeded') {
                    log.warn('failed to create audio artist in meilisearch')
                    await db.abortTransaction()
                    throw new Error('failed to create artist in meilisearch')
                }
            })())
        }

        await Promise.all(meiliArtistCreatePromises)

        if (!audio.tags?.album) {
            await db.commitTransaction()

            return res.status(204).send();
        }

        // ------------------------------------------------------------------------- update artist name in ArtistAlbumAudio repository
        log.info('update artist name in ArtistAlbumAudio repository')

        let promises = []
        for (const artist of updates.artists) {
            promises.push((async () => {
                const updateTitlesResult = await runWithLogger(log, () => artistAlbumAudioRepository.upsertManyByAlbumNameByAudioTitle(audio.tags!.album!, audio.title, { artistName: artist }));
                log.debug({ updateTitlesResult })
                if (!updateTitlesResult.acknowledged) {
                    log.warn('failed to update audio record in db');
                    await db.abortTransaction()
                    return res.status(500).json({ status: 'error', error_code: 'INTERNAL_ERROR' })
                }
            })().catch((err) => { log.error({ err }, 'caught error in promise in audio update artist route') }))
        }

        await db.commitTransaction()

        return res.status(204).send();
    } catch (err) {
        try { await db?.abortTransaction() } catch (_) { }

        runWithLogger(log, () => handleError(res, err))
    }
})

router.get('/', auth, async (req, res) => {
    let log = getLogger().child({ module: 'audio', route: 'GET /api/audio/' });

    try {
        log.info('Audio list request received');

        log.debug({ query: req.query });
        const { page, pageSize, search } = await runWithLogger(log, () => validate(listQuerySchema, req.query));
        log.info('Input validated');
        log.debug({ page, pageSize, search });

        const userId = req.user!.userId;
        log = log.child({ userId });

        const audioRepository = new AudioRepository();

        let items: Audio[]
        if (search) {
            log.info('search in meilisearch')

            const searchResult = await meiliAudio.search(search, { page, hitsPerPage: pageSize })
            const { totalHits, totalPages, hits } = searchResult
            log.debug({ totalHits, totalPages, hits })

            const ids = hits.map(m => m._id)

            log.info('fetch from audioRepository')
            items = await runWithLogger(log, () => audioRepository.getMany(ids))
        } else {
            log.info('fetch from audioRepository')

            const skip = (page - 1) * pageSize;
            items = await runWithLogger(log, () => audioRepository.getPage(skip, pageSize))
        }
        log.debug({ count: items.length });

        log.info('Listed audios');
        res.status(200).json({ status: 'success', data: items });
    } catch (err) {
        runWithLogger(log, () => handleError(res, err));
    }
});

router.get('/info/', auth, async (req, res) => {
    let log = getLogger().child({ module: 'audio', route: 'GET /api/audio/info/' });

    try {
        log.info('Audio info request received');

        log.debug({ query: req.query });
        const { audioId, title } = await runWithLogger(log, () => validate(infoQuerySchema, req.query));
        log.info('Input validated');
        log.debug({ audioId, title });

        const userId = req.user!.userId;
        log = log.child({ userId, audioId, title });

        const audioRepository = new AudioRepository();

        const result = audioId
            ? await runWithLogger(log, () => audioRepository.get(audioId))
            : await runWithLogger(log, () => audioRepository.getByTitle(title!));
        log.debug({ result });
        log.info('Looked up audio info');

        if (!result) {
            log.info('Audio not found');
            return res.status(404).json({ status: 'error', message: 'Audio not found' });
        }

        res.status(200).json({ status: 'success', data: result });
    } catch (err) {
        runWithLogger(log, () => handleError(res, err));
    }
});

router.get('/singed_token', auth, async (req, res) => {
    let log = getLogger().child({ module: 'audio', route: 'GET /api/audio/singed_token' });

    try {
        log.info('Signed token request received');

        log.debug({ query: req.query });
        const { audioId } = await runWithLogger(log, () => validate(signedTokenQuerySchema, req.query));
        log.info('Input validated');
        log.debug({ audioId });

        const userId = req.user!.userId;
        log = log.child({ userId, audioId });

        const audioRepository = new AudioRepository();

        const audio = await runWithLogger(log, () => audioRepository.get(audioId));
        log.debug({ audio });
        log.info('Checked audio ownership');
        if (!audio) {
            log.info('Rejected signed token request: audio not found');
            return res.status(404).json({ status: 'error', message: 'Audio not found' });
        }

        const token = generateStreamToken(audioId, userId);
        log.info('Issued signed stream token');

        res.status(200).json({ status: 'success', data: token });
    } catch (err) {
        runWithLogger(log, () => handleError(res, err));
    }
});

// there are separate routes for downloading audio because web's media player doesn't support using authorization headers, therefor it uses signed urls instead.
// For non web applications
router.get('/file/:audioId', auth, async (req, res) => {
    let log = getLogger().child({ module: 'audio', route: 'GET /api/audio/file/:audioId' });

    try {
        log.info('Audio file request received');

        log.debug({ params: req.params, query: req.query, range: req.headers.range });
        const { audioId, download: temp } = await runWithLogger(log, () => validate(fileParamsSchema, { ...req.params, ...req.query }));
        let download: boolean = temp === 'true'
        log.info('Input validated');
        log.debug({ audioId, download });

        log = log.child({ userId: req.user!.userId, audioId, download });

        await streamAudioFile(audioId, req.user!.userId, req, res, false, download);
    } catch (err) {
        runWithLogger(log, () => handleError(res, err));
    }
});

// For web applications
router.get('/file/web/:audioId/:token', async (req, res) => {
    let log = getLogger().child({ module: 'audio', route: 'GET /api/audio/file/web/:audioId/:token' });

    try {
        log.info('Web audio file request received');

        log.debug({ params: { audioId: req.params.audioId }, query: req.query, range: req.headers.range });
        const { audioId, token, download: temp } = await runWithLogger(log, () => validate(webFileParamsSchema, { ...req.params, ...req.query }));
        let download: boolean = temp === 'true'
        log.info('Input validated');
        log.debug({ audioId, download });

        log = log.child({ audioId, download });

        const { valid, userId } = verifyStreamToken(token, audioId);
        log.debug({ valid });
        log.info('Verified stream token');
        if (valid !== true || !userId) {
            log.warn('Rejected web audio file request: invalid or expired token');
            return res.status(401).json({ status: 'error', message: 'Unauthorized' });
        }
        log = log.child({ userId });

        await streamAudioFile(audioId, userId, req, res, true, download);
    } catch (err) {
        runWithLogger(log, () => handleError(res, err));
    }
});

router.get('/coverArt/:audioId', auth, async (req, res) => {
    let log = getLogger().child({ module: 'audio', route: 'GET /api/audio/coverArt/:audioId' });

    try {
        log.info('Cover art request received');

        log.debug({ params: req.params, query: req.query });
        const { audioId } = await runWithLogger(log, () => validate(coverArtParamsSchema, { ...req.params, ...req.query }));
        log.info('Input validated');
        log.debug({ audioId });

        const audioRepository = new AudioRepository();

        const audio = await runWithLogger(log, () => audioRepository.get(audioId));
        log.debug({ audio });
        log.info('Checked audio ownership');
        if (!audio || !audio.coverArtKey) {
            log.info('Rejected cover art request: audio not found or has no cover art');
            return res.status(404).json({ status: 'error', message: 'Audio not found' });
        }

        const result = await getS3ObjectStream(audio.coverArtKey);
        log.debug({ result });
        if (!result) {
            log.warn('Cover art object has no body');
            return res.status(404).json({ status: 'error', error_code: 'COVER_ART_NOT_FOUND' });
        }

        const { stream, contentLength, contentType } = result
        log.debug({ stream, contentLength, contentType });

        if (!stream) {
            log.warn('Cover art object has no body');
            return res.status(404).json({ status: 'error', error_code: 'COVER_ART_NOT_FOUND' });
        }

        res.setHeader('Accept-Ranges', 'bytes');
        res.setHeader('Content-Type', contentType || 'application/octet-stream');
        res.status(200);
        res.setHeader('Content-Length', contentLength ?? '');

        log.info('Streaming cover art to client');
        stream.pipe(res);
    } catch (err) {
        runWithLogger(log, () => handleError(res, err));
    }
});

router.put('/coverArt/:audioId', auth, isAdminIfAuthenticated, async (req, res) => {
    let log = getLogger().child({ module: 'audio', route: 'PUT /api/audio/coverArt/:audioId' });

    try {
        log.info('Cover art request received');

        log.debug({ params: req.params });
        const { audioId } = await runWithLogger(log, () => validate(coverArtParamsSchema, { ...req.params }));
        log.info('Input validated');
        log.debug({ audioId });

        const audioRepository = new AudioRepository();

        const audio = await runWithLogger(log, () => audioRepository.get(audioId));
        log.debug({ audio });
        log.info('Checked audio ownership');
        if (!audio) {
            log.info('Rejected cover art request: audio not found or has no cover art');
            return res.status(404).json({ status: 'error', message: 'Audio not found' });
        }

        const key = `avarim/audio/cover_art/${audioId}`

        // ------------------------------------------------------------------------- make the temporary directory
        log.info('make the temporary directory')

        const jobDir = join(audioUploadTmpDir, 'coverArts', audioId)
        await mkdir(jobDir, { recursive: true });
        log.debug({ jobDir });
        log.info('Created job scratch directory');

        const cleanupPaths: string[] = [];
        const cleanup = async () => {
            log.debug({ cleanupPaths, jobDir });
            log.info('Cleaning up temp files');
            await Promise.all(cleanupPaths.map((p) => unlink(p).catch(() => { })));
            await rm(jobDir, { recursive: true, force: true }).catch(() => { });
        };

        try {

            // ------------------------------------------------------------------------- store upload stream on disk
            log.info('store upload stream on disk')

            const { path: inputPath, size: inputSize } = await runWithLogger(log, () => receiveUpload(req, undefined, jobDir))
            cleanupPaths.push(inputPath)
            log.debug({ inputSize, inputPath })
            log.info('Upload received and stored to disk')

            const contentType = await runWithLogger(log, () => detectContentType(inputPath))
            log.debug({ contentType })

            if (audio.coverArtKey) {
                log.info('deleting old cover art')
                try { await runWithLogger(log, () => deleteFromS3(audio.coverArtKey!)) } catch (err) { log.warn({ err }, 'failed to delete old cover art') }
            }

            const tmpUpdateResult = await runWithLogger(log, () => audioRepository.unsafeUpdate(audioId, { temporaryAvatar: true }));
            log.debug({ tmpUpdateResult });
            if (!tmpUpdateResult) {
                log.info('failed to update the audio');
                return res.status(500).json({ status: 'error', error_code: 'INTERNAL_ERROR' });
            }

            await runWithLogger(log, () => uploadToS3(createReadStream(inputPath), key, contentType.mimeType, true))

            const updateResult = await runWithLogger(log, () => audioRepository.unsafeUpdate(audioId, { coverArtKey: key, temporaryAvatar: true }));
            log.debug({ updateResult });
            if (!updateResult) {
                log.info('failed to update the audio');
                return res.status(500).json({ status: 'error', error_code: 'INTERNAL_ERROR' });
            }
        } catch (err) {
            log.error({ err }, 'caught an error while trying to upload files')
            cleanup()
            throw err
        }

        res.status(201).json({ status: 'success' })
    } catch (err) {
        runWithLogger(log, () => handleError(res, err));
    }
});

router.delete('/:audioId', auth, isAdminIfAuthenticated, async (req, res) => {
    let log = getLogger().child({ module: 'audio', route: 'DELETE /api/audio/:audioId' });

    try {
        log.info('Audio delete request received');

        log.debug({ params: req.params });
        const { audioId } = await runWithLogger(log, () => validate(deleteParamsSchema, req.params));
        log.info('Input validated');
        log.debug({ audioId });

        const audioRepository = new AudioRepository();

        const audio = await runWithLogger(log, () => audioRepository.get(audioId));
        log.debug({ audio });
        log.info('Checked audio ownership');
        if (!audio) {
            log.info('Rejected audio delete request: audio not found');
            res.status(404).json({ status: 'error', message: 'Audio not found' });
            return
        }

        const r = await runWithLogger(log, () => audioRepository.unsafeUpdate(audioId, { title: `deletionQueued${AUDIO_TITLE_SEPARATOR}${audio.title}`, deletionQueued: true }));
        log.debug({ updateResult: r });
        if (!r.acknowledged || r.matchedCount) {
            log.error({ updateResult: r }, 'Failed to mark audio temporary before delete');
            res.status(500).json({ status: 'error', message: 'Error deleting audio' });
            return
        }
        log.info('Marked audio before delete');

        const meiliAudioDeleteResult = await runWithLogger(log, () => meiliAudio.delete(audioId));
        log.debug({ meiliAudioDeleteResult });
        if (meiliAudioDeleteResult.status !== 'succeeded') {
            log.error({ meiliAudioDeleteResult }, 'Failed to delete audio record from Meilisearch audio collection');
            res.status(500).json({ status: 'error', message: 'Error deleting audio' });
            return
        }
        log.info('Deleted audio record in Meilisearch audio collection')

        const meiliPlaylistAudioDeleteResult = await runWithLogger(log, () => meiliPlaylistAudio.deleteBy({ audioId }));
        log.debug({ meiliPlaylistAudioDeleteResult });
        if (meiliPlaylistAudioDeleteResult.status !== 'succeeded') {
            log.error({ meiliPlaylistAudioDeleteResult }, 'Failed to delete audio record from Meilisearch playlist audio collection');
            res.status(500).json({ status: 'error', message: 'Error deleting audio' });
            return
        }
        log.info('Deleted audio record in Meilisearch playlist audio collection')

        const promises = []
        if (audio?.bucketKey) {
            log.info('Deleting audio file from storage');
            promises.push(runWithLogger(log, () => deleteFromS3(audio.bucketKey!)))
            log.debug({ key: audio.bucketKey });
        }

        if (audio?.webBucketKey) {
            log.info('Deleting web audio file from storage');
            promises.push(runWithLogger(log, () => deleteFromS3(audio.webBucketKey!)))
            log.debug({ key: audio.webBucketKey });
        }

        if (audio?.coverArtKey) {
            log.info('Deleting cover art from storage');
            promises.push(runWithLogger(log, () => deleteFromS3(audio.coverArtKey!)))
            log.debug({ key: audio.coverArtKey });
        }

        const results = await Promise.allSettled(promises)
        log.debug({ results })
        const rejected = results.filter((r): r is PromiseRejectedResult => r.status === 'rejected');
        log.info(
            {
                fulfilledCount: results.length - rejected.length,
                rejectedCount: rejected.length,
                ...(rejected.length > 0 && { errors: rejected.map(r => r.reason instanceof Error ? r.reason.message : r.reason) }),
            },
            'handled all the object deletions from s3 storage'
        );

        if (rejected.length > 0) {
            log.info({ rejectedLength: rejected.length }, `failed to delete objects in s3 storage`)
            res.status(500).json({ status: 'error', error_code: 'INTERNAL_ERROR' })
            return
        }

        const rr = await runWithLogger(log, () => audioRepository.delete(audioId));
        log.debug({ deleteResult: rr });
        if (!rr.acknowledged) {
            log.error({ deleteResult: rr }, 'Failed to delete audio record from DB');
            res.status(500).json({ status: 'error', message: 'Error deleting audio' });
            return
        }
        log.info('Deleted audio record in DB')

        log.info('audio deleted successfully');
        res.status(204).json({ status: 'success' });
    } catch (err) {
        runWithLogger(log, () => handleError(res, err));
    }
});

export { router as audioRoutes };
