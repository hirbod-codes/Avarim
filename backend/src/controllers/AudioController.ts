import { WithId } from "../db/common_schemas";
import { meiliAudio, meiliPlaylistAudio } from "../db/meilisearch";
import { Audio } from "../db/models/Audio";
import ArtistAlbumAudioRepository from "../db/MongoDB/ArtistAlbumAudioRepository";
import AudioRepository from "../db/MongoDB/AudioRepository";
import { deleteFromS3 } from "../lib/file_management";
import { getLogger, runWithLogger } from "../observability/requestLoggerContext";

class AudioNotFoundError extends Error { }
class AudioDeletionError extends Error { }
class AudioUpdateError extends Error { }
class MeiliAudioDeleteError extends Error { }
class MeiliPlaylistAudioDeleteError extends Error { }

class S3DeletionError extends Error { }

export class AudioController {
    static AUDIO_TITLE_SEPARATOR = '__AUDIO_TITLE_SEPARATOR__'

    /**
     * marks(updates) audio record in db ( {title: `deletionQueued${AUDIO_TITLE_SEPARATOR}${audio.title}`, deletionQueued: true} )
     * deletes audio record in meilisearch audio collection
     * deletes audio related records in meilisearch playlist audio collection
     * delete related artistAlbumAudio records (another cron job will handle deleting dangling album and artists; the ones that belong to no audio)
     * deletes audio files and cover art in s3 storage
     * deletes audio record in db
     */
    delete(audio: WithId<Audio>, audioRepository?: AudioRepository, artistAlbumAudioRepository?: ArtistAlbumAudioRepository): Promise<void>
    delete(audioId: string, audioRepository?: AudioRepository, artistAlbumAudioRepository?: ArtistAlbumAudioRepository): Promise<void>
    async delete(arg: WithId<Audio> | string, audioRepository?: AudioRepository, artistAlbumAudioRepository?: ArtistAlbumAudioRepository): Promise<void> {
        let log = getLogger().child({ class: 'controller', method: 'deleteAudio' });

        log.info('deleting audio');

        audioRepository ??= new AudioRepository();
        artistAlbumAudioRepository ??= new ArtistAlbumAudioRepository();

        let audio: WithId<Audio> = undefined!
        let audioId: string = undefined!
        if (typeof arg === 'string') {
            audio = await runWithLogger(log, () => audioRepository.get(arg));
            audioId = arg
            log.debug({ audio });
            log.info('Checked audio ownership');
            if (!audio || !audioId) {
                log.info('Rejected audio delete request: audio not found');
                throw new AudioNotFoundError()
            }
        } else {
            audio = arg
            audioId = arg._id.toString()
        }

        const r = await runWithLogger(log, () => audioRepository.unsafeUpdate(audioId, { title: `deletionQueued${AudioController.AUDIO_TITLE_SEPARATOR}${audio.title}`, deletionQueued: true }));
        log.debug({ updateResult: r });
        if (!r.acknowledged) {
            log.error({ updateResult: r }, 'Failed to mark audio temporary before delete');
            throw new AudioUpdateError()
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

        const artistAlbumAudioDeleteResult = await runWithLogger(log, () => artistAlbumAudioRepository.deleteBy({ audioId }))
        log.debug({ artistAlbumAudioDeleteResult })
        if (!artistAlbumAudioDeleteResult?.acknowledged) {
            log.error({ artistAlbumAudioDeleteResult }, 'Failed to delete artistAlbumAudio records from db');
            throw new MeiliAudioDeleteError()
        }

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