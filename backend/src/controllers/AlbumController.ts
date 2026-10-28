import { WithId } from "../db/common_schemas";
import { meiliAlbum } from "../db/meilisearch";
import { Album } from "../db/models/Album";
import AlbumRepository from "../db/MongoDB/AlbumRepository";
import ArtistAlbumAudioRepository from "../db/MongoDB/ArtistAlbumAudioRepository";
import { deleteFromS3 } from "../lib/file_management";
import { getLogger, runWithLogger } from "../observability/requestLoggerContext";

class AlbumNotFoundError extends Error { }
class AlbumDeletionError extends Error { }
class AlbumUpdateError extends Error { }
class MeiliAlbumDeleteError extends Error { }

class S3DeletionError extends Error { }

export class AlbumController {
    static ALBUM_TITLE_SEPARATOR = '__ALBUM_TITLE_SEPARATOR__'

    /**
     * create album in db
     * create album in meilisearch
     */
    async create(name: string, albumRepository?: AlbumRepository): Promise<string> {
        let log = getLogger().child({ class: 'AlbumController', method: 'createAlbum' });

        albumRepository ??= new AlbumRepository()

        log.info('creating the album')

        const dbResult = await runWithLogger(log, () => albumRepository.insert({ name }))
        log.debug({ dbResult })
        if (!dbResult.acknowledged) {
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

        return dbResult.insertedId.toString()
    }

    /**
     * marks(updates) album record in db ( {name: `deletionQueued${ALBUM_TITLE_SEPARATOR}${album.name}`, deletionQueued: true} )
     * deletes album record in meilisearch album collection
     * delete related artistAlbumAudio records (another cron job will handle deleting dangling audios; audios that belong to no album)
     * deletes album avatar in s3 storage
     * deletes album record in db
     */
    delete(album: WithId<Album>, albumRepository?: AlbumRepository, artistAlbumAudioRepository?: ArtistAlbumAudioRepository): Promise<void>
    delete(albumId: string, albumRepository?: AlbumRepository, artistAlbumAudioRepository?: ArtistAlbumAudioRepository): Promise<void>
    async delete(arg: WithId<Album> | string, albumRepository?: AlbumRepository, artistAlbumAudioRepository?: ArtistAlbumAudioRepository): Promise<void> {
        let log = getLogger().child({ class: 'controller', method: 'delete' });

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

        const r = await runWithLogger(log, () => albumRepository.unsafeUpdate(albumId, { name: `deletionQueued${AlbumController.ALBUM_TITLE_SEPARATOR}${album.name}`, temporaryAvatar: true, deletionQueued: true }));
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
}