import { Response, Router } from "express";
import { auth } from "../../middlewares/auth";
import { getLogger, runWithLogger } from "../../observability/requestLoggerContext";
import { handleError, validate } from "../../lib";
import { Redis } from "../../db/redis";
import { postSchema, zarinpalVerifyCheckSchema, zibalVerifySchema } from "./schemas";
import SubscriptionRepository from "../../db/MongoDB/SubscriptionRepository";
import { Subscription, SubscriptionCreate, subscriptionCreateSchema } from "../../db/models/Subscription";
import { appUrl, isProduction } from "../../configs";
import { payments } from "../..";
import { randomUUID } from "node:crypto";
import { fetchBusinessPlan, resolveCurrencyAndPayment, calculatePricesForSubscriptionDue, getRedisKeyForTemporarySubscription } from "./lib";
import AppSettingsRepository from "../../db/MongoDB/AppSettingsRepository";
import { WithId } from "mongodb";

const router = Router();

const PAYMENT_CHECKPOINT_BASE = '/api/subscription'

const ZARINPAL_PAYMENT_BASE = `/zarinpal`
const ZARINPAL_PAYMENT_VERIFY = `${ZARINPAL_PAYMENT_BASE}/verify`                                       // /zarinpal/verify
const ZARINPAL_PAYMENT_VERIFY_PATH = `${PAYMENT_CHECKPOINT_BASE}${ZARINPAL_PAYMENT_VERIFY}`             // /api/subscription/zarinpal/verify
export const ZARINPAL_PAYMENT_VERIFY_CALLBACK_URL = (subscriptionId: string) => `${isProduction ? `https://${appUrl.replace('https://', '')}` : 'http://localhost:8081'}${ZARINPAL_PAYMENT_VERIFY_PATH}/${subscriptionId}`
const ZARINPAL_PAYMENT_VERIFY_CHECK = `${ZARINPAL_PAYMENT_VERIFY}/check`                                // /zarinpal/verify/check
const ZARINPAL_PAYMENT_VERIFY_CHECK_PATH = `${PAYMENT_CHECKPOINT_BASE}${ZARINPAL_PAYMENT_VERIFY_CHECK}` // /zarinpal/verify/check

const ZIBAL_PAYMENT_BASE = `/zibal`
const ZIBAL_PAYMENT_VERIFY = `${ZIBAL_PAYMENT_BASE}/verify`                                             // /zibal/verify
const ZIBAL_PAYMENT_VERIFY_PATH = `${PAYMENT_CHECKPOINT_BASE}${ZIBAL_PAYMENT_VERIFY}`                   // /api/subscription/zibal/verify
export const ZIBAL_PAYMENT_VERIFY_CALLBACK_URL = (subscriptionId: string) => `${isProduction ? `https://${appUrl.replace('https://', '')}` : 'http://localhost:8081'}${ZIBAL_PAYMENT_VERIFY_PATH}/${subscriptionId}`
const ZIBAL_PAYMENT_VERIFY_CHECK = `${ZIBAL_PAYMENT_VERIFY}/check`                                      // /zibal/verify/check
const ZIBAL_PAYMENT_VERIFY_CHECK_PATH = `${PAYMENT_CHECKPOINT_BASE}${ZIBAL_PAYMENT_VERIFY_CHECK}`       // /zibal/verify/check

router.get('/', auth, async (req, res) => {
    const log = getLogger().child({ module: 'subscription', route: `GET ${PAYMENT_CHECKPOINT_BASE}` });

    try {
        log.info('subscription fetch request received');

        const sr = new SubscriptionRepository()
        const subscription = await runWithLogger(log, () => sr.getActiveByUserId(req.user!.userId))
        if (!subscription || subscription.length !== 1) {
            log.info('subscription not found')
            return res.status(404).json({ status: 'error', error_code: 'SUBSCRIPTION_NOT_FOUND' })
        }

        log.info('sending subscription')
        return res.status(200).json({ status: 'success', data: subscription[0] })
    } catch (error) {
        runWithLogger(log, () => handleError(res, error))
    }
})

