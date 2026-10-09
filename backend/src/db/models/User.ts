import { boolean, InferType, number, object, string } from "yup";
import { likeObjectId } from "../common_schemas";

export const collectionName = 'user'

export const schemaVersion = 'v1.0.0'

export const languageSchema = string().oneOf(['en', 'fa', 'de'])
export const calendarSchema = string().oneOf(['persian', 'gregorian'])
export const timezoneSchema = string()

const update = {
    schemaVersion: string().optional().min(6).max(20),
    role: string().optional(),

    username: string().optional(),
    phoneNumber: string().optional().matches(/^09[0-9]{9}$/),
    email: string().optional().email(),

    avatarKey: string().optional(), // user/avatar/<userId>/
    totalFilesBytes: number().integer().min(0).optional(), // named this way for consistency
    avatarDeletionQueued: boolean().optional(),
    temporaryAvatar: boolean().optional(),

    password: string().optional(),
    refreshToken: string().optional(),

    language: languageSchema.optional(),
    calendar: calendarSchema.optional(),
    timezone: timezoneSchema.optional(),
}
export const userUpdateSchema = object().shape(update).required()

export const userSchema = object().required().stripUnknown().strict(true).shape({
    schemaVersion: string().optional().min(6).max(20),
    _id: likeObjectId.optional(),
    role: string().required(),

    authMethod: string().oneOf(['email', 'phone']).required(),
    username: string().optional(),
    phoneNumber: string().optional().matches(/^09[0-9]{9}$/).when('authMethod', { is: 'phone', then: s => s.required() }),
    email: string().optional().email().when('authMethod', { is: 'email', then: s => s.required() }),
    password: string().optional().when('authMethod', { is: 'email', then: s => s.required() }),

    avatarKey: string().optional(), // user/avatar/<userId>/
    totalFilesBytes: number().integer().min(0).optional(), // named this way for consistency
    avatarDeletionQueued: boolean().optional(),
    temporaryAvatar: boolean().required(),

    refreshToken: string().optional(),

    language: languageSchema.optional(),
    calendar: calendarSchema.optional(),
    timezone: timezoneSchema.optional(),

    createdAt: number().optional(),
    updatedAt: number().optional(),
})

export type User = InferType<typeof userSchema>
export type UserUpdate = InferType<typeof userUpdateSchema>