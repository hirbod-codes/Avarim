import { number } from "yup";
import { string } from "yup";
import { object } from "yup";
import { DEFAULT_PAGE_SIZE, MAX_PAGE, MAX_PAGE_SIZE } from "../schemas";

export const postSchema = object().required().shape({
    name: string().required().label('Name'),
})

export const audioListQuerySchema = object().required().shape({
    albumName: string().required().label('Album Name'),
})

export const artistListQuerySchema = object().required().shape({
    albumName: string().required().label('Album Name'),
})

export const infoQuerySchema = object().required().shape({
    albumId: string().optional().label('Album id').when('name', {
        is: (name: any) => !name || name === null || name === undefined,
        then(schema) {
            return schema.required()
        },
        otherwise(schema) {
            return schema.notRequired()
        },
    }),
    name: string().optional().label('Name').when('albumId', {
        is: (albumId: any) => !albumId || albumId === null || albumId === undefined,
        then(schema) {
            return schema.required()
        },
        otherwise(schema) {
            return schema.notRequired()
        },
    }),
}, [['albumId', 'name']]).required().stripUnknown()

export const listQuerySchema = object().required().shape({
    search: string().max(5000).optional(),
    page: number().integer().min(1).max(MAX_PAGE).default(1).label('Page'),
    pageSize: number().integer().min(1).max(MAX_PAGE_SIZE).default(DEFAULT_PAGE_SIZE).label('Page size'),
}).required().stripUnknown()

export const avatarParamsSchema = object().required().shape({
    albumId: string().objectIdString().required().label('Artist id'),
}).required().stripUnknown()

export const deleteParamsSchema = object().required().shape({
    albumId: string().objectIdString().required().label('Artist id'),
}).required().stripUnknown()
