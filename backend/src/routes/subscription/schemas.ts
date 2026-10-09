import { number, string } from "yup";
import { object } from "yup";
import { paymentMethodSchema } from "../../db/models/Subscription";

export const postSchema = object().required().shape({
    planTitle: string().required().label('Plan Title'),
    paymentMethod: paymentMethodSchema.required().strict(),
    subscriptionDueTSMS: number().integer().positive().required().label('Subscription due'),
    extraStorageBytes: number().integer().min(0).default(0).label('Storage space'),
})

export const zibalVerifySchema = object().required().shape({
    subscriptionId: string().objectIdString().required().label('Subscription id'),
    success: string().required().label('Success'),
    status: string().label('Status'),
    trackId: string().label('Track id'),
})

export const zarinpalVerifySchema = object().required().shape({
    subscriptionId: string().objectIdString().required().label('Subscription id'),
    authority: string().required().label('Authority'),
})
export const zarinpalVerifyCheckSchema = object().required().shape({
    uuid: string().required().label('Uuid'),
})
