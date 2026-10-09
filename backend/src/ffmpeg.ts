import { createReadStream } from 'fs';
import { unlink } from 'fs/promises';
import { join } from 'path';
import { spawn } from "child_process";
import { Readable } from "stream";
import { FfmpegError } from './errors/FfmpegError';
import { FfprobeError } from './errors/FfprobeError';
import { existsSync, chmodSync } from 'node:fs';

function resolveBinary(name: 'ffmpeg' | 'ffprobe'): string {
    // Env override wins (useful for CI, Docker, or a system install)
    const override = process.env[`${name.toUpperCase()}_PATH`];
    if (override) return override;

    const file = process.platform === 'win32' ? `ffmpeg-8.1-essentials_build\\bin\\${name}.exe` : `ffmpeg-7.0.2-amd64-static/${name}`;
    const fullPath = join(process.cwd(), 'src', file);

    if (!existsSync(fullPath)) {
        throw new Error(`${name} binary not found at ${fullPath}`);
    }

    if (process.platform !== 'win32') {
        try { chmodSync(fullPath, 0o755); }
        catch {
            console.error("failed to make the file executable, in this line 'chmodSync(fullPath, 0o755);'")
            /* read-only fs; hope it's already executable */
        }
    }

    return fullPath;
}

export const FFPROBE_PATH = resolveBinary('ffprobe');
export const FFMPEG_PATH = resolveBinary('ffmpeg');

interface ProbeInfo {
    index: number;
    codec_type: 'video' | 'audio' | string;
    codec_name: string;
    disposition?: { attached_pic?: number };

}

type MediaType = 'video' | 'audio';
type Action = 'transcoded' | 'remuxed' | 'passthrough';

const WEB_SAFE_VIDEO_CODECS = new Set(['h264', 'vp9']);
const WEB_SAFE_AUDIO_CODECS_IN_VIDEO = new Set(['aac', 'opus']);
const WEB_SAFE_STANDALONE_AUDIO_CODECS = new Set(['aac', 'mp3']);

export function probeFile(filePath: string): Promise<{ streams: ProbeInfo[]; format: { duration?: string }; }> {
    return new Promise((resolve, reject) => {
        const args = [
            '-v', 'error',
            '-print_format', 'json',
            '-show_format',
            '-show_streams',
            filePath,
        ];

        const proc = spawn(FFPROBE_PATH, args);

        let stdout = '';
        let stderr = '';
        let settled = false;

        const settle = (fn: () => void) => {
            if (settled) return;
            settled = true;
            fn();
        };

        proc.stdout.on('data', (chunk) => { stdout += chunk; });
        proc.stderr.on('data', (chunk) => { stderr += chunk; });

        proc.on('error', (err: NodeJS.ErrnoException) => {
            const msg = err.code === 'ENOENT'
                ? 'ffprobe binary not found; install FFmpeg or set FFPROBE_PATH'
                : `ffprobe spawn failed: ${err.message}`;
            settle(() => reject(new FfprobeError(msg)));
        });

        proc.on('close', (code) => {
            settle(() => {
                if (code !== 0) {
                    reject(new FfprobeError(`ffprobe exited with code ${code}: ${stderr}`));
                    return;
                }

                try {
                    resolve(JSON.parse(stdout) as { streams: ProbeInfo[]; format: { duration?: string }; });
                } catch (err) {
                    reject(new FfprobeError(`Failed to parse ffprobe output: ${(err as Error).message}`));
                }
            });
        });
    });
}

/**
 * Runs ffmpeg to completion writing to a real output file (not a pipe), so standard `-movflags +faststart` can seek back and rewrite the header once encoding is done.
 */
export function runFfmpeg(args: string[]): Promise<void> {
    return new Promise((resolve, reject) => {
        const proc = spawn(FFMPEG_PATH, ['-hide_banner', '-loglevel', 'error', '-nostdin', ...args]);

        let stderr = '';
        let settled = false;

        const settle = (fn: () => void) => {
            if (settled) return;
            settled = true;
            fn();
        };

        proc.stderr.on('data', (chunk) => {
            stderr += chunk;
            if (stderr.length > 64_000) {
                stderr = stderr.slice(-64_000);
            }
        });

        proc.on('error', (err) => {
            settle(() => reject(new FfmpegError(`ffmpeg spawn failed: ${err.message}`)));
        });

        proc.on('close', (code) => {
            settle(() => {
                if (code !== 0) {
                    reject(new FfmpegError(`ffmpeg exited with code ${code}: ${stderr}`));
                    return;
                }
                resolve();
            });
        });
    });
}

/**
 * Returns a Readable for outputPath that deletes the file once fully consumed (or on error/early destroy), so scratch disk usage doesn't accumulate under load.
 */
function readAndCleanup(outputPath: string): Readable {
    const stream = createReadStream(outputPath);
    const cleanup = () => { unlink(outputPath).catch(() => { }); };
    stream.once('close', cleanup);
    stream.once('error', cleanup);
    return stream;
}

export function isWebCompatible(videoProbInfo?: ProbeInfo, audioProbInfo?: ProbeInfo): boolean {
    if (videoProbInfo) {
        const videoOk = WEB_SAFE_VIDEO_CODECS.has(videoProbInfo.codec_name);
        const audioOk = !audioProbInfo || WEB_SAFE_AUDIO_CODECS_IN_VIDEO.has(audioProbInfo.codec_name);
        return videoOk && audioOk;
    }

    if (audioProbInfo) {
        return WEB_SAFE_STANDALONE_AUDIO_CODECS.has(audioProbInfo.codec_name);
    }

    throw new Error('No video or audio stream found');
}

