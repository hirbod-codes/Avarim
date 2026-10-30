import AudioRepository from "../../db/MongoDB/AudioRepository";
import { getLogger, runWithLogger } from "../../observability/requestLoggerContext";
import { Request, Response } from "express";
import { handleError } from "../../lib";
import { createHash } from 'node:crypto';
import { createReadStream } from 'node:fs';
import { stat } from 'node:fs/promises';
import { spawn } from 'node:child_process';
import { parseFile, selectCover, TimestampFormat, type ICommonTagsResult, type IAudioMetadata } from 'music-metadata';
import { probeFile, FFMPEG_PATH } from '../../ffmpeg';
import { AudioTags, TechnicalInfo } from "../../db/models/Audio";
import { basename } from "node:path";
import { getS3ObjectStream } from "../../lib/file_management";
import { MongoDB } from "../../db/MongoDB/mongodb";
import ArtistRepository from "../../db/MongoDB/ArtistRepository";
import AlbumRepository from "../../db/MongoDB/AlbumRepository";
import ArtistAlbumAudioRepository from "../../db/MongoDB/ArtistAlbumAudioRepository";
import { meiliAlbum, meiliArtist } from "../../db/meilisearch";
import { AlbumController } from "../../controllers/AlbumController";
import { ArtistController } from "../../controllers/ArtistController";
import { Album } from "../../db/models/Album";
import { WithId } from "../../db/common_schemas";

/**
 * if album provided
 *      create the artist(s), if no artists found(soundtrack) use composers or producers
 *      create meilisearch artist(s)
 * if artist provided
 *      create the album
 *      create meilisearch album
 * create ArtistAlbumAudio records
 */
export async function prepareAudioInDb(audioId: string, metadata: ExtractionResult) {
    let log = getLogger().child({ step: 'prepareAudioInDb' });

    let db;
    try {
        db = MongoDB.getDbInstance()
        const session = await db.startTransaction()

        const artistRepository = new ArtistRepository()
        artistRepository.setTransactionSession(session)

        const albumRepository = new AlbumRepository()
        albumRepository.setTransactionSession(session)

        const artistAlbumAudioRepository = new ArtistAlbumAudioRepository()
        artistAlbumAudioRepository.setTransactionSession(session)

        const tags = metadata.tags
        if (!tags) return

        let artistNames: string[] = []

        // ------------------------------------------------------------------------- create the artist(s), if no artists found(soundtrack) use composers or producers
        if (tags.artists && tags.artists.length > 0)
            artistNames = tags.artists
        else
            artistNames = tags.composers ?? tags.producers ?? []

        if (artistNames && artistNames.length > 0) {
            log.info('create the artist(s), if no artists found(soundtrack) use composers or producers')

            const promises = []
            for (const name of artistNames) {
                promises.push((async () => {
                    const artistId = await runWithLogger(log, () => new ArtistController().create(name));

                    let albums: WithId<Album>[] = !tags.album ? [] : await runWithLogger(log, albumRepository.getByName(tags.album))
                    log.debug({ albumsLength: albums.length })
                    if (albums.length < 1) {
                        let albumId: string | undefined = undefined
                        if (tags.album)
                            albumId = await runWithLogger(log, () => new AlbumController().create(tags.album!))

                        const createResult = await runWithLogger(log, () => artistAlbumAudioRepository.insert({ artistId, albumId, audioId }));
                        if (!createResult.acknowledged) {
                            log.warn('Failed to create artistAlbumAudio')
                            throw new Error('Failed to create artistAlbumAudio')
                        }
                    } else
                        for (const album of albums) {
                            const createResult = await runWithLogger(log, () => artistAlbumAudioRepository.insert({ artistId, albumId: album._id.toString(), audioId }));
                            if (!createResult.acknowledged) {
                                log.warn('Failed to create artistAlbumAudio')
                                throw new Error('Failed to create artistAlbumAudio')
                            }
                        }
                })())
            }

            const result = await Promise.all(promises)
            log.debug({ result })
        } else {
            let albumId: string | undefined = undefined
            if (tags && tags.album) {
                albumId = await runWithLogger(log, () => new AlbumController().create(tags.album!))
            }

            const createResult = await runWithLogger(log, () => artistAlbumAudioRepository.insert({ artistId: undefined, albumId, audioId }));
            if (!createResult.acknowledged) {
                log.warn('Failed to create artistAlbumAudio')
                throw new Error('Failed to create artistAlbumAudio')
            }
        }

        await db.commitTransaction()
    } catch (err) {
        log.error({ err })
        await db?.abortTransaction()

        throw err
    }
}

