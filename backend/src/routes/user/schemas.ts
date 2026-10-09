import { object, string } from "yup";
import { calendarSchema, languageSchema, timezoneSchema } from "../../db/models/User";

export const preferencesSchema = object().shape({
    language: languageSchema.required(),
    calendar: calendarSchema.required(),
    timezone: timezoneSchema.required(),
}).required()

export const uploadAvatarSchema = object().shape({
    fileName: string().required()
})

export const fetchAvatarSchema = object().shape({
    download: string().oneOf(['true']).nullable().optional()
})
