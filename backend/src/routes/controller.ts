import { WithId } from "../db/common_schemas";
import { meiliAlbum, meiliArtist, meiliAudio, meiliPlaylistAudio } from "../db/meilisearch";
import { Album } from "../db/models/Album";
import { Artist } from "../db/models/Artist";
import { Audio } from "../db/models/Audio";
import AlbumRepository from "../db/MongoDB/AlbumRepository";
import ArtistAlbumAudioRepository from "../db/MongoDB/ArtistAlbumAudioRepository";
import ArtistRepository from "../db/MongoDB/ArtistRepository";
import AudioRepository from "../db/MongoDB/AudioRepository";
import { deleteFromS3 } from "../lib/file_management";
import { getLogger, runWithLogger } from "../observability/requestLoggerContext";

class AudioNotFoundError extends Error { }
class AudioDeletionError extends Error { }
class AudioUpdateError extends Error { }
class MeiliAudioDeleteError extends Error { }
class MeiliPlaylistAudioDeleteError extends Error { }

class AlbumNotFoundError extends Error { }
class AlbumDeletionError extends Error { }
class AlbumUpdateError extends Error { }
class MeiliAlbumDeleteError extends Error { }

class ArtistNotFoundError extends Error { }
class ArtistDeletionError extends Error { }
class ArtistUpdateError extends Error { }
class MeiliArtistDeleteError extends Error { }

class S3DeletionError extends Error { }

const AUDIO_TITLE_SEPARATOR = '__AUDIO_TITLE_SEPARATOR__'
const ALBUM_TITLE_SEPARATOR = '__ALBUM_TITLE_SEPARATOR__'
const ARTIST_TITLE_SEPARATOR = '__ARTIST_TITLE_SEPARATOR__'