router.get(`/supported_payment_methods`, auth, async (req, res) => {
    const log = getLogger().child({ module: 'subscription', route: `GET ${PAYMENT_CHECKPOINT_BASE}/supported_payment_methods` });

    try {
        log.info('supported payment methods list request received');

        const methods = []
        if (payments.zibal)
            methods.push('zibal')

        log.info('sending payment methods')
        return res.status(200).json({ status: 'success', data: { methods } })
    } catch (error) {
        runWithLogger(log, () => handleError(res, error))
    }
})

router.get('/calculate', auth, async (req, res) => {
    const log = getLogger().child({ module: 'subscription', route: 'GET /api/subscription/calculate' });

    try {
        log.info('subscription calculation request received');

        log.debug({ query: req.query });
        let { planTitle, paymentMethod, subscriptionDueTSMS, extraStorageBytes } = await runWithLogger(log, () => validate(postSchema, req.query))
        log.debug({ planTitle, paymentMethod, subscriptionDueTSMS, extraStorageBytes });

        if (planTitle === 'free') {
            log.info("invalid plan 'free' is chosen")
            return res.status(400).json({ status: 'error', error_code: 'INVALID_PLAN' })
        }

        const nowTS = Date.now()
        if (subscriptionDueTSMS && subscriptionDueTSMS < (nowTS + (3 * 24 * 60 * 60 * 1000))) {
            log.info("invalid 'subscriptionDueTSMS' provided")
            return res.status(400).json({ status: 'error', error_code: 'INVALID_SUBSCRIPTION_DUE' })
        }

        log.info('input validated');

        const userId = req.user!.userId;
        log.debug({ userId });

        const appSettingsRepository = new AppSettingsRepository()
        const subscriptionRepository = new SubscriptionRepository()

        // ------------------------------------------------------------------------- fetch and check if any active subscription exist
        log.info('fetch and check if any active subscription exist')
        const subscriptions = await runWithLogger(log, () => subscriptionRepository.getActiveByUserId(userId))
        log.debug({ subscriptionsLength: subscriptions.length, subscriptions });
        if (subscriptions.length > 1) {
            log.warn('user has too many subscriptions active!')
            return res.status(500).json({ status: 'error' })
        }
        const tempSub: WithId<Subscription> | undefined = subscriptions[0] as any

        // ------------------------------------------------------------------------- check if the active subscription is expired
        log.info('check if the active subscription is expired')
        const expired = tempSub && tempSub.currentPeriodEnd <= nowTS
        log.debug({ expired })

        const activeSubscription: WithId<Subscription> | undefined = expired ? undefined : tempSub as any
        log.debug({ activeSubscription })

        // ------------------------------------------------------------------------- fetching business plans
        const currentPlan = activeSubscription ? await fetchBusinessPlan({ log, planTitle: activeSubscription.planTitle, res }) : undefined

        const requestedPlan = planTitle === currentPlan?.title ? currentPlan : await fetchBusinessPlan({ log, planTitle, res })
        if (!requestedPlan) {
            log.info(`There is no plan with title: ${planTitle}`)
            return res.status(400).json({ status: 'error', error_code: 'PLAN_NOT_FOUND' })
        }

        if (activeSubscription && currentPlan) {
            if (
                planTitle === activeSubscription.planTitle
                && Math.abs(activeSubscription.currentPeriodEnd - subscriptionDueTSMS) / (24 * 60 * 60 * 1000) < 3
                && Math.abs(activeSubscription.privileges.storageBytes - (requestedPlan.privileges.storageBytes + extraStorageBytes)) < (10 * 1024 * 1024 * 1024)
            ) {
                log.info('rejecting upgrade: requested options has no effective upgrade')
                return res.status(400).json({ status: 'error', error_code: 'NO_UPGRADE_OPTIONS' })
            }
        }

        // ------------------------------------------------------------------------- resolving currency and payment method and callback url
        const resolved = await resolveCurrencyAndPayment({ log, paymentMethod, res })
        if (!resolved) {
            log.info(`There is no plan with title: ${planTitle}`)
            return res.status(400).json({ status: 'error', error_code: 'PLAN_PAYMENT_METHOD' })
        }
        const [currency] = resolved

        // ------------------------------------------------------------------------- check if the currency doesn't match
        log.info("check if the currency doesn't match")
        if (activeSubscription && activeSubscription.payment.currency !== currency) {
            log.info('active plan is in another currency')
            return res.status(400).json({ status: 'error', error_code: 'ACTIVE_PLAN_CURRENCY_MISMATCH' })
        }

        // ------------------------------------------------------------------------- calculating price
        let remainingTotalPrice = 0
        if (activeSubscription && currentPlan) {
            log.debug({ durationDays: (activeSubscription.currentPeriodEnd - nowTS) / (1000 * 60 * 60 * 24), durationSeconds: (activeSubscription.currentPeriodEnd - nowTS) / 1000 }, 'remaining duration')
            const remainingDueOfActiveSubscriptionPriceCalculations = await calculatePricesForSubscriptionDue({
                log,
                plan: currentPlan,
                durationMS: activeSubscription.currentPeriodEnd - nowTS,
                currency: currency,
                privilegesStorageBytes: activeSubscription.privileges.storageBytes,
                appSettingsRepository,
                res
            })
            log.debug({ remainingDueOfActiveSubscriptionPriceCalculations })

            if (!remainingDueOfActiveSubscriptionPriceCalculations) return

            const [, , t] = remainingDueOfActiveSubscriptionPriceCalculations

            remainingTotalPrice = t
        }

        log.debug({ durationDays: (subscriptionDueTSMS - nowTS) / (1000 * 60 * 60 * 24), durationSeconds: (subscriptionDueTSMS - nowTS) / 1000 }, 'due duration')
        const dueCalculations = await calculatePricesForSubscriptionDue({
            log,
            plan: requestedPlan,
            durationMS: subscriptionDueTSMS - nowTS,
            currency: currency,
            privilegesStorageBytes: requestedPlan.privileges.storageBytes + extraStorageBytes,
            appSettingsRepository,
            res
        })
        if (!dueCalculations) return
        const [, , dueTotalPrice] = dueCalculations

        let totalPrice = dueTotalPrice - remainingTotalPrice

        // negative activeSubscription.payment.amount (our dept) is added if there is any
        if (activeSubscription && activeSubscription.payment.amount < 0)
            totalPrice += activeSubscription.payment.amount

        log.debug({ dueCalculations, totalPrice })

        if (totalPrice < 0)
            log.warn({ totalPrice }, "we are in dept to user")

        return res.status(200).json({ status: 'success', data: { totalPrice, currency } })
    } catch (error) {
        runWithLogger(log, () => handleError(res, error))
    }
});

