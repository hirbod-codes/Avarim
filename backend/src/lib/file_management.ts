import { Upload } from "@aws-sdk/lib-storage";
import { fileTypeFromFile } from "file-type";
import { s3 } from "..";
import { BUCKET_NAME, MAX_UPLOAD_SIZE } from "../configs";
import { Readable, Transform } from "stream";
import Busboy from 'busboy';
import { stat, unlink } from "fs/promises";
import { join } from "path";
import { randomUUID } from "crypto";
import { createWriteStream } from "fs";
import { pipeline } from "stream/promises";
import { UploadTooLargeError } from "../errors/UploadTooLargeError";
import { InvalidMediaError } from "../errors/InvalidMediaError";
import { Request } from "express";
import { DeleteObjectCommand, GetObjectCommand, HeadObjectCommand, S3ServiceException } from "@aws-sdk/client-s3";
import type { IncomingMessage } from 'node:http';
import { extname } from "node:path";

export async function detectContentType(filePath: string): Promise<{ mimeType: string; extension: string }> {
    const type = await fileTypeFromFile(filePath);
    if (!type) throw new InvalidMediaError('Could not determine file type from content');
    return { mimeType: type.mime, extension: type.ext };
}

/**
 * Base class for failures raised by the storage helpers in this file.
 * Always an HTTP 500: if one of these is thrown, it's the server's (or S3's) problem, never the client's.
 * `status` and `statusCode` are both set because Express' default handler reads `status`,
 * while many custom handlers read `statusCode`. `expose = false` keeps bucket/key details out of the response.
 */
export class FileManagementError extends Error {
    readonly status = 500;
    readonly statusCode = 500;
    readonly expose = false;
    constructor(message: string, public readonly cause?: unknown) {
        super(message);
        this.name = "FileManagementError";
    }
}

export class S3OperationError extends FileManagementError {
    constructor(message: string, public readonly operation: "upload" | "delete" | "head" | "download", public readonly key: string, cause?: unknown) {
        super(message, cause);
        this.name = "S3OperationError";
    }
}
/**
 * returns zero if not found
 * @param key 
 * @returns 
 */
export async function getS3ObjectSize(key: string): Promise<number> {
    try {
        const result = await s3.send(
            new HeadObjectCommand({
                Bucket: BUCKET_NAME,
                Key: key,
            })
        );

        // ContentLength is in bytes
        return result.ContentLength ?? 0;
    } catch (err) {
        if (err instanceof S3ServiceException) {
            if (err.name === "NotFound") {
                return 0
            }
            throw new S3OperationError(`Failed to get metadata for "${key}": ${err.name}`, "head", key, err);
        }
        throw new S3OperationError(`Failed to get metadata for "${key}": ${(err as Error).message}`, "head", key, err);
    }
}

/**
 * Uploads a stream to `key`. If an object already exists at `key` it is REPLACED (S3's default:
 * a plain PUT overwrites, and the swap is atomic, readers see the old or the new object, never a mix).
 * Pass `contentType` when replacing: an upload without one stores the new object with S3's default
 * type and does not keep the old object's.
 * With `start = false` the caller awaits `upload.done()` later and gets the SDK's raw errors, not S3OperationError.
 */
export async function uploadToS3(readStream: Readable, key: string, contentType?: string, start: boolean = true): Promise<Upload> {
    if (!key)
        throw new S3OperationError("S3 key must not be empty", "upload", key);

    let upload: Upload;
    try {
        upload = new Upload({
            client: s3,
            params: {
                Bucket: BUCKET_NAME,
                Key: key,
                Body: readStream,
                ...(contentType ? { ContentType: contentType } : {}),
            },
        });
    } catch (err) {
        throw new S3OperationError(`Failed to upload object "${key}": ${(err as Error).message ?? "unknown error"}`, "upload", key, err);
    }

    // Surface read-stream errors even if 'start' is false and caller
    // awaits upload.done() later — otherwise these can go unhandled.
    readStream.on("error", (err) => {
        upload.abort().catch(() => {
            // best-effort abort; ignore secondary failure
        });
    });

    if (start) {
        try {
            await upload.done();
        } catch (err) {
            // Make sure any partial multipart upload is cleaned up.
            try { await upload.abort(); }
            catch {
                // ignore abort failure, original error is more important
            }

            if (err instanceof S3ServiceException) {
                throw new S3OperationError(`Failed to upload object "${key}": ${err.name} (${err.$metadata?.httpStatusCode ?? "?"})`, "upload", key, err);
            }

            throw new S3OperationError(`Failed to upload object "${key}": ${(err as Error).message ?? "unknown error"}`, "upload", key, err);
        }
    }

    return upload;
}

