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
import { DeleteObjectCommand, HeadObjectCommand, S3ServiceException } from "@aws-sdk/client-s3";
import type { IncomingMessage } from 'node:http';
import { extname } from "node:path";

export async function detectContentType(filePath: string): Promise<{ mimeType: string; extension: string }> {
    const type = await fileTypeFromFile(filePath);
    if (!type) throw new InvalidMediaError('Could not determine file type from content');
    return { mimeType: type.mime, extension: type.ext };
}

export class S3OperationError extends Error {
    constructor(message: string, public readonly operation: "upload" | "delete" | "head", public readonly key: string, public readonly cause?: unknown) {
        super(message);
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

export async function uploadToS3(readStream: Readable, key: string, contentType?: string, start: boolean = true): Promise<Upload> {
    if (!key)
        throw new S3OperationError("S3 key must not be empty", "upload", key);

    const upload = new Upload({
        client: s3,
        params: {
            Bucket: BUCKET_NAME,
            Key: key,
            Body: readStream,
            ...(contentType ? { ContentType: contentType } : {}),
        },
    });

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

export async function receiveUploadddddd(req: Request, fileSizeLimit: number, destDir: string, originalFilename = 'upload'): Promise<{ path: string; size: number; originalFilename: string }> {
    // Fail fast if the client declares a too-large body
    const declared = Number(req.headers['content-length']);
    if (Number.isFinite(declared) && declared > fileSizeLimit) {
        throw new UploadTooLargeError(`File exceeds plan limit of ${fileSizeLimit} bytes`);
    }

    const tempPath = join(destDir, `${randomUUID()}-input`);
    let received = 0;

    // Enforce the limit on actual bytes, since Content-Length can lie or be absent
    const limiter = new Transform({
        transform(chunk: Buffer, _enc, cb) {
            received += chunk.length;
            if (received > fileSizeLimit) {
                return cb(new UploadTooLargeError(`File exceeds plan limit of ${fileSizeLimit} bytes`));
            }
            cb(null, chunk);
        },
    });

    try {
        await pipeline(req, limiter, createWriteStream(tempPath));
    } catch (err) {
        await unlink(tempPath).catch(() => { });
        throw err;
    }

    return { path: tempPath, size: received, originalFilename };
}

export function receiveUploadd(req: Request, fileSizeLimit: number, destDir: string): Promise<{ path: string; size: number; originalFilename: string }> {
    fileSizeLimit = Math.min(fileSizeLimit, MAX_UPLOAD_SIZE)

    return new Promise((resolve, reject) => {
        const bb = Busboy({ headers: toPlainHeaders(req.headers), limits: { files: 1, fileSize: fileSizeLimit } });

        let handled = false;
        let tempPath: string | null = null;
        let originalFilename = 'upload';

        const fail = (err: Error) => {
            if (handled) return;
            handled = true;
            if (tempPath) unlink(tempPath).catch(() => { });
            reject(err);
        };

        bb.on('file', (_name, file, info) => {
            originalFilename = info.filename ?? originalFilename;
            tempPath = join(destDir, `${randomUUID()}-input`);
            const writeStream = createWriteStream(tempPath);

            let limitExceeded = false;
            file.on('limit', () => {
                limitExceeded = true;
                writeStream.destroy();
                file.resume(); // drain remaining bytes so the client's request completes cleanly
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
                .catch(() => {
                    // A destroyed writeStream from the size-limit branch also lands here via pipeline's rejection.
                    fail(new UploadTooLargeError(`File exceeds plan limit of ${fileSizeLimit} bytes`));
                });
        });

        bb.on('error', (err) => fail(err as Error));
        bb.on('filesLimit', () => fail(new Error('Only one file allowed per upload')));
        bb.on('close', () => fail(new InvalidMediaError('No file found in upload')));

        req.on('error', (err) => fail(err));
        req.pipe(bb);
    });
}