export class Controller {
    /**
     * if doesn't exist
     * create artist in db
     * create artist in meilisearch
     */
    async createArtist(name: string, artistRepository?: ArtistRepository): Promise<string> {
        let log = getLogger().child({ class: 'controller', method: 'createArtist' });

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

            const meiliResult = await runWithLogger(log, () => meiliArtist.create({ name }))
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
     * if doesn't exist
     * create album in db
     * create album in meilisearch
     */
    async createAlbum(name: string,artistId?:string, albumRepository?: AlbumRepository): Promise<string> {
        let log = getLogger().child({ class: 'controller', method: 'createAlbum' });

        albumRepository ??= new AlbumRepository()

        log.info('creating the album')

        const album = await runWithLogger(log, () => albumRepository.getByName(name))
        log.debug({ album })
        if (!album) {
            const createResult = await runWithLogger(log, () => albumRepository.insert({artistId, name }))
            log.debug({ createResult })
            if (!createResult.acknowledged) {
                log.warn('Failed to create album')
                throw new Error('Failed to create album')
            }

            log.info('create meilisearch album')

            const meiliResult = await runWithLogger(log, () => meiliAlbum.create({ name }))
            log.debug({ meiliResult })
            if (meiliResult.status !== 'succeeded') {
                log.warn('Failed to create album')
                throw new Error('Failed to create album')
            }

            return createResult.insertedId.toString()
        }

        return album._id.toString()
    }

    /**
     * marks(updates) artist record in db ( {name: `deletionQueued${ALBUM_TITLE_SEPARATOR}${artist.name}`, deletionQueued: true} )
     * deletes artist record in meilisearch artist collection
     * delete related artistAlbumAudio records (another cron job will handle deleting dangling audios; audios that belong to no artist)
     * deletes artist avatar in s3 storage
     * deletes artist record in db
     */
    deleteArtist(artist: WithId<Artist>, artistRepository?: ArtistRepository, artistAlbumAudioRepository?: ArtistAlbumAudioRepository): Promise<void>
    deleteArtist(artistId: string, artistRepository?: ArtistRepository, artistAlbumAudioRepository?: ArtistAlbumAudioRepository): Promise<void>
    async deleteArtist(arg: WithId<Artist> | string, artistRepository?: ArtistRepository, artistAlbumAudioRepository?: ArtistAlbumAudioRepository): Promise<void> {
        let log = getLogger().child({ class: 'controller', method: 'deleteArtist' });

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

        const r = await runWithLogger(log, () => artistRepository.unsafeUpdate(artistId, { name: `deletionQueued${ARTIST_TITLE_SEPARATOR}${artist.name}`, temporaryAvatar: true, deletionQueued: true }));
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
        if (!artistAlbumAudioDeleteResult.acknowledged) {
            log.error({ artistAlbumAudioDeleteResult }, 'Failed to delete artistAlbumAudio records from db');
            throw new MeiliAlbumDeleteError()
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

    /**
     * marks(updates) album record in db ( {name: `deletionQueued${ALBUM_TITLE_SEPARATOR}${album.name}`, deletionQueued: true} )
     * deletes album record in meilisearch album collection
     * delete related artistAlbumAudio records (another cron job will handle deleting dangling audios; audios that belong to no album)
     * deletes album avatar in s3 storage
     * deletes album record in db
     */
    deleteAlbum(album: WithId<Album>, albumRepository?: AlbumRepository, artistAlbumAudioRepository?: ArtistAlbumAudioRepository): Promise<void>
    deleteAlbum(albumId: string, albumRepository?: AlbumRepository, artistAlbumAudioRepository?: ArtistAlbumAudioRepository): Promise<void>
    async deleteAlbum(arg: WithId<Album> | string, albumRepository?: AlbumRepository, artistAlbumAudioRepository?: ArtistAlbumAudioRepository): Promise<void> {
        let log = getLogger().child({ class: 'controller', method: 'deleteAlbum' });

        log.info('deleting album');

        albumRepository ??= new AlbumRepository();
        artistAlbumAudioRepository ??= new ArtistAlbumAudioRepository();

        let album: WithId<Album> = undefined!
        let albumId: string = undefined!
        if (typeof arg === 'string') {
            album = await runWithLogger(log, () => albumRepository.get(arg));
            albumId = arg
            log.debug({ album });
            log.info('Checked album ownership');
            if (!album || !albumId) {
                log.info('Rejected album delete request: album not found');
                throw new AlbumNotFoundError()
            }
        } else {
            album = arg
            albumId = arg._id.toString()
        }

        const r = await runWithLogger(log, () => albumRepository.unsafeUpdate(albumId, { name: `deletionQueued${ALBUM_TITLE_SEPARATOR}${album.name}`, temporaryAvatar: true, deletionQueued: true }));
        log.debug({ updateResult: r });
        if (!r.acknowledged) {
            log.error({ updateResult: r }, 'Failed to mark album temporary before delete');
            throw new AlbumUpdateError()
        }
        log.info('Marked audio before delete');

        const meiliAlbumDeleteResult = await runWithLogger(log, () => meiliAlbum.delete(albumId));
        log.debug({ meiliAlbumDeleteResult });
        if (meiliAlbumDeleteResult.status !== 'succeeded') {
            log.error({ meiliAlbumDeleteResult }, 'Failed to delete album record from Meilisearch album collection');
            throw new MeiliAlbumDeleteError()
        }
        log.info('Deleted album record in Meilisearch album collection')

        // a cron job will handle dangling audios
        const artistAlbumAudioDeleteResult = await runWithLogger(log, () => artistAlbumAudioRepository.deleteBy({ albumId }))
        log.debug({ artistAlbumAudioDeleteResult })
        if (!artistAlbumAudioDeleteResult.acknowledged) {
            log.error({ artistAlbumAudioDeleteResult }, 'Failed to delete artistAlbumAudio records from db');
            throw new MeiliAlbumDeleteError()
        }

        const promises = []
        if (album?.avatarKey) {
            log.info('Deleting album file from storage');
            promises.push(runWithLogger(log, () => deleteFromS3(album.avatarKey!)))
            log.debug({ key: album.avatarKey });
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

        const rr = await runWithLogger(log, () => albumRepository.delete(albumId));
        log.debug({ deleteResult: rr });
        if (!rr.acknowledged) {
            log.error({ deleteResult: rr }, 'Failed to delete album record from DB');
            throw new AlbumDeletionError()
        }
        log.info('Deleted album record in DB')
    }

    /**
     * marks(updates) audio record in db ( {title: `deletionQueued${AUDIO_TITLE_SEPARATOR}${audio.title}`, deletionQueued: true} )
     * deletes audio record in meilisearch audio collection
     * deletes audio related records in meilisearch playlist audio collection
     * delete related artistAlbumAudio records (another cron job will handle deleting dangling album and artists; the ones that belong to no audio)
     * deletes audio files and cover art in s3 storage
     * deletes audio record in db
     */
    deleteAudio(audio: WithId<Audio>, audioRepository?: AudioRepository, artistAlbumAudioRepository?: ArtistAlbumAudioRepository): Promise<void>
    deleteAudio(audioId: string, audioRepository?: AudioRepository, artistAlbumAudioRepository?: ArtistAlbumAudioRepository): Promise<void>
    async deleteAudio(arg: WithId<Audio> | string, audioRepository?: AudioRepository, artistAlbumAudioRepository?: ArtistAlbumAudioRepository): Promise<void> {
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

        const r = await runWithLogger(log, () => audioRepository.unsafeUpdate(audioId, { title: `deletionQueued${AUDIO_TITLE_SEPARATOR}${audio.title}`, deletionQueued: true }));
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
        if (!artistAlbumAudioDeleteResult.acknowledged) {
            log.error({ artistAlbumAudioDeleteResult }, 'Failed to delete artistAlbumAudio records from db');
            throw new MeiliAlbumDeleteError()
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