router.post('/', auth, async (req, res) => {
    const log = getLogger().child({ module: 'subscription', route: 'POST /api/subscription' });

    try {
        log.info('subscription request received');

        log.debug({ body: req.body });
        let { planTitle, paymentMethod, subscriptionDueTSMS, extraStorageBytes } = await runWithLogger(log, () => validate(postSchema, req.body))
        log.debug({ planTitle, paymentMethod, subscriptionDueTSMS, extraStorageBytes });

        if (planTitle === 'free') {
            log.info("invalid plan 'free' is chosen")
            return res.status(400).json({ status: 'error', error_code: 'INVALID_PLAN' })
        }

        const nowTS = Date.now()
        if (subscriptionDueTSMS && subscriptionDueTSMS <= nowTS) {
            log.info("invalid 'subscriptionDueTSMS' provided")
            return res.status(400).json({ status: 'error', error_code: 'INVALID_SUBSCRIPTION_DUE' })
        }

        log.info('input validated');

        const userId = req.user!.userId;
        log.debug({ userId });

        const redis = await Redis.getClient();
        const appSettingsRepository = new AppSettingsRepository()
        const subscriptionRepository = new SubscriptionRepository()

        // ------------------------------------------------------------------------- fetch and check if any active subscription exist
        log.info('fetch and check if any active subscription exist')
        const subscriptions = await runWithLogger(log, () => subscriptionRepository.getActiveByUserId(userId))
        log.debug({ subscriptionsLength: subscriptions.length, subscriptions });
        if (subscriptions.length > 1) {
            log.warn('user has too many subscriptions active!')
            return res.status(500).json({ status: 'error' })
        }
        const tempSub: WithId<Subscription> | undefined = subscriptions[0] as any

        // ------------------------------------------------------------------------- check if the active subscription is expired
        log.info('check if the active subscription is expired')
        const expired = tempSub && tempSub.currentPeriodEnd <= nowTS
        log.debug({ expired })

        const activeSubscription: WithId<Subscription> | undefined = expired ? undefined : tempSub as any
        log.debug({ activeSubscription })

        // ------------------------------------------------------------------------- fetching business plans
        const currentPlan = activeSubscription ? await fetchBusinessPlan({ log, planTitle: activeSubscription.planTitle, res }) : undefined

        const requestedPlan = planTitle === currentPlan?.title ? currentPlan : await fetchBusinessPlan({ log, planTitle, res })
        if (!requestedPlan) {
            log.info(`There is no plan with title: ${planTitle}`)
            return res.status(400).json({ status: 'error', error_code: 'PLAN_NOT_FOUND' })
        }

        if (activeSubscription && currentPlan) {
            if (
                planTitle === activeSubscription.planTitle
                && Math.abs(activeSubscription.currentPeriodEnd - subscriptionDueTSMS) / (24 * 60 * 60 * 1000) < 3
                && Math.abs(activeSubscription.privileges.storageBytes - (requestedPlan.privileges.storageBytes + extraStorageBytes)) < (10 * 1024 * 1024 * 1024)
            ) {
                log.info('rejecting upgrade: requested options has no effective upgrade')
                return res.status(400).json({ status: 'error', error_code: 'NO_UPGRADE_OPTIONS' })
            }
        }

        // ------------------------------------------------------------------------- resolving currency and payment method and callback url
        const resolved = await resolveCurrencyAndPayment({ log, paymentMethod, res })
        if (!resolved) {
            log.info(`There is no plan with title: ${planTitle}`)
            return res.status(400).json({ status: 'error', error_code: 'PLAN_PAYMENT_METHOD' })
        }
        const [currency, payment, callback] = resolved

        // ------------------------------------------------------------------------- check if the currency doesn't match
        log.info("check if the currency doesn't match")
        if (activeSubscription && activeSubscription.payment.currency !== currency) {
            log.info('active plan is in another currency')
            return res.status(400).json({ status: 'error', error_code: 'ACTIVE_PLAN_CURRENCY_MISMATCH' })
        }

        // ------------------------------------------------------------------------- calculating price
        let remainingTotalPrice = 0
        if (activeSubscription && currentPlan) {
            const remainingDueOfActiveSubscriptionPriceCalculations = await calculatePricesForSubscriptionDue({
                log,
                plan: currentPlan,
                durationMS: activeSubscription.currentPeriodEnd - nowTS,
                currency: currency,
                privilegesStorageBytes: activeSubscription.privileges.storageBytes,
                appSettingsRepository,
                res
            })
            log.debug({ remainingDueOfActiveSubscriptionPriceCalculations })

            if (!remainingDueOfActiveSubscriptionPriceCalculations) return

            const [, , t] = remainingDueOfActiveSubscriptionPriceCalculations

            remainingTotalPrice = t
        }

        const dueCalculations = await calculatePricesForSubscriptionDue({
            log,
            plan: requestedPlan,
            durationMS: subscriptionDueTSMS - nowTS,
            currency: currency,
            privilegesStorageBytes: requestedPlan.privileges.storageBytes + extraStorageBytes,
            appSettingsRepository,
            res
        })
        if (!dueCalculations) return
        const [, , dueTotalPrice] = dueCalculations

        let totalPrice = dueTotalPrice - remainingTotalPrice

        // negative activeSubscription.payment.amount (our dept) is added if there is any
        if (activeSubscription && activeSubscription.payment.amount < 0)
            totalPrice += activeSubscription.payment.amount

        log.debug({ dueCalculations, totalPrice })

        if (totalPrice < 0)
            log.warn({ totalPrice }, "we are in dept to user")

        // ------------------------------------------------------------------------- deleting old subscriptions with 'paymentNotCompleted' status
        log.info("deleting old subscriptions with 'paymentNotCompleted' status")
        const deleteResult = await runWithLogger(log, () => subscriptionRepository.deleteDanglingStatusForUser(userId))
        log.debug({ deleteResult })

        // ------------------------------------------------------------------------- creating temporary subscription with status 'paymentNotCompleted'
        log.info("creating temporary subscription with status 'paymentNotCompleted'")
        // Using activeSubscription in order to preserve storage quota upgrades
        const subscriptionCreate: SubscriptionCreate = subscriptionCreateSchema.cast({
            userId,
            status: 'paymentNotCompleted',
            planTitle,
            currentPeriodEnd: subscriptionDueTSMS,
            privileges: requestedPlan.privileges,
            payment: {
                amount: totalPrice,
                currency,
                method: paymentMethod
            }
        } as SubscriptionCreate);
        subscriptionCreate.privileges.storageBytes = requestedPlan.privileges.storageBytes + extraStorageBytes

        if (totalPrice <= 0) subscriptionCreate.status = 'active'

        log.info({ ...subscriptionCreate, ...({ expirationDate: new Date(subscriptionDueTSMS).toUTCString() }) }, "storing user's subscription")
        const insertResult = await runWithLogger(log, () => subscriptionRepository.insert(subscriptionCreate))
        log.debug({ insertResult })
        if (!insertResult.acknowledged || !insertResult.insertedId) {
            log.info('failed to store user\'s subscription')
            return res.status(500).json({ status: 'error', message: 'subscription process failed.' })
        }
        if (totalPrice <= 0) {
            log.info("since calculated 'totalPrice' is equal to or less than zero, this subscription is considered free and therefor it is created with 'active' status")
            return res.status(201).json({ status: 'success' })
        }
        const newSubscription: WithId<Subscription> = { ...subscriptionCreate, _id: insertResult.insertedId }

        // ------------------------------------------------------------------------- storing the created subscription in session
        log.info('storing the created subscription in session')
        const redisKey = getRedisKeyForTemporarySubscription(newSubscription._id!.toString())
        await redis.set(redisKey, JSON.stringify(newSubscription), 'EX', 1500)

        // ------------------------------------------------------------------------- requesting payment
        log.info('requesting payment')
        const result = await runWithLogger(log, () => payment.request(totalPrice, callback(newSubscription._id!.toString())))
        log.debug({ result })
        if (result == false) {
            log.error('system failed to request a payment')
            return res.status(500).json({ status: 'error', message: 'INTERNAL_ERROR' })
        }

        return res.status(200).json({ status: 'success', data: result });
    } catch (error) {
        runWithLogger(log, () => handleError(res, error))
    }
});