export async function streamAudioFile(audioId: string, userId: string, req: Request, res: Response, isWeb: boolean, download: boolean) {
    const log = getLogger().child({ step: 'streamAudioFile' })

    const audioRepository = new AudioRepository();

    const audio = await runWithLogger(log, () => audioRepository.get(audioId));
    log.debug({ audio });
    log.info('Checked audio ownership');
    if (!audio || !audio.contentType || (!audio.webBucketKey && !audio.bucketKey)) {
        log.info('Rejected audio file request: audio not found or missing expected bucket key');
        return res.status(404).json({ status: 'error', message: 'Audio not found' });
    }

    const range = req.headers.range;
    const key = isWeb ? (audio.webBucketKey ?? audio.bucketKey!) : audio.bucketKey!;
    log.debug({ key, range, download });

    const result = await getS3ObjectStream(key, { range })
    log.debug({ result });
    log.info('Fetched object from storage');

    if (!result || !result.stream) {
        log.warn('Storage object has no body');
        return res.status(404).json({ status: 'error', message: 'Audio not found' });
    }

    const body = result.stream
    body.on('error', (err) => {
        log.error({ err, key }, 'S3 stream error while serving audio file');
        if (!res.headersSent) return runWithLogger(log, () => handleError(res, err));
        res.destroy();
    });

    res.status(range ? 206 : 200);
    res.setHeader('Content-Type', isWeb ? 'audio/m4a' : (audio.contentType?.mimeType ?? 'audio/m4a'));
    res.setHeader('Accept-Ranges', 'bytes');
    if (result.contentRange) res.setHeader('Content-Range', result.contentRange);
    if (result.contentLength) res.setHeader('Content-Length', result.contentLength);

    log.info('Streaming audio file to client');
    body.pipe(res);
}

/* ------------------------------------------------------------------ */
/* Types                                                              */
/* ------------------------------------------------------------------ */

// Your ProbeInfo only types 4 fields; ffprobe returns far more. Widen it here
// (ideally move these into ffmpeg.ts and export them).
export interface FfprobeStream {
    index: number;
    codec_type: 'video' | 'audio' | string;
    codec_name: string;
    profile?: string;
    sample_rate?: string;
    channels?: number;
    channel_layout?: string;
    bits_per_sample?: number;
    bits_per_raw_sample?: string;
    bit_rate?: string;
    disposition?: { attached_pic?: number };
    tags?: Record<string, string>;
}
export interface FfprobeResult {
    streams: FfprobeStream[];
    format: { format_name?: string; duration?: string; bit_rate?: string; size?: string; tags?: Record<string, string> };
}

export interface ExtractedCover { index: number; mime: string; kind: string | null | undefined; description: string | null | undefined; sizeBytes: number; data: Uint8Array }

export type TagSource = 'tags' | 'ffprobe' | 'filename';

export interface ExtractionResult {
    tags: AudioTags;
    /** which source filled each tag, so the review UI can show "guessed from filename" */
    tagSources: Partial<Record<keyof AudioTags, TagSource>>;
    syncedLyrics: { timeMs: number; text: string }[] | undefined;
    /** every native tag exactly as stored in the file, as strings ("ID3v2.4:TXXX:MOOD" -> "Happy") */
    rawTags: Record<string, string>;
    technical: TechnicalInfo;
    covers: ExtractedCover[];
    /** index into `covers` of the best front cover, or null */
    suggestedCoverIndex: number | undefined;
    warnings: string[];
    /** kept server-side only; needed later for generateWebCompatibleCopy */
    probe: FfprobeResult;
}

