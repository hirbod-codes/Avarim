import { Response } from "express";
import { CurrencyRequired, PaymentMethod } from "../../db/models/Subscription";
import PlanRepository from "../../db/MongoDB/PlanRepository";
import { Logger } from "../../observability/logger";
import { runWithLogger } from "../../observability/requestLoggerContext";
import { Plan } from "../../db/models/Plan";
import { payments } from "../..";
import { ZARINPAL_PAYMENT_VERIFY_CALLBACK_URL, ZIBAL_PAYMENT_VERIFY_CALLBACK_URL } from "./subscription";
import { A_MONTH_IN_MILLISECONDS } from "../../lib";
import AppSettingsRepository from "../../db/MongoDB/AppSettingsRepository";

export const getRedisKeyForTemporarySubscription = (subscriptionId: string) => `plan_request:${subscriptionId}`

/**
 * fetches business plan by plan title
 * 
 * @param log
 * @param planTitle
 * @param planRepository is added to preserve db session utilization
 * @param res if provided, a response with 400 status code and INVALID_PLAN_TITLE error code is sent
 */
export async function fetchBusinessPlan({ log, planTitle, planRepository, res }: { log: Logger, planTitle: string, planRepository?: PlanRepository, res?: Response }): Promise<Plan | undefined> {
    log.info('fetching business plan')

    const plans = await runWithLogger(log, () => (planRepository ?? new PlanRepository()).getAll())
    const plan = plans.find(f => f.title === planTitle)
    log.debug({ plan, plans })
    if (plan === undefined) {
        log.warn('No plan found with the provided plan title')
        res?.status(400).json({ status: 'error', error_code: 'INVALID_PLAN_TITLE' })
    }

    return plan
}

/**
 * resolves the currency and callback from given payment method
 * @param log 
 * @param paymentMethod 
 * @param plan 
 * @param duration 
 * @param res if provided, a response with 400 status code and UNSUPPORTED_PAYMENT_METHOD error code is sent
 * @returns 
 */
export async function resolveCurrencyAndPayment({ log, paymentMethod, res }: { log: Logger, paymentMethod: PaymentMethod, res?: Response }): Promise<undefined | [currency: CurrencyRequired, payment: IPay, callback: (subscriptionId: string) => string]> {
    log.info('resolving currency and payment method and callback url')
    let currency: CurrencyRequired = resolveCurrencyFromPaymentMethod(paymentMethod)!

    let callback: (subscriptionId: string) => string
    switch (paymentMethod) {
        case 'zarinpal':
            callback = ZARINPAL_PAYMENT_VERIFY_CALLBACK_URL
            break;

        case 'zibal':
            callback = ZIBAL_PAYMENT_VERIFY_CALLBACK_URL
            break;

        case 'paypal':
            res?.status(400).json({ status: 'error', error_code: 'UNSUPPORTED_PAYMENT_METHOD' })
            return undefined

        case 'bitcoin':
            res?.status(400).json({ status: 'error', error_code: 'UNSUPPORTED_PAYMENT_METHOD' })
            return undefined

        default:
            res?.status(400).json({ status: 'error', error_code: 'UNSUPPORTED_PAYMENT_METHOD' })
            return undefined
    }

    if (!payments[paymentMethod]) {
        res?.status(400).json({ status: 'error', error_code: 'UNSUPPORTED_PAYMENT_METHOD' })
        return undefined
    }

    const payment: IPay = payments[paymentMethod]

    log.debug({ currency, payment })
    return [currency, payment, callback]
}

export function resolveCurrencyFromPaymentMethod(paymentMethod: PaymentMethod): CurrencyRequired {
    switch (paymentMethod) {
        case 'zarinpal':
            return 'IRR'

        case 'zibal':
            return 'IRR'

        case 'paypal':
            return 'USD'

        case 'bitcoin':
            return 'BTC'

        default:
            throw new Error('UNSUPPORTED_PAYMENT_METHOD')
    }
}

type calculatePricesForRemainingPlanDueOptions = {
    log: Logger,
    plan: Plan,
    durationMS: number,
    privilegesStorageBytes: number,
    currency: CurrencyRequired,
    appSettingsRepository?: AppSettingsRepository,
    res?: Response
}
export async function calculatePricesForSubscriptionDue({
    log,
    plan,
    durationMS,
    privilegesStorageBytes,
    currency,
    appSettingsRepository,
    res
}: calculatePricesForRemainingPlanDueOptions): Promise<[planPrice: number, storagePrice: number, totalPrice: number] | undefined> {
    log.info('calculating price')

    const durationPerMonth = (durationMS) / (A_MONTH_IN_MILLISECONDS)
    if (durationPerMonth < 0) {
        log.error("logic error!!!, 'currentPeriodEnd' can not be smaller than 'nowTS'")
        throw new Error("logic error!!!, 'currentPeriodEnd' can not be smaller than 'nowTS'")
    }

    let planPrice: number, storagePrice: number | undefined = undefined, storagePricePerMonth: number = 0

    if (privilegesStorageBytes > plan.privileges.storageBytes) {
        log.info('user has purchased extra storage, calculating additional storage cost')

        const pricingSettings = await runWithLogger(log, () => (appSettingsRepository ?? new AppSettingsRepository()).getByKey('pricing'))
        log.debug({ pricingSettings })
        if (!pricingSettings) {
            log.error({ pricingSettings }, "failed to fetch app settings with 'pricing' key")
            res?.status(500).json({ status: 'error', error_code: 'INTERNAL_ERROR' })
            return undefined
        }

        const pricePerGbPerMonth = pricingSettings.pricePerGbPerMonth[currency]

        const extraBytes = privilegesStorageBytes - plan.privileges.storageBytes
        if (extraBytes > 0)
            storagePricePerMonth = (extraBytes / (1024 * 1024 * 1024)) * pricePerGbPerMonth
        else
            log.error({ pricingSettings }, "the provided plan already covers storage bytes")
    }

    planPrice = durationPerMonth * plan.price[currency]
    storagePrice = durationPerMonth * storagePricePerMonth
    const totalPrice = planPrice + storagePrice
    log.info({
        remainingPlanDueFractionPerMonth: durationPerMonth,
        calculatedPlanPrice: planPrice,
        calculatedStoragePrice: storagePrice,
        totalPrice,
        durationMS: durationMS,
        durationMSDays: durationMS / (1000 * 60 * 60 * 24),
    })

    return [planPrice, storagePrice, totalPrice]
}
