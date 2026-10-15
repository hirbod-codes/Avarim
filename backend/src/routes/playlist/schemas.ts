import { array, number } from "yup";
import { string } from "yup";
import { object } from "yup";
import { DEFAULT_PAGE_SIZE, MAX_PAGE, MAX_PAGE_SIZE } from "../schemas";

export const postSchema = object().required().shape({
    name: string().required().label('Name'),
})

export const isNameUnique = object().required().shape({
    name: string().required().label('Name'),
})

export const createPlaylistAudioSchema = object().required().shape({
    playlistId: string().objectIdString().required().label('Playlist id'),
    audioId: string().objectIdString().optional().label('Audio id').when('audioIds', {
        is: (audioIds: any) => !audioIds || audioIds === null || audioIds === undefined,
        then(schema) {
            return schema.required()
        },
        otherwise(schema) {
            return schema.notRequired()
        },
    }),
    audioIds: array(string().objectIdString().required()).min(1).optional().label('Audio ids').when('audioId', {
        is: (audioId: any) => !audioId || audioId === null || audioId === undefined,
        then(schema) {
            return schema.required()
        },
        otherwise(schema) {
            return schema.notRequired()
        },
    }),
}, [['audioId', 'audioIds']]).required().stripUnknown()

export const listQuerySchema = object().required().shape({
    search: string().max(5000).optional(),
    page: number().integer().min(1).max(MAX_PAGE).default(1).label('Page'),
    pageSize: number().integer().min(1).max(MAX_PAGE_SIZE).default(DEFAULT_PAGE_SIZE).label('Page size'),
}).required().stripUnknown()

export const avatarParamsSchema = object().required().shape({
    playlistId: string().objectIdString().required().label('Playlist id'),
}).required().stripUnknown()

export const deleteParamsSchema = object().required().shape({
    playlistId: string().objectIdString().required().label('Playlist id'),
}).required().stripUnknown()

export const infoQuerySchema = object().required().shape({
    search: string().max(5000).optional(),
    page: number().integer().min(1).max(MAX_PAGE).default(1).label('Page'),
    pageSize: number().integer().min(1).max(MAX_PAGE_SIZE).default(DEFAULT_PAGE_SIZE).label('Page size'),
    playlistId: string().optional().label('Playlist id').when('name', {
        is: (name: any) => !name || name === null || name === undefined,
        then(schema) {
            return schema.required()
        },
        otherwise(schema) {
            return schema.notRequired()
        },
    }),
    name: string().optional().label('Name').when('playlistId', {
        is: (playlistId: any) => !playlistId || playlistId === null || playlistId === undefined,
        then(schema) {
            return schema.required()
        },
        otherwise(schema) {
            return schema.notRequired()
        },
    }),
}, [['playlistId', 'name']]).required().stripUnknown()