export interface ExtractOptions {
    /** measure EBU R128 loudness (default true) */
    loudness?: boolean;
    /** compute waveform peaks (default true) */
    waveform?: boolean;
    /** overall budget for the whole extraction, in ms (default 120 000) */
    timeoutMs?: number;
}

export const DEFAULT_EXTRACTION_TIMEOUT_MS = 120_000;

/** Thrown by extractMetadata when the overall time budget runs out. Map it to 504, not 422. */
export class ExtractionTimeoutError extends Error {
    constructor(public readonly timeoutMs: number) {
        super(`Metadata extraction timed out after ${timeoutMs} ms`);
        this.name = 'ExtractionTimeoutError';
    }
}

/* ------------------------------------------------------------------ */
/* Small helpers                                                      */
/* ------------------------------------------------------------------ */

const num = (v: unknown): number | null => {
    const n = typeof v === 'string' || typeof v === 'number' ? Number(v) : NaN;
    return Number.isFinite(n) ? n : null;
};
const clean = (s?: string | null) => (s ?? '').replace(/\u0000/g, '').trim();
const dedupe = (xs: string[]) => {
    const seen = new Set<string>();
    return xs.filter((x) => { const k = x.toLowerCase(); return seen.has(k) ? false : (seen.add(k), true); });
};
/** Splits on ';' only. Commas and '&' are NOT safe ("Tyler, The Creator"); leave those to the admin. */
const splitList = (s?: string | string[] | null) =>
    dedupe((Array.isArray(s) ? s : [s ?? '']).flatMap((x) => clean(x).split(/\s*;\s*/)).filter(Boolean));
const lowerKeys = (t?: Record<string, string>) =>
    Object.fromEntries(Object.entries(t ?? {}).map(([k, v]) => [k.toLowerCase(), v]));

function normDate(s?: string | null): string | null {
    const m = clean(s).match(/^(\d{4})(?:-(\d{2}))?(?:-(\d{2}))?/);
    return m ? [m[1], m[2], m[3]].filter(Boolean).join('-') : null;
}
function normIsrc(xs?: string[]): string[] {
    return dedupe((xs ?? []).map((x) => clean(x).replace(/[-\s]/g, '').toUpperCase())).filter((x) => /^[A-Z]{2}[A-Z0-9]{3}\d{7}$/.test(x));
}
const LOSSLESS = /^(flac|alac|wavpack|ape|tta|pcm_.*|mlp|truehd)$/;

type Log = ReturnType<typeof getLogger>;
const isAbortError = (e: unknown) => (e as { name?: string } | null)?.name === 'AbortError';

/** An aborted child process (our timeout fired) is expected, so it's a warning; anything else is an error. */
function logProcessError(log: Log, err: unknown, what: string) {
    if (isAbortError(err)) log.warn(`Aborted ${what} (extraction cancelled or timed out)`);
    else log.error({ err }, `Failed to run ${what}`);
}

export function emptyTags(audioTitle: string): AudioTags {
    return {
        audioTitle, artists: [], album: undefined,
        trackNumber: undefined, trackTotal: undefined, discNumber: undefined, discTotal: undefined,
        year: undefined, releaseDate: undefined, genres: [], composers: [], lyricists: [], producers: [],
        label: undefined, catalogNumber: undefined, isrc: [], bpm: undefined, key: undefined, compilation: false,
        language: undefined, copyright: undefined, comment: undefined, lyrics: undefined,
    };
}

const isEmpty = (v: unknown) => v == null || v === false || (Array.isArray(v) && v.length === 0) || v === '';

