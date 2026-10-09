import { InferType, number, object, string } from 'yup';
import { privilegesSchema } from './Plan';

export const collectionName = 'subscription'

export const schemaVersion = 'v1.0.0'

export type SubscriptionStatus = 'active' | 'canceled' | 'trial' | 'expired' | 'paymentNotVerified' | 'paymentNotCompleted' | 'inDebtToUser'
const statusSchema = string().oneOf<SubscriptionStatus>(['active', 'canceled', 'trial', 'expired', 'paymentNotVerified', 'paymentNotCompleted', 'inDebtToUser'])

export type PaymentMethod = "zarinpal" | "paypal" | "bitcoin" | "zibal"
export type SubscriptionDuration = "month" | "year"
export const paymentMethodSchema = string().oneOf<PaymentMethod>(['zarinpal', 'zibal', 'paypal', 'bitcoin'])
export const subscriptionDurationSchema = string().oneOf<SubscriptionDuration>(['month', 'year'])

export const currencySchema = string().oneOf(['IRR', 'USD', 'EUR', 'BTC', 'ETH'])
export const currencyRequiredSchema = currencySchema.required()
export type Currency = InferType<typeof currencySchema>
export type CurrencyRequired = InferType<typeof currencyRequiredSchema>

export const paymentSchema = object().shape({
    authority: string().optional(),
    completedAt: number().integer().min(0).optional(),
    verifiedAt: number().integer().min(0).optional(),
    refId: string().optional(),
    cardNumber: string().optional(),
    cardNumberHash: string().optional(),
    processorSubscriptionId: string(),
    method: paymentMethodSchema.required(),
    currency: currencyRequiredSchema,
    amount: number().integer().min(0).required(), // Negative values indicate we are in dept to user
})
export type Payment = InferType<typeof paymentSchema>

const create = {
    schemaVersion: string().optional().min(6).max(20),
    userId: string().required(),
    planTitle: string().required().label('Plan title'),
    privileges: privilegesSchema.required(),
    status: statusSchema.required(),
    currentPeriodEnd: number().integer().positive().required(),
    payment: paymentSchema.required(),
}
export const subscriptionCreateSchema = object().shape(create).required()

const update = {
    privileges: privilegesSchema.optional(),
    status: statusSchema.optional(),
    currentPeriodEnd: number().optional(),
    payment: paymentSchema.optional(),
}
export const subscriptionUpdateSchema = object().shape(update).required()

export const subscriptionSchema = object().shape({
    schemaVersion: string().optional().min(6).max(20),
    userId: string().required(),
    planTitle: string().required().label('Plan title'),
    privileges: privilegesSchema.required(),
    status: statusSchema.required(),
    currentPeriodEnd: number().integer().positive().required(),
    payment: paymentSchema.required(),
    createdAt: number().optional(),
    updatedAt: number().optional(),
})

export type SubscriptionCreate = InferType<typeof subscriptionCreateSchema>
export type SubscriptionUpdate = InferType<typeof subscriptionUpdateSchema>
export type Subscription = InferType<typeof subscriptionSchema>
