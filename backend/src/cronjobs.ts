import cron from 'node-cron'
import { Audio } from './db/models/Audio'
import AudioRepository from './db/MongoDB/AudioRepository'
import { User } from './db/models/User'
import { UserRepository } from './db/MongoDB/UserRepository'
import { payments, s3 } from '.'
import SubscriptionRepository from './db/MongoDB/SubscriptionRepository'
import { getLogger, runWithLogger } from './observability/requestLoggerContext'
import { Subscription } from './db/models/Subscription'
import { WithId } from 'mongodb'
import { deleteFromS3 } from './lib/file_management'
import AppSettingsRepository from './db/MongoDB/AppSettingsRepository'
import UsageRepository from './db/MongoDB/UsageRepository'
import { MongoDB } from './db/MongoDB/mongodb'
import { meiliAlbum, meiliAudio, meiliPlaylistAudio } from './db/meilisearch'
import AlbumRepository from './db/MongoDB/AlbumRepository'
import ArtistAlbumAudioRepository from './db/MongoDB/ArtistAlbumAudioRepository'

export const runCronjobs = async () => {
    const cronLog = getLogger()

    cronLog.info('scheduling jobs...')

    // Schedule: every 12 hours
    // "0 0 */12 * * *" => second, minute, hour, day, month, weekday
    cron.schedule('0 0 */12 * * *', async () => {
        const log = getLogger().child({ module: 'cronjob', job: 'delete temporary contents' });

        try {
            log.info('Sending delete requests for temporary contents...');

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

            log.info('Deleting dangling audio files...');
            const audioRepo = new AudioRepository()
            const deleteAudio = async (audio: WithId<Audio>) => {
                log.info(`Deleting audio id: ${audio._id?.toString()} ...`);

                const audioId = audio._id?.toString()

                const audioRepository = new AudioRepository();

                const meiliAudioDeleteResult = await runWithLogger(log, () => meiliAudio.delete(audioId));
                log.debug({ meiliAudioDeleteResult });
                if (meiliAudioDeleteResult.status !== 'succeeded') {
                    log.error({ meiliAudioDeleteResult }, 'Failed to delete audio record from Meilisearch audio collection');
                    return
                }
                log.info('Deleted audio record in Meilisearch audio collection')

                const meiliPlaylistAudioDeleteResult = await runWithLogger(log, () => meiliPlaylistAudio.deleteBy({ audioId }));
                log.debug({ meiliPlaylistAudioDeleteResult });
                if (meiliPlaylistAudioDeleteResult.status !== 'succeeded') {
                    log.error({ meiliPlaylistAudioDeleteResult }, 'Failed to delete audio record from Meilisearch playlist audio collection');
                    return
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
                    return
                }

                const rr = await runWithLogger(log, () => audioRepository.delete(audioId));
                log.debug({ deleteResult: rr });
                if (!rr.acknowledged) {
                    log.error({ deleteResult: rr }, 'Failed to delete audio record from DB');
                    return
                }
                log.info('Deleted audio record in DB')
            }

            const handleAudioRemove = async (audio: WithId<Audio>) => {
                if (audio.bucketKey)
                    await deleteFromS3(audio.bucketKey)
                if (audio.webBucketKey)
                    await deleteFromS3(audio.webBucketKey)
                if (audio.coverArtKey)
                    await deleteFromS3(audio.coverArtKey)
                await deleteAudio(audio)
            }
            let audioCursor = audioRepo.getDeletablesFromCursor(from)
            for await (const audio of audioCursor)
                handleAudioRemove(audio)

            await Promise.allSettled(userDeleteAvatarPromises)

            log.info('Deleting dangling album avatars...');
            const albumRepo = new AlbumRepository()
            const artistAlbumAudioRepository = new ArtistAlbumAudioRepository()

            const albumDeleteAvatarPromises = []
            let albumCursor = albumRepo.getDeletablesAvatarFromCursor(from)
            for await (const album of albumCursor)
                albumDeleteAvatarPromises.push((async () => {
                    try {
                        log.info(`Deleting user id: ${album._id!.toString()} ...`);

                        const albumId = album._id!.toString()

                        log.info({ album })

                        if (album.avatarKey)
                            await deleteFromS3(album.avatarKey)

                        if (album.deletionQueued === true) {
                            const meiliAlbumDeleteResult = await runWithLogger(log, () => meiliAlbum.delete(albumId))
                            log.debug({ meiliAlbumDeleteResult })
                            if (meiliAlbumDeleteResult.status !== 'succeeded') {
                                log.error({ meiliAlbumDeleteResult }, 'Failed to delete album record from Meilisearch album collection');
                                return
                            }

                            let audios: WithId<Audio>[] = [], skip = 0
                            do {
                                audios = await runWithLogger(log, () => artistAlbumAudioRepository.getManyAudioByAlbumName(album.name, skip, 10))
                                const promises = []
                                for (const audio of audios) {
                                    log.debug({ audio })
                                    promises.push(deleteAudio(audio))
                                }

                                skip += audios.length
                            } while (audios.length !== 0);

                            const deleteResult = await runWithLogger(log, () => albumRepo.delete(albumId));
                            log.info({ deleteResult });
                            if (!deleteResult) {
                                log.error({ deleteResult }, 'Failed to delete album record from DB');
                                return
                            }
                            log.info('Deleted album avatar in DB')

                            return
                        }

                        const updateResult = await runWithLogger(log, () => albumRepo.unsafeUpdate(album._id!.toString(), { deletionQueued: false, avatarKey: undefined, temporaryAvatar: false }));
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

            log.info('done');
        } catch (err) {
            log.error({ err }, 'job threw error, while trying to delete temporary contents')
        }
    })

    cronLog.info('Cron jobs scheduled')
}