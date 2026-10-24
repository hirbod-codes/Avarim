import { meiliAudio, meiliPlaylistAudio } from "../db/meilisearch";
import AudioRepository from "../db/MongoDB/AudioRepository";
import { deleteFromS3 } from "../lib/file_management";
import { getLogger, runWithLogger } from "../observability/requestLoggerContext";

class AudioNotFoundError extends Error { }
class AudioDeletionError extends Error { }
class MeiliAudioDeleteError extends Error { }
class MeiliPlaylistAudioDeleteError extends Error { }
class S3DeletionError extends Error { }

const AUDIO_TITLE_SEPARATOR = '__AUDIO_TITLE_SEPARATOR__'

export class controller {
    constructor() { }

    async artist(id: string) {
    }

    /**
     * marks(updates) album record in db ( {title: `deletionQueued${ALBUM_TITLE_SEPARATOR}${album.title}`, deletionQueued: true} )
     * deletes album record in meilisearch album collection
     * delete album's audios
     * deletes album avatar in s3 storage
     * deletes album record in db
     * 
     * @param id 
     */
    async album(albumId: string) {
    }

    /**
     * marks(updates) audio record in db ( {title: `deletionQueued${AUDIO_TITLE_SEPARATOR}${audio.title}`, deletionQueued: true} )
     * deletes audio record in meilisearch audio collection
     * deletes audio related records in meilisearch playlist audio collection
     * deletes audio files and cover art in s3 storage
     * deletes audio record in db
     * 
     * @param audioId 
     */
    async audio(audioId: string) {
        let log = getLogger().child({ class: 'controller', method: 'audio' });

        log.info('Audio delete request received');

        const audioRepository = new AudioRepository();

        const audio = await runWithLogger(log, () => audioRepository.get(audioId));
        log.debug({ audio });
        log.info('Checked audio ownership');
        if (!audio) {
            log.info('Rejected audio delete request: audio not found');
            throw new AudioNotFoundError()
        }

        const r = await runWithLogger(log, () => audioRepository.unsafeUpdate(audioId, { title: `deletionQueued${AUDIO_TITLE_SEPARATOR}${audio.title}`, deletionQueued: true }));
        log.debug({ updateResult: r });
        if (!r.acknowledged || r.matchedCount) {
            log.error({ updateResult: r }, 'Failed to mark audio temporary before delete');
            throw new AudioDeletionError()
        }
        log.info('Marked audio before delete');

        const meiliAudioDeleteResult = await runWithLogger(log, () => meiliAudio.delete(audioId));
        log.debug({ meiliAudioDeleteResult });
        if (meiliAudioDeleteResult.status !== 'succeeded') {
            log.error({ meiliAudioDeleteResult }, 'Failed to delete audio record from Meilisearch audio collection');
            throw new MeiliAudioDeleteError()
        }
        log.info('Deleted audio record in Meilisearch audio collection')

        const meiliPlaylistAudioDeleteResult = await runWithLogger(log, () => meiliPlaylistAudio.deleteBy({ audioId }));
        log.debug({ meiliPlaylistAudioDeleteResult });
        if (meiliPlaylistAudioDeleteResult.status !== 'succeeded') {
            log.error({ meiliPlaylistAudioDeleteResult }, 'Failed to delete audio record from Meilisearch playlist audio collection');
            throw new MeiliPlaylistAudioDeleteError()
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
            throw new S3DeletionError()
        }

        const rr = await runWithLogger(log, () => audioRepository.delete(audioId));
        log.debug({ deleteResult: rr });
        if (!rr.acknowledged) {
            log.error({ deleteResult: rr }, 'Failed to delete audio record from DB');
            throw new AudioDeletionError()
        }
        log.info('Deleted audio record in DB')

        log.info('audio deleted successfully');
    }
}