import { object, string } from "yup";
import { DEFAULT_PAGE_SIZE, MAX_PAGE, MAX_PAGE_SIZE } from '../schemas';
import { number } from "yup";

export const postSchema = object().required().shape({
    title: string().required().label('Title'),
})

export const listQuerySchema = object().required().shape({
    page: number().integer().min(1).max(MAX_PAGE).default(1).label('Page'),
    pageSize: number().integer().min(1).max(MAX_PAGE_SIZE).default(DEFAULT_PAGE_SIZE).label('Page size'),
})

export const infoQuerySchema = object().required().shape({
    audioId: string().objectIdString().optional().label('Audio id').when('title', {
        is: (title: any) => !title || title === null || title === undefined,
        then(schema) {
            return schema.required()
        },
        otherwise(schema) {
            return schema.notRequired()
        },
    }),
    title: string().optional().label('Title').when('audioId', {
        is: (audioId: any) => !audioId || audioId === null || audioId === undefined,
        then(schema) {
            return schema.required()
        },
        otherwise(schema) {
            return schema.notRequired()
        },
    }),
}, [['audioId', 'title']])

export const signedTokenQuerySchema = object().required().shape({
    audioId: string().objectIdString().required().label('Audio id')
})

export const ttsQuerySchema = object().required().shape({
    text: string().max(500).required().label('Text'),
    authToken: string().max(500).required().label('Text'),
    userTtsApiKey: string().max(500).optional().label('Token'),
})

export const fileParamsSchema = object().required().shape({
    audioId: string().objectIdString().required().label('Audio id'),
    download: string().optional().label('Download'),
})

export const webFileParamsSchema = object().required().shape({
    token: string().required().label('Token'),
    audioId: string().objectIdString().required().label('Audio id'),
    download: string().optional().label('Download'),
})

export const coverArtParamsSchema = object().required().shape({
    audioId: string().objectIdString().required().label('Audio id'),
    download: string().optional().label('Download'),
})

export const deleteParamsSchema = object().required().shape({
    audioId: string().objectIdString().required().label('Audio id'),
})