/** Fill only the gaps, in priority order, remembering where each value came from. */
function fill(target: AudioTags, source: Partial<AudioTags>, name: TagSource, sources: ExtractionResult['tagSources']) {
    for (const key of Object.keys(source) as (keyof AudioTags)[]) {
        if (isEmpty(target[key]) && !isEmpty(source[key])) {
            (target as Record<string, unknown>)[key] = source[key];
            sources[key] = name;
        }
    }
}

/* ------------------------------------------------------------------ */
/* Source 1: embedded tags (music-metadata, pure JS)                  */
/* ------------------------------------------------------------------ */

function tagsFromParser(c: ICommonTagsResult): Partial<AudioTags> {
    const date = normDate(c.date ?? c.releasedate);
    const comments = (c.comment ?? [])
        // iTunes stuffs normalisation / gapless blobs into COMM frames; not human text
        .filter((x) => !x.descriptor?.toLowerCase().startsWith('itun'))
        .map((x) => clean(x.text)).filter(Boolean);
    return {
        audioTitle: clean(c.title) ?? undefined,
        artists: c.artists?.length ? splitList(c.artists) : splitList(c.artist),
        albumArtists: c.albumartists?.length ? splitList(c.albumartists) : splitList(c.albumartist),
        album: clean(c.album),
        trackNumber: c.track.no ?? undefined,
        trackTotal: c.track.of ?? undefined,
        discNumber: c.disk.no ?? undefined,
        discTotal: c.disk.of ?? undefined,
        year: c.year ?? (date ? Number(date.slice(0, 4)) : undefined),
        releaseDate: date ?? undefined,
        genres: splitList(c.genre),
        composers: splitList(c.composer),
        lyricists: splitList(c.lyricist),
        producers: splitList(c.producer),
        label: clean(c.label?.[0]) ?? undefined,
        catalogNumber: clean(c.catalognumber?.[0]) ?? undefined,
        isrc: normIsrc(c.isrc),
        bpm: c.bpm ?? undefined,
        key: clean(c.key) ?? undefined,
        compilation: !!c.compilation,
        language: clean(c.language) ?? undefined,
        copyright: clean(c.copyright) ?? undefined,
        comment: comments.join('\n') ?? undefined,
        lyrics: c.lyrics?.find((l) => l.text)?.text ?? undefined,
    };
}

function syncedLyricsFrom(c: ICommonTagsResult) {
    const l = c.lyrics?.find((x) => x.syncText?.length && x.timeStampFormat === TimestampFormat.milliseconds);
    return l ? l.syncText.filter((s) => s.timestamp != null).map((s) => ({ timeMs: s.timestamp!, text: s.text })) : null;
}

function flattenNative(md: IAudioMetadata): Record<string, string> {
    const out: Record<string, string> = {};
    for (const [type, tags] of Object.entries(md.native)) {
        for (const t of tags) {
            const v: unknown = t.value;
            const s = typeof v === 'string' || typeof v === 'number' || typeof v === 'boolean' ? String(v)
                : v && typeof v === 'object' && 'text' in v ? String((v as { text: unknown }).text) : null; // skip binary (APIC, GEOB, ...)
            if (!s) continue;
            const k = `${type}:${t.id}`;
            out[k] = (out[k] ? out[k] + ' | ' : '') + s.slice(0, 2000);
        }
    }
    return out;
}

/* ------------------------------------------------------------------ */
/* Source 2: ffprobe tags (fallback when the parser can't read a file) */
/* ------------------------------------------------------------------ */