/**
 * Given an already-uploaded file on disk, returns a stream of a web-safe
 * copy — video or audio — ready to pipe into an S3 upload or similar.
 *
 * - Video: web-compatible sources (H.264/AAC or VP9/Opus) are remuxed
 *   with faststart (cheap stream copy); anything else is transcoded once
 *   to H.264/AAC MP4 with faststart.
 * - Audio-only: sources already in a browser-safe codec (AAC/MP3) are
 *   passed through untouched — no ffmpeg call, no scratch file, the
 *   original upload is streamed as-is. Anything else is transcoded once
 *   to AAC (.m4a).
 *
 * Callers on native platforms (Windows/Android via media_kit) don't need
 * this at all since libmpv already decodes almost anything — call this
 * only when producing the web-targeted copy.
 */
export async function generateWebCompatibleCopy(inputPath: string, videoUploadTmpDir: string, outputFileName: string, videoProbInfo?: ProbeInfo, audioProbInfo?: ProbeInfo): Promise<{ mediaType: MediaType, action: Action, outputStream: Readable }> {
    if (videoProbInfo) {
        const videoOk = WEB_SAFE_VIDEO_CODECS.has(videoProbInfo.codec_name);
        const audioOk = !audioProbInfo || WEB_SAFE_AUDIO_CODECS_IN_VIDEO.has(audioProbInfo.codec_name);
        const webCompatible = videoOk && audioOk;

        const outputPath = join(videoUploadTmpDir, `${outputFileName}.mp4`);

        const args = webCompatible
            ? [
                '-y',
                '-i', inputPath,
                '-c', 'copy',
                '-movflags', '+faststart',
                outputPath,
            ]
            : [
                '-y',
                '-i', inputPath,
                '-c:v', 'libx264',
                '-preset', 'veryfast',
                '-crf', '23',
                '-pix_fmt', 'yuv420p',      // avoids chroma-format playback issues on Safari/older browsers
                '-c:a', 'aac',
                '-b:a', '128k',
                '-movflags', '+faststart',
                outputPath,
            ];

        await runFfmpeg(args);

        return {
            mediaType: 'video',
            action: webCompatible ? 'remuxed' : 'transcoded',
            outputStream: readAndCleanup(outputPath),
        };
    }

    if (audioProbInfo) {
        const webCompatible = WEB_SAFE_STANDALONE_AUDIO_CODECS.has(audioProbInfo.codec_name);

        // Already playable in the browser — stream the original file
        // untouched, no ffmpeg invocation at all.
        if (webCompatible)
            return {
                mediaType: 'audio',
                action: 'passthrough',
                outputStream: createReadStream(inputPath),
            };

        const outputPath = join(videoUploadTmpDir, `${outputFileName}.m4a`);

        await runFfmpeg([
            '-y',
            '-i', inputPath,
            '-vn',                      // drop the cover-art "video" stream
            '-map', '0:a:0',            // first audio stream only (optional but explicit)
            '-c:a', 'aac',
            '-b:a', '192k',
            '-movflags', '+faststart',
            '-map_metadata', '0',       // keep title/artist/album tags
            outputPath,
        ]);

        return {
            mediaType: 'audio',
            action: 'transcoded',
            outputStream: readAndCleanup(outputPath),
        };
    }

    throw new Error(`No video or audio stream found in ${inputPath}`);
}


export async function generateThumbnail(inputPath: string, outputPath: string, durationSeconds?: number): Promise<void> {
    // Input-side seeking (-ss before -i) is fast/keyframe-based. Pick a point
    // a little into the clip so we don't grab a black first frame, but never
    // past a very short clip's actual length.
    const seekTime = durationSeconds && durationSeconds > 2 ? Math.min(1, durationSeconds * 0.1) : 0;

    await runFfmpeg([
        '-y',
        '-ss', String(seekTime),
        '-i', inputPath,
        '-vframes', '1',
        '-vf', 'scale=640:-2',
        '-q:v', '3',
        outputPath,
    ]);
}

const COVER_ART_FORMATS: Record<string, { extension: string; mimeType: string }> = {
    mjpeg: { extension: 'jpg', mimeType: 'image/jpeg' },
    png: { extension: 'png', mimeType: 'image/png' },
    bmp: { extension: 'bmp', mimeType: 'image/bmp' },
    gif: { extension: 'gif', mimeType: 'image/gif' },
};

/**
 * Extracts embedded cover art (ID3 APIC, FLAC METADATA_BLOCK_PICTURE, MP4
 * covr atom — ffprobe reports all of these as a video stream flagged
 * disposition.attached_pic) via stream copy. Returns null if the file has
 * no embedded art, or if it's in an image codec we don't recognize —
 * either way, missing cover art should never fail the upload.
 */
export async function extractCoverArt(inputPath: string, streams: ProbeInfo[], workDir: string, outputFileName: string): Promise<{ path: string, extension: string, mimeType: string } | null> {
    const coverStream = streams.find((s) => s.codec_type === 'video' && s.disposition?.attached_pic === 1);
    if (!coverStream) return null;

    const format = COVER_ART_FORMATS[coverStream.codec_name];
    if (!format) return null;

    const outputPath = join(workDir, `${outputFileName}.${format.extension}`);
    await runFfmpeg([
        '-y',
        '-i', inputPath,
        '-map', `0:${coverStream.index}`,
        '-c', 'copy',
        outputPath,
    ]);

    return { path: outputPath, ...format };
}
