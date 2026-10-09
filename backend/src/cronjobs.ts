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

            const userRepo = new UserRepository()

            const audioRepo = new AudioRepository()

            const deleteAudio = async (audio: Audio & { _id: any }) => {
                log.info(`Deleting audio id: ${audio._id?.toString()} ...`);

                let db: MongoDB | undefined = undefined
                try {
                    log.info({ audio })

                    db = MongoDB.getDbInstance()
                    const session = await db.startTransaction()

                    const audioRepository = new AudioRepository();
                    audioRepository.setTransactionSession(session)

                    // if (audio.totalFilesBytes) {
                    //     if (!(await runWithLogger(log, () => rollbackStorageQuota(audio.userId.toString(), audio.totalFilesBytes!)))) {
                    //         log.info(`failed to decrease user storage bytes usage by ${audio.totalFilesBytes}`)
                    //         await db.abortTransaction()
                    //         return
                    //     }
                    //     log.info(`decreased user storage bytes usage by ${audio.totalFilesBytes}`)
                    // }

                    const rr = await runWithLogger(log, () => audioRepository.delete(audio._id!.toString()));
                    log.info({ deleteResult: rr });
                    if (!rr.acknowledged) {
                        log.error({ deleteResult: rr }, 'Failed to delete audio record from DB');
                        await db.abortTransaction()
                        return
                    }
                    log.info('Deleted audio record in DB')

                    await db.commitTransaction()
                    log.info('done')
                } catch (err) {
                    log.error({ err }, 'caught error in deleteAudio function')
                    await db?.abortTransaction()
                }
            }

            const deleteAvatar = async (user: User) => {
                log.info(`Deleting user id: ${user._id?.toString()} ...`);

                let db: MongoDB | undefined = undefined
                try {
                    log.info({ user })

                    db = MongoDB.getDbInstance()
                    const session = await db.startTransaction()

                    const userRepository = new UserRepository();
                    userRepository.setTransactionSession(session)

                    // if (user.totalFilesBytes) {
                    //     if (!(await runWithLogger(log, () => rollbackStorageQuota(user._id!.toString(), user.totalFilesBytes!)))) {
                    //         log.info(`failed to decrease user storage bytes usage by ${user.totalFilesBytes}`)
                    //         await db.abortTransaction()
                    //         return
                    //     }
                    //     log.info(`decreased user storage bytes usage by ${user.totalFilesBytes}`)
                    // }

                    const rr = await runWithLogger(log, () => userRepository.unsafeUpdate(user._id!.toString(), { avatarDeletionQueued: false, avatarKey: undefined, temporaryAvatar: false }));
                    log.info({ deleteResult: rr });
                    if (!rr) {
                        log.error({ deleteResult: rr }, 'Failed to delete user record from DB');
                        await db.abortTransaction()
                        return
                    }
                    log.info('Deleted user record in DB')

                    await db.commitTransaction()
                    log.info('done')
                } catch (err) {
                    log.error({ err }, 'caught error in deleteAudio function')
                    await db?.abortTransaction()
                }
            }

            log.info('Deleting dangling avatar files...');
            const handleAvatarRemove = async (user: User) => {
                if (user.avatarKey)
                    await deleteFromS3(user.avatarKey)
                await deleteAvatar(user)
            }
            let userCursor = userRepo.getTemporaryAvatarFromCursor(from)
            for await (const user of userCursor)
                handleAvatarRemove(user)

            log.info('Deleting dangling audio files...');
            const handleAudioRemove = async (audio: Audio & { _id: any }) => {
                if (audio.bucketKey)
                    await deleteFromS3(audio.bucketKey)
                if (audio.webBucketKey)
                    await deleteFromS3(audio.webBucketKey)
                if (audio.coverArtKey)
                    await deleteFromS3(audio.coverArtKey)
                await deleteAudio(audio)
            }
            let audioCursor = audioRepo.getTemporariesFromCursor(from)
            for await (const audio of audioCursor)
                handleAudioRemove(audio)

            log.info('done');
        } catch (err) {
            log.error({ err }, 'job threw error, while trying to delete temporary contents')
        }
    })

    // Schedule: every 4 hours
    // "0 0 */4 * * *" => second, minute, hour, day, month, weekday
    cron.schedule('0 0 */4 * * *', async () => {
        const log = getLogger().child({ module: 'cronjob', job: 'delete dangling subscriptions' });

        try {
            log.info('deleting dangling subscriptions...');

            const subscriptionRepository = new SubscriptionRepository()

            log.info('cancelling subscriptions with status \'paymentNotCompleted\'...');
            const subscriptionUpdateResult = await subscriptionRepository.cancelByStatus(['paymentNotCompleted'], 4)
            log.info({ subscriptionUpdateResult })
            if (!subscriptionUpdateResult.acknowledged) {
                log.error({ subscriptionUpdateResult }, 'job failed to clean dangling subscriptions')
                return
            }

            const cancel = async (subscription: WithId<Subscription>) => {
                log.info('updating subscription status to \'canceled\'')
                let updateResult = await runWithLogger(log, () => subscriptionRepository.unsafeUpdate(subscription._id!.toString(), subscription.userId, { status: 'canceled' }))
                log.debug({ updateResult })
                if (!updateResult.acknowledged || updateResult.matchedCount !== 1) {
                    log.info('failed to cancel user\'s subscription')
                    // cronjob will clean up the subscription
                }
            }

            const markAsInDebt = async (subscription: WithId<Subscription>) => {
                log.info('updating subscription status to \'inDebtToUser\'')
                let updateResult = await runWithLogger(log, () => subscriptionRepository.unsafeUpdate(subscription._id!.toString(), subscription.userId, { status: 'inDebtToUser' }))
                log.debug({ updateResult })
                if (!updateResult.acknowledged || updateResult.matchedCount !== 1) {
                    log.info('failed to cancel user\'s subscription')
                    // cronjob will clean up the subscription
                }
            }

            const handleSubscription = async (subscription: WithId<Subscription>): Promise<boolean> => {
                const { payment: { amount, method: paymentMethod, authority }, userId } = subscription
                const payment: IPay = payments[paymentMethod]!

                log.info('verifying payment...')
                const result = await runWithLogger(log, () => payment.verify({ authority, amount }))
                log.debug({ result })
                if (result == false) {
                    log.info('this subscription is already rolled back automatically by the third party payment provider, cancelling this dangling subscription')
                    await cancel(subscription)
                    return false
                }
                const { refId, cardNumber, cardNumberHash } = result

                log.info('remove user\'s valid subscriptions')
                const deleteResult = await runWithLogger(log, () => subscriptionRepository.deleteByStatusForUser(userId, ['active', 'trial']))
                if (!deleteResult.acknowledged) {
                    log.warn('job failed to delete active subscriptions of user, since the transaction is not reversible anymore, the subscription is marked as in debt')
                    await markAsInDebt(subscription)

                    return false
                }

                log.info('updating subscription status to \'active\'')
                const updateResult = await runWithLogger(log, () => subscriptionRepository.unsafeUpdate(subscription._id!.toString(), userId, { status: 'active', payment: { ...subscription.payment, verifiedAt: Date.now(), refId, cardNumber, cardNumberHash } }))
                log.debug({ updateResult })
                if (!updateResult.acknowledged || updateResult.matchedCount !== 1) {
                    log.info('job failed to activate user\' subscription, since the transaction is not reversible anymore, the subscription is marked as in debt')
                    log.info('failed to activate user\'s subscription')
                    // rollback payment
                    await markAsInDebt(subscription)

                    return false
                }

                return true
            }

            const subscriptions = await subscriptionRepository.getCreatedBeforeByStatusCursor(['paymentNotVerified'], Date.now() - (4 * 60 * 60 * 1000))

            const promises: Promise<boolean>[] = []
            for await (const subscription of subscriptions) {
                log.info({ subscription }, 'handling subscription')
                promises.push(handleSubscription(subscription))
            }

            const results = await Promise.allSettled<boolean>(promises)
            log.info({ fulfilledCount: results.map(m => m.status === 'fulfilled' ? m.value === true : false).filter((f) => f === true).length, rejectedCount: results.filter((f) => f.status === 'rejected').length }, 'handled all the subscriptions')

            log.info('done');
        } catch (err) {
            log.error({ err }, 'job threw error, while trying to clean dangling subscriptions')
        }
    })

    // Schedule: every 12 hours
    // "0 0 */12 * * *" => second, minute, hour, day, month, weekday
    cron.schedule('0 0 */12 * * *', async () => {
        const log = getLogger().child({ module: 'cronjob', job: 'delete unused storage space' });

        try {
            log.info('delete unused storage space...');

            const appSettingsRepository = new AppSettingsRepository()
            const userRepository = new UserRepository()
            const usageRepository = new UsageRepository()
            const subscriptionRepository = new SubscriptionRepository()

            log.info('fetching admins');
            const admins = await runWithLogger(log, () => userRepository.getAdmins())

            const handleSubscription = async (subscription: WithId<Subscription>): Promise<boolean> => {
                const userId = subscription.userId
                if (admins && admins.map(m => m._id.toString()).includes(userId)) {
                    log.info('user is admin, returning');
                    return true
                }

                const usage = await runWithLogger(log, () => (usageRepository.getByUserId(userId)))
                if (!usage || usage.storageBytes === 0) {
                    log.info('storage usage is 0, returning');
                    return true
                }

                const results = await Promise.allSettled([
                    runWithLogger(log, () => deleteFromS3(`image/${userId}`)),
                    runWithLogger(log, () => deleteFromS3(`audio/${userId}`)),
                    runWithLogger(log, () => deleteFromS3(`audio/cover_art/${userId}`)),
                    runWithLogger(log, () => deleteFromS3(`video/${userId}`)),
                    runWithLogger(log, () => deleteFromS3(`video/thumbnail/${userId}`)),
                    runWithLogger(log, () => deleteFromS3(`user/avatar/${userId}`)),
                ]);
                const rejected = results.filter((r): r is PromiseRejectedResult => r.status === 'rejected');

                log.info(
                    {
                        fulfilledCount: results.length - rejected.length,
                        rejectedCount: rejected.length,
                        ...(rejected.length > 0 && { errors: rejected.map(r => r.reason instanceof Error ? r.reason.message : r.reason) }),
                    },
                    'handled all the subscriptions'
                );

                if (rejected.length === 0) {
                    log.info('all data in s3 storage deleted successfully');
                    const result = await runWithLogger(log, () => (usageRepository.deleteByUserId(userId)))
                    if (!result.acknowledged) {
                        log.info('failed to delete usage record in db');
                        return false
                    }
                }

                return true
            }

            const appSettings = await runWithLogger(log, () => (appSettingsRepository.getByKey('expiration')))
            let deleteS3StorageAfterExpiredDaysCount: number
            if (appSettings)
                deleteS3StorageAfterExpiredDaysCount = appSettings.deleteS3StorageAfterExpiredDaysCount ?? 15
            else deleteS3StorageAfterExpiredDaysCount = 15

            const subscriptions = await runWithLogger(log, () => subscriptionRepository.getUnhandledExpiredBeforeCursor(Date.now() - (deleteS3StorageAfterExpiredDaysCount * 24 * 60 * 60 * 1000)))

            const promises: Promise<boolean>[] = []
            for await (const subscription of subscriptions) {
                log.info({ subscription }, 'handling subscription')
                promises.push(handleSubscription(subscription))
            }
            const results = await Promise.allSettled<boolean>(promises)
            log.info({ fulfilledCount: results.map(m => m.status === 'fulfilled' ? m.value === true : false).filter((f) => f === true).length, rejectedCount: results.filter((f) => f.status === 'rejected').length }, 'handled all the subscriptions')

            log.info('done');
        } catch (err) {
            log.error({ err }, 'job threw error, while trying to delete unused storage space')
        }
    })

    cronLog.info('Cron jobs scheduled')
}