function tagsFromFfprobe(probe: FfprobeResult): Partial<AudioTags> {
    const audio = probe.streams.find((s) => s.codec_type === 'audio');
    const t = { ...lowerKeys(audio?.tags), ...lowerKeys(probe.format.tags) }; // Ogg/Opus keep tags on the stream
    const pair = (v?: string) => { const m = v?.match(/^\s*(\d+)\s*(?:\/\s*(\d+))?/); return { no: m ? Number(m[1]) || null : null, of: m?.[2] ? Number(m[2]) || null : null }; };
    const trk = pair(t.track), dsk = pair(t.disc);
    const date = normDate(t.date ?? t.year);
    return {
        audioTitle: clean(t.title) ?? undefined,
        artists: splitList(t.artist),
        album: clean(t.album),
        trackNumber: trk.no ?? undefined,
        trackTotal: trk.of ?? undefined,
        discNumber: dsk.no ?? undefined,
        discTotal: dsk.of ?? undefined,
        releaseDate: date ?? undefined,
        year: date ? Number(date.slice(0, 4)) : undefined,
        genres: splitList(t.genre),
        composers: splitList(t.composer),
        label: clean(t.label ?? t.publisher) ?? undefined,
        isrc: normIsrc(t.isrc ? [t.isrc] : []),
        copyright: clean(t.copyright) ?? undefined,
        comment: clean(t.comment) ?? undefined,
        lyrics: clean(t.lyrics ?? t.unsyncedlyrics) ?? undefined,
    };
}

/* ------------------------------------------------------------------ */
/* Source 3: file name ("01 - Artist - Title.mp3")                    */
/* ------------------------------------------------------------------ */

function tagsFromFilename(originalName: string): Partial<AudioTags> {
    const base = originalName.replace(/\.[^.]+$/, '').replace(/_/g, ' ').trim();
    const m = base.match(/^(?:(\d{1,3})\s*[-.)]\s+)?(?:(.+?)\s+-\s+)?(.+)$/);
    if (!m) return {};
    return { trackNumber: m[1] ? Number(m[1]) : undefined, artists: m[2] ? [m[2].trim()] : [], audioTitle: m[3].trim() };
}

/* ------------------------------------------------------------------ */
/* Derived analysis (ffmpeg / node)                                   */
/* ------------------------------------------------------------------ */
// Every helper takes an optional AbortSignal: when extractMetadata's time budget runs out
// (or another step fails) the signal kills the spawned ffmpeg instead of leaving it running.

function sha256(path: string, signal?: AbortSignal): Promise<string> {
    const log = getLogger().child({ module: 'ffmpeg', step: 'sha256' })

    return new Promise((resolve, reject) => {
        const h = createHash('sha256');
        createReadStream(path, { signal })
            .on('data', (c) => h.update(c))
            .on('error', (err) => {
                if (isAbortError(err)) log.warn('Aborted file sha256 (extraction cancelled or timed out)');
                else log.error({ err }, 'Failed to read file for sha256');
                reject(err);
            })
            .on('end', () => {
                const digest = h.digest('hex');
                log.debug({ sha256: digest });
                log.info('Computed file sha256');
                resolve(digest);
            });
    });
}

/**
 * EBU R128 loudness. Your runFfmpeg runs with `-loglevel error` and throws away
 * stderr on success, but loudnorm prints its JSON report to stderr at info
 * level, so this needs its own spawn.
 */
export function measureLoudness(inputPath: string, signal?: AbortSignal): Promise<TechnicalInfo['loudness'] | null> {
    const log = getLogger().child({ module: 'ffmpeg', step: 'measureLoudness' })

    return new Promise((resolve) => {
        const p = spawn(FFMPEG_PATH, ['-hide_banner', '-nostdin', '-nostats', '-i', inputPath, '-vn', '-af', 'loudnorm=print_format=json', '-f', 'null', '-'], { signal });
        let stderr = '';
        p.stderr.on('data', (c) => { stderr += c; });
        p.on('error', (err) => { logProcessError(log, err, 'ffmpeg loudness measurement'); resolve(null); });
        p.on('close', (code) => {
            if (signal?.aborted) return resolve(null);
            const json = stderr.match(/\{[^{}]*"input_i"[^{}]*\}/)?.[0];
            if (code !== 0 || !json) {
                log.debug({ code, stderrTail: stderr.slice(-1000) });
                log.warn('Loudness measurement produced no result');
                return resolve(null);
            }
            try {
                const j = JSON.parse(json);
                const loudness = { integratedLufs: num(j.input_i) ?? undefined, truePeakDbtp: num(j.input_tp) ?? undefined, loudnessRangeLu: num(j.input_lra) ?? undefined };
                log.debug({ loudness });
                log.info('Measured loudness');
                resolve(loudness);
            } catch (err) {
                log.error({ err }, 'Failed to parse loudnorm output');
                resolve(null);
            }
        });
    });
}

