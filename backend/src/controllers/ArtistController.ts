import { WithId } from "../db/common_schemas";
import { meiliArtist } from "../db/meilisearch";
import { Artist } from "../db/models/Artist";
import ArtistRepository from "../db/MongoDB/ArtistRepository";
import ArtistAlbumAudioRepository from "../db/MongoDB/ArtistAlbumAudioRepository";
import { deleteFromS3 } from "../lib/file_management";
import { getLogger, runWithLogger } from "../observability/requestLoggerContext";

class ArtistNotFoundError extends Error { }
class ArtistDeletionError extends Error { }
class ArtistUpdateError extends Error { }
class MeiliArtistDeleteError extends Error { }
class ArtistAlbumAudioDeleteError extends Error { }

class S3DeletionError extends Error { }

export class ArtistController {
    static ARTIST_TITLE_SEPARATOR = '__ARTIST_TITLE_SEPARATOR__'

    /**
     * if doesn't exist
     * create artist in db
     * create artist in meilisearch
     */
    async create(name: string, artistRepository?: ArtistRepository): Promise<string> {
        let log = getLogger().child({ class: 'ArtistController', method: 'create' });

        artistRepository ??= new ArtistRepository()

        log.info('creating the artist')

        const artist = await runWithLogger(log, () => artistRepository.getByName(name))
        log.debug({ artist })
        if (!artist) {
            const createResult = await runWithLogger(log, () => artistRepository.insert({ name }))
            log.debug({ createResult })
            if (!createResult.acknowledged) {
                log.warn('Failed to create artist')
                throw new Error('Failed to create artist')
            }

            log.info('create meilisearch artist')

            const meiliResult = await runWithLogger(log, () => meiliArtist.create({ _id: createResult.insertedId.toString(), name }))
            log.debug({ meiliResult })
            if (meiliResult.status !== 'succeeded') {
                log.warn('Failed to create artist')
                throw new Error('Failed to create artist')
            }

            return createResult.insertedId.toString()
        }

        return artist._id.toString()
    }

    /**
     * marks(updates) artist record in db ( {name: `deletionQueued${ALBUM_TITLE_SEPARATOR}${artist.name}`, deletionQueued: true} )
     * deletes artist record in meilisearch artist collection
     * delete related artistAlbumAudio records (another cron job will handle deleting dangling audios; audios that belong to no artist)
     * deletes artist avatar in s3 storage
     * deletes artist record in db
     */
    delete(artist: WithId<Artist>, artistRepository?: ArtistRepository, artistAlbumAudioRepository?: ArtistAlbumAudioRepository): Promise<void>
    delete(artistId: string, artistRepository?: ArtistRepository, artistAlbumAudioRepository?: ArtistAlbumAudioRepository): Promise<void>
    async delete(arg: WithId<Artist> | string, artistRepository?: ArtistRepository, artistAlbumAudioRepository?: ArtistAlbumAudioRepository): Promise<void> {
        let log = getLogger().child({ class: 'ArtistController', method: 'delete' });

        log.info('deleting artist');

        artistRepository ??= new ArtistRepository();
        artistAlbumAudioRepository ??= new ArtistAlbumAudioRepository();

        let artist: WithId<Artist> = undefined!
        let artistId: string = undefined!
        if (typeof arg === 'string') {
            artist = await runWithLogger(log, () => artistRepository.get(arg));
            artistId = arg
            log.debug({ artist });
            log.info('Checked artist ownership');
            if (!artist || !artistId) {
                log.info('Rejected artist delete request: artist not found');
                throw new ArtistNotFoundError()
            }
        } else {
            artist = arg
            artistId = arg._id.toString()
        }

        const r = await runWithLogger(log, () => artistRepository.unsafeUpdate(artistId, { name: `deletionQueued${ArtistController.ARTIST_TITLE_SEPARATOR}${artist.name}`, temporaryAvatar: true, deletionQueued: true }));
        log.debug({ updateResult: r });
        if (!r.acknowledged) {
            log.error({ updateResult: r }, 'Failed to mark artist temporary before delete');
            throw new ArtistUpdateError()
        }
        log.info('Marked audio before delete');

        const meiliArtistDeleteResult = await runWithLogger(log, () => meiliArtist.delete(artistId));
        log.debug({ meiliArtistDeleteResult });
        if (meiliArtistDeleteResult.status !== 'succeeded') {
            log.error({ meiliArtistDeleteResult }, 'Failed to delete artist record from Meilisearch artist collection');
            throw new MeiliArtistDeleteError()
        }
        log.info('Deleted artist record in Meilisearch artist collection')

        // a cron job will handle dangling albums
        const artistAlbumAudioDeleteResult = await runWithLogger(log, () => artistAlbumAudioRepository.deleteBy({ artistId }))
        log.debug({ artistAlbumAudioDeleteResult })
        if (!artistAlbumAudioDeleteResult?.acknowledged) {
            log.error({ artistAlbumAudioDeleteResult }, 'Failed to delete artistAlbumAudio records from db');
            throw new ArtistAlbumAudioDeleteError()
        }

        const promises = []
        if (artist?.avatarKey) {
            log.info('Deleting artist file from storage');
            promises.push(runWithLogger(log, () => deleteFromS3(artist.avatarKey!)))
            log.debug({ key: artist.avatarKey });
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

        const rr = await runWithLogger(log, () => artistRepository.delete(artistId));
        log.debug({ deleteResult: rr });
        if (!rr.acknowledged) {
            log.error({ deleteResult: rr }, 'Failed to delete artist record from DB');
            throw new ArtistDeletionError()
        }
        log.info('Deleted artist record in DB')
    }
}