/**
 * function returns if key is not found
 * 
 * @param Key 
 * @returns 
 */
export async function deleteFromS3(Key: string): Promise<void> {
    if (!Key)
        throw new S3OperationError("S3 key must not be empty", "delete", Key);

    try {
        await s3.send(
            new DeleteObjectCommand({
                Bucket: BUCKET_NAME,
                Key,
            })
        );
    } catch (err) {
        if (err instanceof S3ServiceException) {
            // treat NoSuchKey as a no-op.
            if (err.name === "NoSuchKey")
                return;

            throw new S3OperationError(`Failed to delete object "${Key}": ${err.name} (${err.$metadata?.httpStatusCode ?? "?"})`, "delete", Key, err);
        }

        throw new S3OperationError(`Failed to delete object "${Key}": ${(err as Error).message ?? "unknown error"}`, "delete", Key, err);
    }
}

/* ------------------------------------------------------------------ */
/* Download                                                           */
/* ------------------------------------------------------------------ */

/**
 * True when an error (raw SDK error or an S3OperationError wrapping one) means "this object doesn't exist".
 * Deliberately NOT a generic 404 check: a missing bucket (NoSuchBucket) is also a 404, but that's a
 * misconfiguration and must surface as an error, not as "not found".
 */
export function isS3NotFound(err: unknown): boolean {
    const cause = err instanceof S3OperationError ? err.cause : err;
    return cause instanceof S3ServiceException && (cause.name === "NoSuchKey" || cause.name === "NotFound");
}

function toDownloadError(err: unknown, key: string): S3OperationError {
    if (err instanceof S3OperationError) return err;
    if (err instanceof S3ServiceException) {
        return new S3OperationError(`Failed to download object "${key}": ${err.name} (${err.$metadata?.httpStatusCode ?? "?"})`, "download", key, err);
    }
    return new S3OperationError(`Failed to download object "${key}": ${(err as Error).message ?? "unknown error"}`, "download", key, err);
}

export interface S3ObjectStream {
    stream: Readable;
    contentLength?: number;
    contentType?: string;
    contentRange?: string;
}

/**
 * Opens a read stream for an object (optionally just a byte range).
 * The caller owns the stream: consume it or destroy() it, otherwise the HTTP connection stays open.
 *
 * @param range an HTTP Range value such as "bytes=0-1023"
 * @returns undefined if the object doesn't exist
 * @throws S3OperationError (HTTP 500) for every other failure
 */
export async function getS3ObjectStream(key: string, options: { range?: string; signal?: AbortSignal } = {}): Promise<S3ObjectStream | undefined> {
    if (!key)
        throw new S3OperationError("S3 key must not be empty", "download", key);

    try {
        const result = await s3.send(
            new GetObjectCommand({
                Bucket: BUCKET_NAME,
                Key: key,
                ...(options.range ? { Range: options.range } : {}),
            }),
            { abortSignal: options.signal },
        );

        if (!(result.Body instanceof Readable))
            throw new Error("Object has no readable body");

        return {
            stream: result.Body,
            contentLength: result.ContentLength,
            contentType: result.ContentType,
            contentRange: result.ContentRange,
        };
    } catch (err) {
        if (isS3NotFound(err)) return undefined;
        throw toDownloadError(err, key);
    }
}

/**
 * Downloads an object to a file on disk (e.g. a temp dir, for ffmpeg or metadata extraction).
 *
 * - Never overwrites: fails if `destPath` already exists, and in that case leaves the existing file alone.
 * - On any failure (network drop, abort, incomplete body) the partial file is deleted.
 * - Checks the final size against the object's Content-Length, so a silently truncated download is an error.
 * - The destination directory must already exist.
 *
 * @returns undefined if the object doesn't exist (no file is created)
 * @throws S3OperationError (HTTP 500) for every other failure
 */