/** Decode to 8 kHz mono PCM and keep the max |sample| per bin. */
export function computeWaveform(inputPath: string, bins = 200, signal?: AbortSignal): Promise<number[] | null> {
    const log = getLogger().child({ module: 'ffmpeg', step: 'computeWaveform' })

    return new Promise((resolve) => {
        const p = spawn(FFMPEG_PATH, ['-hide_banner', '-loglevel', 'error', '-nostdin', '-i', inputPath, '-vn', '-ac', '1', '-ar', '8000', '-f', 's16le', '-'], { signal });
        const chunks: Buffer[] = [];
        let stderr = '';
        p.stdout.on('data', (c: Buffer) => chunks.push(c));
        p.stderr.on('data', (c) => { stderr = (stderr + c).slice(-2000); });
        p.on('error', (err) => { logProcessError(log, err, 'ffmpeg waveform decoding'); resolve(null); });
        p.on('close', (code) => {
            if (signal?.aborted) return resolve(null);
            if (code !== 0) {
                log.debug({ code, stderr });
                log.warn('Waveform decoding failed');
                return resolve(null);
            }
            const buf = Buffer.concat(chunks);
            const samples = Math.floor(buf.length / 2);
            if (!samples) {
                log.warn('Waveform decoding produced no samples');
                return resolve(null);
            }
            const per = Math.max(1, Math.ceil(samples / bins));
            const out: number[] = [];
            for (let i = 0; i < samples; i += per) {
                let peak = 0;
                for (let j = i; j < Math.min(i + per, samples); j++) peak = Math.max(peak, Math.abs(buf.readInt16LE(j * 2)));
                out.push(Math.round((peak / 32768) * 1000) / 1000);
            }
            log.debug({ samples, bins: out.length });
            log.info('Computed waveform');
            resolve(out);
        });
    });
}

/**
 * Hash of the audio stream only (tags and cover art are ignored), so a re-tagged
 * or re-covered copy of the same file gets the same value. Returns undefined on failure.
 */
export function generateAudioSha256(inputPath: string, signal?: AbortSignal): Promise<string | undefined> {
    const log = getLogger().child({ module: 'ffmpeg', step: 'generateAudioSha256' })

    return new Promise((resolve) => {
        const p = spawn(FFMPEG_PATH, ['-hide_banner', '-loglevel', 'error', '-nostdin', '-i', inputPath, '-map', '0:a:0', '-c', 'copy', '-f', 'hash', '-hash', 'sha256', '-'], { signal });
        let out = '';
        let stderr = '';
        p.stdout.on('data', (c) => { out += c; });
        p.stderr.on('data', (c) => { stderr = (stderr + c).slice(-2000); });
        p.on('error', (err) => { logProcessError(log, err, 'ffmpeg audio hashing'); resolve(undefined); });
        p.on('close', (code) => {
            if (signal?.aborted) return resolve(undefined);
            const digest = code === 0 ? out.match(/SHA256=([0-9a-f]{64})/i)?.[1]?.toLowerCase() : undefined;
            if (!digest) {
                log.debug({ code, stderr });
                log.warn('Audio stream hashing produced no result');
                return resolve(undefined);
            }
            log.debug({ audioSha256: digest });
            log.info('Computed audio stream sha256');
            resolve(digest);
        });
    });
}

