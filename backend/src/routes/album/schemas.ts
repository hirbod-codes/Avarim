import { number } from "yup";
import { string } from "yup";
import { object } from "yup";
import { DEFAULT_PAGE_SIZE, MAX_PAGE, MAX_PAGE_SIZE } from "../schemas";
import { boolean } from "yup";

export const postSchema = object().required().shape({
    name: string().required().label('Name'),
    artistId: string().objectIdString().optional().label('Artist id'),
}).stripUnknown().required()

export const audioListQuerySchema = object().required().shape({
    albumName: string().required().label('Album Name'),
}).stripUnknown().required()

export const albumIdArtistNameSchema = object().required().shape({
    albumId: string().objectIdString().required().label('Album id'),
    albumName: string().required().label('Album Name'),
}).stripUnknown().required()

export const albumNamePagePageSizeSchema = object().required().shape({
    albumId: string().required().label('Album Id').when('albumName', {
        is: (albumName: any) => !albumName || albumName === null || albumName === undefined,
        then(schema) {
            return schema.required()
        },
        otherwise(schema) {
            return schema.notRequired()
        },
    }),
    albumName: string().required().label('Album Name').when('albumId', {
        is: (albumId: any) => !albumId || albumId === null || albumId === undefined,
        then(schema) {
            return schema.required()
        },
        otherwise(schema) {
            return schema.notRequired()
        },
    }),
    page: number().integer().min(1).max(MAX_PAGE).default(1).label('Page'),
    pageSize: number().integer().min(1).max(MAX_PAGE_SIZE).default(DEFAULT_PAGE_SIZE).label('Page size'),
}, [['albumId', 'albumName']]).stripUnknown().required()

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
    artistId: string().optional().label('Artist id').when('albumId', {
        is: (albumId: any) => !albumId || albumId === null || albumId === undefined,
        then(schema) {
            return schema.required()
        },
        otherwise(schema) {
            return schema.notRequired()
        },
    }),
}, [['albumId', 'name'], ['albumId', 'artistId']]).stripUnknown().required()

export const listQuerySchema = object().required().shape({
    search: string().max(5000).optional(),
    page: number().integer().min(1).max(MAX_PAGE).default(1).label('Page'),
    pageSize: number().integer().min(1).max(MAX_PAGE_SIZE).default(DEFAULT_PAGE_SIZE).label('Page size'),
}).stripUnknown().required()

export const avatarParamsSchema = object().required().shape({
    albumId: string().objectIdString().required().label('Artist id'),
}).stripUnknown().required()

export const deleteParamsSchema = object().required().shape({
    shouldDeleteAudios: boolean().optional().label('Should delete audios'),
    albumId: string().objectIdString().required().label('Artist id'),
}).stripUnknown().required()