export async function downloadFromS3(key: string, destPath: string, options: { signal?: AbortSignal } = {}): Promise<{ path: string; size: number; contentType?: string } | undefined> {
    // Open the object first, so a missing key never leaves an empty file behind.
    const object = await getS3ObjectStream(key, { signal: options.signal });
    if (!object) return undefined;
    const { stream, contentLength, contentType } = object;

    try {
        await pipeline(stream, createWriteStream(destPath, { flags: "wx" }), { signal: options.signal });

        const { size } = await stat(destPath);
        if (contentLength !== undefined && size !== contentLength)
            throw new Error(`Incomplete download: expected ${contentLength} bytes, got ${size}`);

        return { path: destPath, size, contentType };
    } catch (err) {
        // EEXIST means the file isn't ours (it existed before): never delete it.
        if ((err as NodeJS.ErrnoException).code !== "EEXIST")
            await unlink(destPath).catch(() => { });
        throw toDownloadError(err, key);
    }
}

/**
 * Busboy expects Node's plain IncomingHttpHeaders record. Some setups
 * (Express 5, fetch-based adapters/middleware) type or actually provide
 * req.headers as a Fetch API Headers instance instead, which has no index
 * signature and can't be passed directly. Normalize either shape to a
 * plain object.
 */
export function toPlainHeaders(headers: Request['headers'] | globalThis.Headers): Record<string, string> {
    if (typeof (headers as globalThis.Headers)?.entries === 'function') {
        return Object.fromEntries((headers as globalThis.Headers).entries());
    }
    return headers as unknown as Record<string, string>;
}


const ALLOWED_EXT = /^\.[a-z0-9]{1,5}$/i;

export function receiveUpload(req: IncomingMessage, fileSizeLimit: number | undefined, destDir: string): Promise<{ path: string; size: number; originalFilename: string }> {
    fileSizeLimit = Math.min(fileSizeLimit ?? Infinity, MAX_UPLOAD_SIZE)

    return new Promise((resolve, reject) => {
        const contentType = req.headers['content-type'] ?? '';
        if (!contentType.startsWith('multipart/form-data')) {
            reject(new InvalidMediaError('Expected multipart/form-data'));
            return;
        }

        const bb = Busboy({ headers: req.headers, limits: { files: 1, fileSize: fileSizeLimit } });

        let handled = false;
        let tempPath: string | null = null;
        let originalFilename = 'upload';

        const fail = (err: Error) => {
            if (handled) return;
            handled = true;
            if (tempPath) unlink(tempPath).catch(() => { });
            reject(err);
        };

        let fileSeen = false;

        bb.on('file', (_name, file, info) => {
            fileSeen = true;

            originalFilename = info.filename || originalFilename;
            const ext = extname(originalFilename);
            tempPath = join(destDir, `${randomUUID()}-input${ALLOWED_EXT.test(ext) ? ext : ''}`);
            const writeStream = createWriteStream(tempPath);

            let limitExceeded = false;
            file.on('limit', () => {
                limitExceeded = true;
                writeStream.destroy();
                file.resume();
            });

            pipeline(file, writeStream)
                .then(async () => {
                    if (limitExceeded) {
                        fail(new UploadTooLargeError(`File exceeds plan limit of ${fileSizeLimit} bytes`));
                        return;
                    }
                    if (handled) return;
                    handled = true;
                    const { size } = await stat(tempPath!);
                    resolve({ path: tempPath!, size, originalFilename });
                })
                .catch((err) => fail(limitExceeded
                    ? new UploadTooLargeError(`File exceeds plan limit of ${fileSizeLimit} bytes`)
                    : err));
        });

        bb.on('error', (err) => fail(err as Error));
        bb.on('filesLimit', () => fail(new Error('Only one file allowed per upload')));
        bb.on('close', () => { if (!fileSeen) fail(new InvalidMediaError('No file found in upload')) });

        req.on('error', (err) => fail(err));
        req.pipe(bb);
    });
}