router.get(`${ZIBAL_PAYMENT_VERIFY_CHECK}`, async (req, res) => {
    const log = getLogger().child({ module: 'subscription', route: `GET ${ZIBAL_PAYMENT_VERIFY_CHECK_PATH}` });

    try {
        log.info('zibal subscription verification check request received');

        log.debug({ query: req.query });
        const { uuid } = await runWithLogger(log, () => validate(zarinpalVerifyCheckSchema, req.query))
        log.debug({ uuid });
        log.info('input validated');

        const redis = await Redis.getClient()
        const redisKey = `payment_results:${uuid}`
        const exists = (await redis.exists(redisKey)) === 1
        log.debug({ exists });
        if (!exists) {
            log.info('payment uuid not found')
            return res.status(400).json({ status: 'error', error_code: 'UUID_NOT_FOUND' })
        }

        log.info('payment uuid found')
        return res.status(204).json({ status: 'success' })
    } catch (error) {
        runWithLogger(log, () => handleError(res, error))
    }
})

router.get(`${ZIBAL_PAYMENT_VERIFY}/:subscriptionId`, async (req, res) => {
    const log = getLogger().child({ module: 'subscription', route: `GET ${ZIBAL_PAYMENT_VERIFY_PATH}/:subscriptionId` });

    try {
        log.info('zibal subscription verification request received');

        log.debug({ params: req.params, query: req.query });
        const { success, trackId, status, subscriptionId } = await runWithLogger(log, () => validate(zibalVerifySchema, { ...req.query, ...req.params }))
        log.debug({ success, trackId, status, subscriptionId });
        log.info('input validated');

        if (success !== '1') {
            log.info('payment failed')
            return redirectToPaymentPage(res, { status: 'error', error_code: 'NO_SUBSCRIPTION' })
        }

        const redis = await Redis.getClient()
        const rp = new SubscriptionRepository()

        // ------------------------------------------------------------------------- fetching the subscription
        log.info('fetching the subscription')
        const redisKey = getRedisKeyForTemporarySubscription(subscriptionId)
        const subscriptionStr = await redis.get(redisKey)
        log.debug({ redisKey, subscriptionStr })
        if (!subscriptionStr) {
            log.info('system failed to fetch the subscription')
            return redirectToPaymentPage(res, { status: 'error', error_code: 'NO_SUBSCRIPTION' })
        }

        let subscription: WithId<Subscription>
        try {
            subscription = JSON.parse(subscriptionStr) as WithId<Subscription>
        } catch (e) {
            log.warn('system failed to parse the stored subscription json string in session')
            return redirectToPaymentPage(res, { status: 'error', error_code: 'NO_SUBSCRIPTION' })
        }
        log.debug({ subscription })

        const resolved = await resolveCurrencyAndPayment({ log, paymentMethod: subscription.payment.method, res })
        if (!resolved) return
        const [, payment] = resolved

        const userId = subscription.userId

        // ------------------------------------------------------------------------- cancelling, updating subscription status to 'canceled'
        const cancel = async () => {
            log.info("cancelling, updating subscription status to 'canceled'")
            let updateResult = await runWithLogger(log, () => rp.unsafeUpdate(subscription._id!.toString(), userId, { status: 'canceled' }))
            log.debug({ updateResult })
            if (!updateResult.acknowledged || updateResult.matchedCount !== 1) {
                log.info('failed to cancel user\'s subscription')
                // cronjob will clean up the subscription
            }
        }

        // ------------------------------------------------------------------------- reversing payment
        const rollbackPayment = async () => {
            log.info('reversing payment')
            const result = await runWithLogger(log, () => payment.reverse({ trackId }))
            if (result == false) {
                log.error('system failed to reverse a payment, user payment will be rolled back by the payment provider automatically')
                // cronjob will clean up the subscription
            }
        }

        // ------------------------------------------------------------------------- updating subscription status to 'paymentNotVerified'
        // ------------------------------------------------------------------------- this section is added in case, the process is interrupted exactly after verifying payment section, 
        // ------------------------------------------------------------------------- the situation is then handled in a cron job scheduled when starting this server process 
        log.info("updating subscription status to 'paymentNotVerified'")
        let updateResult = await runWithLogger(log, () => rp.unsafeUpdate(subscription._id!.toString(), userId, { status: 'paymentNotVerified', payment: { ...(subscription.payment), authority: trackId, completedAt: Date.now() } }))
        log.debug({ updateResult })
        if (!updateResult.acknowledged || updateResult.matchedCount !== 1) {
            log.info('failed to update user\'s subscription, user payment will be rolled back by the payment provider automatically')
            return redirectToPaymentPage(res, { status: 'error', message: 'subscription process failed, user payment will be rolled back by the payment provider automatically.' })
            // cronjob will clean up the subscription
        }

        async function responseSuccess() {
            // to stop false success payment response redirects to be used by unauthenticated users
            const uuid = randomUUID()
            await redis.set(`payment_results:${uuid}`, 1, 'EX', 300)

            return redirectToPaymentPage(res, { status: 'success', data: uuid })
        }

        // ------------------------------------------------------------------------- verifying payment
        log.info('verifying payment')
        const verificationResult = await runWithLogger(log, () => payment.verify({ trackId }))
        log.debug({ result: verificationResult })
        if (verificationResult == false) {
            const previouslyVerifiedResult = await runWithLogger(log, () => payment.isPreviouslyVerified({ trackId }))
            if (previouslyVerifiedResult === false) {
                log.error('system failed to verify a payment, user payment will be rolled back by the payment provider automatically')
                redirectToPaymentPage(res, { status: 'error', message: 'INTERNAL_ERROR' })

                await cancel()
                return
            }

            await responseSuccess()
        }
        const { refId } = verificationResult

        // ------------------------------------------------------------------------- remove user's valid subscriptions
        log.info("remove user's valid subscriptions")
        const deleteResult = await runWithLogger(log, () => rp.deleteByStatusForUser(userId, ['active', 'trial']))
        if (!deleteResult.acknowledged) {
            redirectToPaymentPage(res, { status: 'error', message: 'INTERNAL_ERROR' })

            await rollbackPayment()

            await cancel()

            return
        }

        // ------------------------------------------------------------------------- updating subscription status to 'active'
        log.info("updating subscription status to 'active'")
        updateResult = await runWithLogger(log, () => rp.unsafeUpdate(subscription._id!.toString(), userId, { status: 'active', payment: { ...(subscription.payment), verifiedAt: Date.now(), refId }, }))
        log.debug({ updateResult, ...({ expirationDate: new Date(subscription.currentPeriodEnd).toUTCString() }) })
        if (!updateResult.acknowledged || updateResult.matchedCount !== 1) {
            log.info('failed to store user\'s subscription')
            redirectToPaymentPage(res, { status: 'error', message: 'subscription process failed.' })

            // rollback payment
            await rollbackPayment()

            await cancel()

            return
        }

        await responseSuccess()
    } catch (error) {
        runWithLogger(log, () => handleError(res, error))
    }
})

