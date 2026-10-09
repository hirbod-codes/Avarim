import { GetObjectCommand } from "@aws-sdk/client-s3";
import AudioRepository from "../../db/MongoDB/AudioRepository";
import { getLogger, runWithLogger } from "../../observability/requestLoggerContext";
import { s3 } from "../..";
import { Request, Response } from "express";
import { BUCKET_NAME } from "../../configs";
import { Readable } from "stream";
import { handleError } from "../../lib";

export async function streamAudioFile(audioId: string, userId: string, req: Request, res: Response, isWeb: boolean, download: boolean, log = getLogger().child({ step: 'streamAudioFile' })) {
    const audioRepository = new AudioRepository();

    const audio = await runWithLogger(log, () => audioRepository.get(audioId, userId!));
    log.debug({ audio });
    log.info('Checked audio ownership');
    if (!audio || !audio.contentType || (isWeb && !audio.webBucketKey) || (!isWeb && !audio.bucketKey)) {
        log.info('Rejected audio file request: audio not found or missing expected bucket key');
        return res.status(404).json({ status: 'error', message: 'Audio not found' });
    }

    const range = req.headers.range;
    const key = isWeb ? audio.webBucketKey : audio.bucketKey;
    log.debug({ key, range, download });

    const result = await runWithLogger(log, () => s3.send(new GetObjectCommand({
        Bucket: BUCKET_NAME,
        Key: key,
        Range: range,
        ResponseContentDisposition: download ? `attachment; filename="${audio._id!.toString()}.${audio.contentType!.extension}"` : undefined,
    })));
    log.debug({ contentLength: result.ContentLength, contentRange: result.ContentRange });
    log.info('Fetched object from storage');

    if (result.Body === undefined || result.Body === null) {
        log.warn('Storage object has no body');
        return res.status(404).json({ status: 'error', message: 'Audio not found' });
    }

    const body = result.Body as Readable;
    body.on('error', (err) => {
        log.error({ err, key }, 'S3 stream error while serving audio file');
        if (!res.headersSent) return runWithLogger(log, () => handleError(res, err));
        res.destroy();
    });

    res.status(range ? 206 : 200);
    res.setHeader('Content-Type', isWeb ? 'audio/m4a' : (audio.contentType?.mimeType ?? 'audio/m4a'));
    res.setHeader('Accept-Ranges', 'bytes');
    if (result.ContentRange) res.setHeader('Content-Range', result.ContentRange);
    if (result.ContentLength) res.setHeader('Content-Length', result.ContentLength);

    log.info('Streaming audio file to client');
    body.pipe(res);
}