/* ------------------------------------------------------------------ */
/* Main entry point                                                   */
/* ------------------------------------------------------------------ */

/**
 * Extracts tags, technical info, covers and derived analysis from an audio file.
 * Rejects with ExtractionTimeoutError after `opts.timeoutMs`. The timeout also kills
 * the ffmpeg child processes that are still running. (probeFile has no abort support;
 * see the note in the answer if you want ffprobe covered too.)
 */
export async function extractMetadata(filePath: string, originalName: string, opts: ExtractOptions = {}): Promise<ExtractionResult> {
    const log = getLogger().child({ module: 'ffmpeg', step: 'extractMetadata' })

    const startedAt = Date.now();
    const timeoutMs = opts.timeoutMs ?? DEFAULT_EXTRACTION_TIMEOUT_MS;
    const withLoudness = opts.loudness ?? true;
    const withWaveform = opts.waveform ?? true;
    const warnings: string[] = [];

    log.debug({ filePath, originalName, withLoudness, withWaveform, timeoutMs });
    log.info('Starting metadata extraction');

    /* ---- gather raw data, all in parallel, under one time budget ---- */
    const ac = new AbortController();
    let timer: NodeJS.Timeout | undefined;
    const timeout = new Promise<never>((_, reject) => {
        timer = setTimeout(() => {
            ac.abort();                                   // kills any ffmpeg still running
            reject(new ExtractionTimeoutError(timeoutMs));
        }, timeoutMs);
    });

    let raw;
    try {
        raw = await Promise.race([
            Promise.all([
                parseFile(filePath, { duration: true }).catch((err: Error) => {
                    log.warn({ err }, 'Tag parser failed; using ffprobe/filename only');
                    warnings.push(`Tag parser failed (${err.message}); using ffprobe/filename only`);
                    return null;
                }),
                (probeFile(filePath) as Promise<unknown> as Promise<FfprobeResult>),   // throws FfprobeError -> route answers 422
                sha256(filePath, ac.signal),
                stat(filePath),
                withLoudness ? measureLoudness(filePath, ac.signal) : null,
                withWaveform ? computeWaveform(filePath, 200, ac.signal) : null,
                generateAudioSha256(filePath, ac.signal),
            ]),
            timeout,
        ]);
    } catch (err) {
        ac.abort();                                       // on any failure, don't leave sibling ffmpeg processes running
        if (err instanceof ExtractionTimeoutError) log.error({ timeoutMs, elapsedMs: Date.now() - startedAt }, 'Metadata extraction timed out');
        else log.error({ err }, 'Metadata extraction failed while collecting raw data');
        throw err;
    } finally {
        clearTimeout(timer);
    }
    const [md, probe, hash, st, loudness, waveform, audioSha256] = raw;

    log.debug({
        hasTagParser: !!md, probeFormat: probe.format.format_name, streams: probe.streams.length,
        sizeBytes: st.size, sha256: hash, audioSha256, hasLoudness: !!loudness, waveformBins: waveform?.length,
    });
    log.info('Collected raw data from tag parser, ffprobe and analysis');

    const audio = probe.streams.find((s) => s.codec_type === 'audio');
    if (!audio) {
        log.warn('File contains no audio stream');
        throw new Error('File contains no audio stream');
    }

    if (!audioSha256) {
        log.error('Failed to generate audio sha256');
        throw new Error('Failed to generate sha 256');
    }

    /* ---- tags: embedded > ffprobe > filename ---- */
    const tags = emptyTags(md?.common.title ?? basename(originalName).split('.')[0]);
    const tagSources: ExtractionResult['tagSources'] = {};
    if (md) fill(tags, tagsFromParser(md.common), 'tags', tagSources);
    fill(tags, tagsFromFfprobe(probe), 'ffprobe', tagSources);
    fill(tags, tagsFromFilename(originalName), 'filename', tagSources);
    log.debug({ tags, tagSources });
    log.info('Merged tags from embedded tags, ffprobe and filename');

    /* ---- covers ---- */
    let covers: ExtractedCover[] = [], suggestedCoverIndex = undefined
    try {
        const pics = md?.common.picture ?? [];

        const best = selectCover(pics);

        covers = pics.map((p, index) => ({
            index, mime: p.format, kind: p.type ?? undefined, description: p.description ?? undefined, sizeBytes: p.data.byteLength, data: p.data,
        }));
        if (best) suggestedCoverIndex = pics.indexOf(best)
        log.debug({ covers: covers.map(({ data: _data, ...c }) => c), suggestedCoverIndex });
        log.info('Collected embedded covers');
    } catch (err) {
        log.warn({ err }, 'failed to extract cover art')
    }

    /* ---- technical ---- */
    const f = md?.format;
    const codec = audio.codec_name ?? f?.codec ?? undefined;
    const durationSec = f?.duration ?? num(probe.format.duration) ?? undefined;
    const technical: TechnicalInfo = {
        container: f?.container ?? probe.format.format_name ?? undefined,
        ffprobeFormat: probe.format.format_name ?? undefined,
        codec,
        codecProfile: f?.codecProfile ?? audio.profile ?? undefined,
        lossless: f?.lossless ?? (codec ? LOSSLESS.test(codec) : undefined),
        durationSec,
        bitrate: f?.bitrate ?? num(audio.bit_rate) ?? num(probe.format.bit_rate) ?? undefined,
        sampleRate: f?.sampleRate ?? num(audio.sample_rate) ?? undefined,
        bitDepth: f?.bitsPerSample ?? (num(audio.bits_per_raw_sample) || audio.bits_per_sample || undefined),
        channels: f?.numberOfChannels ?? audio.channels ?? undefined,
        channelLayout: audio.channel_layout ?? undefined,
        encoder: f?.tool ?? undefined,
        sizeBytes: st.size,
        sha256: hash,
        audioSha256,
        tagTypes: f?.tagTypes ?? [],
        replayGain: {
            trackGainDb: md?.common.replaygain_track_gain?.dB ?? undefined,
            trackPeak: md?.common.replaygain_track_peak?.ratio ?? undefined,
            albumGainDb: md?.common.replaygain_album_gain?.dB ?? undefined,
        },
        loudness: loudness ?? undefined,
        waveform: waveform ?? undefined,
    };
    log.debug({ technical: { ...technical, waveform: waveform ? `${waveform.length} bins` : undefined } });
    log.info('Built technical info');

    /* ---- sanity checks the admin should see ---- */
    const probeDur = num(probe.format.duration);
    if (durationSec && probeDur && Math.abs(durationSec - probeDur) > 1)
        warnings.push(`Duration disagrees between parsers (${durationSec.toFixed(1)}s vs ${probeDur.toFixed(1)}s); file may be truncated or corrupt`);

    if (!tags.audioTitle) warnings.push('No title found');

    if (!tags.artists?.length) warnings.push('No artist found');

    if ([tags.audioTitle, tags.album, ...(tags.artists ?? [])].some((s) => s && /[ÃÂ][\u0080-\u00BF]/.test(s)))
        warnings.push('Some text looks like mojibake (legacy tag encoding); please review spelling');

    if (md?.common.date && !normDate(md.common.date)) warnings.push(`Unrecognised date format "${md.common.date}"`);

    log.debug({ warnings });
    if (warnings.length) log.warn('Extraction finished with warnings for the admin to review');
    else log.info('Sanity checks passed with no warnings');

    log.debug({ elapsedMs: Date.now() - startedAt });
    log.info('Metadata extraction finished');

    return {
        tags, tagSources,
        syncedLyrics: md ? (syncedLyricsFrom(md.common) ?? undefined) : undefined,
        rawTags: md ? flattenNative(md) : {},
        technical, covers, suggestedCoverIndex, warnings, probe,
    };
}