function redirectToPaymentPage(res: Response, params: Record<string, string>) {
    const query = new URLSearchParams(params as Record<string, string>).toString();

    return res.redirect(`${isProduction ? `https://${appUrl.replace('https://', '')}` : 'http://localhost:8081'}/#/payment/result?${query}`);
}

// Cancelling a subscription is currently not supported
// router.delete(`/`, auth, async (req, res) => {
//     const log = getLogger().child({ module: 'subscription', route: `GET ${ZIBAL_PAYMENT_VERIFY_CHECK_PATH}` });

//     try {
//         log.info('subscription verification request received');

//         const uu = new UsageRepository()
//         const sr = new SubscriptionRepository()

//         // ------------------------------------------------------------------------- deleting subscription with status 'active'
//         log.info("deleting subscription with status 'active'")
//         const deleteResult = await runWithLogger(log, () => sr.deleteByStatusForUser(req.user!.userId, ['active', 'trial']))
//         log.debug({ updateResult: deleteResult })
//         if (!deleteResult.acknowledged) {
//             log.info("failed to cancel user's subscription")
//             return res.status(500).json({ status: 'error' })
//         }

//         // ------------------------------------------------------------------------- deleting user usage
//         log.info("deleting user usage")
//         const deleteUserUsageResult = await runWithLogger(log, () => uu.deleteByUserId(req.user!.userId))
//         log.debug({ deleteUserUsageResult: deleteUserUsageResult })
//         if (!deleteUserUsageResult) {
//             log.info("failed to cancel user's subscription")
//             return res.status(500).json({ status: 'error' })
//         }

//         log.info("successfully canceled user's subscription")
//         return res.status(204).json({ status: 'success' })
//     } catch (error) {
//         runWithLogger(log, () => handleError(res, error))
//     }
// })

export { router as subscriptionRoutes }
