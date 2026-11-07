import { Upload } from "@aws-sdk/lib-storage";
import { fileTypeFromFile } from "file-type";
import { s3 } from "..";
import { BUCKET_NAME, MAX_UPLOAD_SIZE } from "../configs";
import { Readable } from "stream";
import Busboy from 'busboy';
import { stat, unlink } from "fs/promises";
import { join } from "path";
import { randomUUID } from "crypto";
import { createWriteStream, type WriteStream } from "fs";
import { pipeline } from "stream/promises";
import { UploadTooLargeError } from "../errors/UploadTooLargeError";
import { InvalidMediaError } from "../errors/InvalidMediaError";
import { Request, Response } from "express";
import { DeleteObjectCommand, GetObjectCommand, HeadObjectCommand, S3ServiceException } from "@aws-sdk/client-s3";
import type { IncomingMessage } from 'node:http';
import { extname } from "node:path";
import { parseByteRangeHeader } from "../routes/schemas";

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
 * Like getS3ObjectSize, but tells "doesn't exist" (undefined) apart from "exists and is empty" (sizeInBytes: 0).
 *
 * @returns undefined if the object doesn't exist
 * @throws S3OperationError (HTTP 500) for every other failure
 */
export async function getS3ObjectInfo(key: string, options: { signal?: AbortSignal } = {}): Promise<{ sizeInBytes: number; contentType?: string } | undefined> {
    if (!key)
        throw new S3OperationError("S3 key must not be empty", "head", key);

    try {
        const result = await s3.send(
            new HeadObjectCommand({ Bucket: BUCKET_NAME, Key: key }),
            { abortSignal: options.signal },
        );
        return { sizeInBytes: result.ContentLength ?? 0, contentType: result.ContentType };
    } catch (err) {
        if (isS3NotFound(err)) return undefined;
        if (err instanceof S3ServiceException)
            throw new S3OperationError(`Failed to get metadata for "${key}": ${err.name} (${err.$metadata?.httpStatusCode ?? "?"})`, "head", key, err);
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
    readStream.on("error", () => {
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

/** True when S3 refused a Range because it starts past the end of the object (e.g. a stale stored size). */
export function isS3InvalidRange(err: unknown): boolean {
    const cause = err instanceof S3OperationError ? err.cause : err;
    return cause instanceof S3ServiceException && cause.name === "InvalidRange";
}

function isAbortError(error: unknown): boolean {
    return (error as { name?: string }).name === 'AbortError';
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
 * A browser asks for "bytes=0-" and then reads at the speed of playback, so one open-ended request keeps
 * an S3 socket busy for the whole track. Answering with at most this many bytes makes every socket
 * short-lived; the player simply asks for the next chunk. (A 206 may be shorter than requested.)
 */
const MAX_BYTES_PER_RESPONSE = 2 * 1024 * 1024;

/**
 * Streams the object at `key` to the client, honouring a `Range` header (audio/video players need it to seek).
 *
 * `sizeInBytes` is the object's size if you already know it (store it at upload time: it saves a request).
 * `undefined` and `0` both mean "unknown": the size is then read from S3 (HeadObject) before the range is checked,
 * so ranges are validated against the real size either way. Do NOT pass getS3ObjectSize()'s result here: it
 * returns 0 for a missing object, which would look like an empty file.
 *
 * It always answers the request itself:
 *   200 whole object | 206 requested range (at most MAX_BYTES_PER_RESPONSE per response) |
 *   400 malformed Range | 404 object doesn't exist | 416 range outside the object
 * The error responses are JSON, `{ status: 'error', error_code }`; set the 404's code with `notFoundErrorCode`.
 * Real failures (S3 errors, S3 breaking mid-stream) are thrown for your error middleware; if the headers
 * were already sent it must only close the connection (check `res.headersSent`) rather than write a JSON body.
 * A player that leaves (seek, closed tab) is not an error: nothing is thrown and the S3 socket is released.
 */
export async function handleS3ObjectStream(
    req: Request,
    res: Response,
    key: string,
    contentType: string,
    sizeInBytes?: number,
    options: { notFoundErrorCode?: string } = {},
): Promise<void> {
    // While we are still waiting for S3 to answer (possibly queued for a socket): if the player goes away
    // (seek, tab closed), cancel that request instead of letting it run for nobody.
    const s3RequestAbortController = new AbortController();
    const cancelS3RequestWhenClientLeaves = () => s3RequestAbortController.abort();
    res.once('close', cancelS3RequestWhenClientLeaves);

    // Used to tell a player that left from a broken S3 stream (see the catch block).
    let clientLeftWhileS3StreamWasHealthy = false;
    let totalSizeInBytes: number | undefined;

    const onNotFound = () => {
        res.status(404).json({ status: 'error', error_code: options.notFoundErrorCode ?? 'FILE_NOT_FOUND' });
    };

    const onInvalidRangeHeader = () => { };
    const onRangeNotSatisfied = () => { };
    const on = () => { };

    try {
        // Unknown size: ask S3. That also tells us whether the object exists at all.
        const knownSizeInBytes = sizeInBytes !== undefined && sizeInBytes > 0 ? sizeInBytes : undefined;
        totalSizeInBytes = knownSizeInBytes ?? (await getS3ObjectInfo(key, { signal: s3RequestAbortController.signal }))?.sizeInBytes;
        if (totalSizeInBytes === undefined) {
            onNotFound();
            return;
        }

        const range = parseByteRangeHeader(req.headers.range, totalSizeInBytes);

        res.setHeader('Accept-Ranges', 'bytes');

        if (range.kind === 'malformed') {
            res.status(400).json({ status: 'error', error_code: 'INVALID_RANGE_HEADER' });
            return;
        }
        if (range.kind === 'unsatisfiable') {
            res.setHeader('Content-Range', `bytes */${totalSizeInBytes}`);
            res.status(416).json({ status: 'error', error_code: 'RANGE_NOT_SATISFIABLE' });
            return;
        }

        const startByteInclusive = range.kind === 'partial' ? range.startByteInclusive : 0;
        const endByteInclusive = range.kind === 'partial'
            ? Math.min(range.endByteInclusive, startByteInclusive + MAX_BYTES_PER_RESPONSE - 1)
            : totalSizeInBytes - 1;

        const s3Response = await getS3ObjectStream(key, {
            signal: s3RequestAbortController.signal,
            ...(range.kind === 'partial' && { range: `bytes=${startByteInclusive}-${endByteInclusive}` }),
        });
        // From here on pipeline() cleans up (destroys the S3 stream) when the client leaves.
        res.off('close', cancelS3RequestWhenClientLeaves);

        if (!s3Response) {
            onNotFound(); // deleted since the size check
            return;
        }

        const s3Body = s3Response.stream;
        res.once('close', () => {
            if (!s3Body.destroyed) clientLeftWhileS3StreamWasHealthy = true;
        });

        // The headers describe what S3 actually sends, so a stale stored size can't make them lie about the body.
        res.type(contentType || s3Response.contentType || 'application/octet-stream');
        res.setHeader('Content-Length', s3Response.contentLength ?? endByteInclusive - startByteInclusive + 1);
        if (range.kind === 'partial') {
            res.status(206);
            res.setHeader('Content-Range', s3Response.contentRange ?? `bytes ${startByteInclusive}-${endByteInclusive}/${totalSizeInBytes}`);
        }

        // pipeline (not Body.pipe(res)) destroys the S3 stream when the client disconnects, which frees the socket.
        await pipeline(s3Body, res);
    } catch (err) {
        // pipeline() destroys `res` on ANY failure, and a player that leaves mid-stream can surface as an S3-looking
        // ECONNRESET ("aborted"), so neither `res.destroyed` nor the error code can tell a disconnect from a broken
        // S3 stream. The state of the S3 stream at the moment `res` closed can: still healthy = the player left;
        // already destroyed = S3 broke first.
        // (getS3ObjectStream wraps SDK errors, so an abort during the wait arrives as an S3OperationError:
        // the signal is what tells us the player left.)
        if (s3RequestAbortController.signal.aborted || isAbortError(err)) return; // the player left while we were waiting for S3
        if (clientLeftWhileS3StreamWasHealthy) return; // the player left mid-stream

        // The stored size was larger than the real object, so S3 refused the range.
        if (isS3InvalidRange(err) && !res.headersSent) {
            const realSizeInBytes = (await getS3ObjectInfo(key).catch(() => undefined))?.sizeInBytes;
            res.setHeader('Content-Range', `bytes */${realSizeInBytes ?? totalSizeInBytes}`);
            res.status(416).json({ status: 'error', error_code: 'RANGE_NOT_SATISFIABLE' });
            return;
        }

        throw err;
    } finally {
        res.off('close', cancelS3RequestWhenClientLeaves);
    }
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

/**
 * Receives ONE multipart file upload into `destDir` (a temp file) and resolves once it is fully on disk.
 * The caller owns the temp file afterwards. On any failure the temp file is removed and the request is no longer read.
 */
export function receiveUpload(req: IncomingMessage, fileSizeLimit: number | undefined, destDir: string): Promise<{ path: string; size: number; originalFilename: string }> {
    const effectiveFileSizeLimit = Math.min(fileSizeLimit ?? Infinity, MAX_UPLOAD_SIZE);

    return new Promise((resolve, reject) => {
        const contentType = req.headers['content-type'] ?? '';
        if (!contentType.toLowerCase().startsWith('multipart/form-data')) {
            reject(new InvalidMediaError('Expected multipart/form-data'));
            return;
        }

        let bb: ReturnType<typeof Busboy>;
        try {
            bb = Busboy({ headers: req.headers, limits: { files: 1, fileSize: effectiveFileSizeLimit } });
        } catch (err) {
            // e.g. a multipart Content-Type without a boundary: the client's mistake, not a server error
            reject(new InvalidMediaError(`Malformed multipart request: ${(err as Error).message}`));
            return;
        }

        let isSettled = false;
        let tempPath: string | null = null;
        let tempFileWriteStream: WriteStream | null = null;
        let receivedFile: Readable | null = null;
        let originalFilename = 'upload';

        const fail = (err: Error) => {
            if (isSettled) return;
            isSettled = true;

            // Stop reading the request and release everything that is still open. Without this, an upload that is
            // aborted half-way leaves the file stream waiting for data that never comes, holding an open file
            // handle to a temp file that has already been deleted.
            req.unpipe(bb);
            bb.destroy();
            receivedFile?.destroy();
            if (tempPath) {
                const pathToRemove = tempPath;
                // Delete only once the stream has closed: the file might not even exist yet (it is opened asynchronously).
                if (tempFileWriteStream && !tempFileWriteStream.closed) {
                    tempFileWriteStream.once('close', () => unlink(pathToRemove).catch(() => { }));
                    tempFileWriteStream.destroy();
                } else {
                    unlink(pathToRemove).catch(() => { });
                }
            }
            reject(err);
        };

        let fileSeen = false;

        bb.on('file', (_name, file, info) => {
            fileSeen = true;
            receivedFile = file;

            originalFilename = info.filename || originalFilename;
            const ext = extname(originalFilename);
            tempPath = join(destDir, `${randomUUID()}-input${ALLOWED_EXT.test(ext) ? ext : ''}`);
            const writeStream = createWriteStream(tempPath);
            tempFileWriteStream = writeStream;

            let limitExceeded = false;
            file.on('limit', () => {
                limitExceeded = true;
                writeStream.destroy();
                file.resume();
            });

            pipeline(file, writeStream)
                .then(async () => {
                    if (limitExceeded) {
                        fail(new UploadTooLargeError(`File exceeds plan limit of ${effectiveFileSizeLimit} bytes`));
                        return;
                    }
                    if (isSettled) return;
                    const { size } = await stat(tempPath!);
                    // Only now is it settled: if stat() throws, the catch below must still be able to reject.
                    if (isSettled) return;
                    isSettled = true;
                    resolve({ path: tempPath!, size, originalFilename });
                })
                .catch((err) => fail(limitExceeded
                    ? new UploadTooLargeError(`File exceeds plan limit of ${effectiveFileSizeLimit} bytes`)
                    : err));
        });

        bb.on('error', (err) => fail(err as Error));
        bb.on('filesLimit', () => fail(new Error('Only one file allowed per upload')));
        bb.on('close', () => { if (!fileSeen) fail(new InvalidMediaError('No file found in upload')) });

        req.on('error', (err) => fail(err));
        req.pipe(bb);
    });
}
