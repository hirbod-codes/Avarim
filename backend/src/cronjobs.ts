import cron from 'node-cron'
import { Audio } from './db/models/Audio'
import AudioRepository from './db/MongoDB/AudioRepository'
import { UserRepository } from './db/MongoDB/UserRepository'
import { getLogger, runWithLogger } from './observability/requestLoggerContext'
import { WithId } from 'mongodb'
import { deleteFromS3 } from './lib/file_management'
import { meiliAlbum, meiliAudio, meiliPlaylistAudio } from './db/meilisearch'
import AlbumRepository from './db/MongoDB/AlbumRepository'
import ArtistAlbumAudioRepository from './db/MongoDB/ArtistAlbumAudioRepository'
import { Controller } from './routes/contorller'
import ArtistRepository from './db/MongoDB/ArtistRepository'
import { ArtistUpdate } from './db/models/Artist'
import { AlbumUpdate } from './db/models/Album'

export const runCronjobs = async () => {
    const cronLog = getLogger()

    cronLog.info('scheduling jobs...')

    // Schedule: every 12 hours
    // Delete temporary or deletion queued contents
    // "0 0 */12 * * *" => second, minute, hour, day, month, weekday
    cron.schedule('0 0 */12 * * *', async () => {
        const log = getLogger().child({ module: 'cronjob', job: 'delete dangling, temporary or deletion queued contents' });

        try {
            log.info('deleting dangling, temporary or deletion queued contents...');

            const from = Date.now() - (14 * 60 * 60 * 1000)

            log.info('Deleting dangling user avatars...');
            const userRepo = new UserRepository()

            const userDeleteAvatarPromises = []
            let userCursor = userRepo.getDeletablesAvatarFromCursor(from)
            for await (const user of userCursor)
                userDeleteAvatarPromises.push((async () => {
                    log.info(`Deleting user id: ${user._id?.toString()} ...`);

                    try {
                        log.info({ user })

                        if (user.avatarKey)
                            await deleteFromS3(user.avatarKey)

                        const rr = await runWithLogger(log, () => userRepo.unsafeUpdate(user._id!.toString(), { avatarDeletionQueued: false, avatarKey: undefined, temporaryAvatar: false }));
                        log.info({ deleteResult: rr });
                        if (!rr) {
                            log.error({ deleteResult: rr }, 'Failed to delete user record from DB');
                            return
                        }
                        log.info('Deleted user record in DB')

                        log.info('done')
                    } catch (err) {
                        log.error({ err }, 'caught error in deleteAudio function')
                    }
                })())

            await Promise.allSettled(userDeleteAvatarPromises)

            log.info('Deleting dangling audio files...');
            const audioRepo = new AudioRepository()

            const audioDeletePromises = []
            let audioCursor = audioRepo.getDeletablesFromCursor(from)
            for await (const audio of audioCursor)
                audioDeletePromises.push((async () => {
                    if (audio.temporaryAvatar === true && audio.coverArtKey)
                        await deleteFromS3(audio.coverArtKey)
                    if (audio.deletionQueued === true || audio.temporary === true)
                        await new Controller().deleteAudio(audio)
                })())

            await Promise.allSettled(audioDeletePromises)

            log.info('Deleting dangling album avatars...');
            const albumRepo = new AlbumRepository()

            const albumDeleteAvatarPromises = []
            let albumCursor = albumRepo.getDeletablesAvatarFromCursor(from)
            for await (const album of albumCursor)
                albumDeleteAvatarPromises.push((async () => {
                    try {
                        log.info(`Deleting user id: ${album._id!.toString()} ...`);

                        log.info({ album })

                        if (album.temporaryAvatar === true && album.avatarKey)
                            await deleteFromS3(album.avatarKey)

                        if (album.deletionQueued === true) {
                            await new Controller().deleteAlbum(album)
                            return
                        }

                        const albumId = album._id!.toString()

                        const update: AlbumUpdate = { deletionQueued: false, temporaryAvatar: false }
                        if (album.temporaryAvatar === true)
                            update.avatarKey = undefined

                        const updateResult = await runWithLogger(log, () => albumRepo.unsafeUpdate(albumId, update));
                        log.info({ updateResult });
                        if (!updateResult) {
                            log.error({ updateResult }, 'Failed to delete album record from DB');
                            return
                        }
                        log.info('Deleted album avatar in DB')
                    } catch (err) {
                        log.error({ err }, 'caught error in cleanAlbum function')
                    }
                })())

            await Promise.allSettled(albumDeleteAvatarPromises)

            log.info('Deleting dangling album avatars...');
            const artistRepo = new ArtistRepository()

            const artistDeleteAvatarPromises = []
            let artistCursor = artistRepo.getDeletablesAvatarFromCursor(from)
            for await (const artist of artistCursor)
                artistDeleteAvatarPromises.push((async () => {
                    try {
                        log.info(`Deleting user id: ${artist._id!.toString()} ...`);

                        log.info({ artist })

                        if (artist.deletionQueued === true) {
                            await new Controller().deleteArtist(artist)
                            return
                        }

                        if (artist.temporaryAvatar && artist.avatarKey)
                            await deleteFromS3(artist.avatarKey)

                        if (artist.temporaryBanner && artist.bannerKey)
                            await deleteFromS3(artist.bannerKey)

                        const artistId = artist._id!.toString()

                        const update: ArtistUpdate = { deletionQueued: false, temporaryAvatar: false, temporaryBanner: false }
                        if (artist.temporaryAvatar)
                            update.avatarKey = undefined
                        if (artist.temporaryBanner)
                            update.bannerKey = undefined

                        const updateResult = await runWithLogger(log, () => artistRepo.unsafeUpdate(artistId, update));
                        log.info({ updateResult });
                        if (!updateResult) {
                            log.error({ updateResult }, 'Failed to delete artist record from DB');
                            return
                        }
                        log.info('Deleted artist avatar in DB')
                    } catch (err) {
                        log.error({ err }, 'caught error in cleanAlbum function')
                    }
                })())

            await Promise.allSettled(artistDeleteAvatarPromises)

            log.info('Deleting dangling albums...');
            const artistAlbumAudioRepository = new ArtistAlbumAudioRepository()

            const danglingAlbumsPromises = []
            let danglingAlbumCursor = albumRepo.getFromCursor(from)
            for await (const danglingAlbum of danglingAlbumCursor)
                danglingAlbumsPromises.push((async () => {
                    const artistAlbumAlbumDeleteResult = await runWithLogger(log, () => artistAlbumAudioRepository.getBy({ albumName: danglingAlbum.name }))
                    if (artistAlbumAlbumDeleteResult.length === 0) {
                        await new Controller().deleteAlbum(danglingAlbum)
                    }
                })())

            await Promise.allSettled(danglingAlbumsPromises)

            log.info('Deleting dangling artists...');

            const danglingArtistsPromises = []
            let danglingArtistCursor = artistRepo.getFromCursor(from)
            for await (const danglingArtist of danglingArtistCursor)
                danglingArtistsPromises.push((async () => {
                    const artistAlbumAlbumDeleteResult = await runWithLogger(log, () => artistAlbumAudioRepository.getBy({ artistName: danglingArtist.name }))
                    if (artistAlbumAlbumDeleteResult.length === 0) {
                        await new Controller().deleteArtist(danglingArtist)
                    }
                })())

            await Promise.allSettled(danglingArtistsPromises)

            log.info('done');
        } catch (err) {
            log.error({ err }, 'job threw error, while trying to delete temporary contents')
        }
    })

    cronLog.info('Cron jobs scheduled')
}