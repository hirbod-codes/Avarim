import { boolean, InferType, number, object, string } from 'yup';
import { s3RootName } from '../../configs';

export const collectionName = 'album'

export const schemaVersion = 'v1.0.0'

export const getAvatarKey = (albumId: string) => `${s3RootName}/album/avatar/${albumId}`

const shape = {
    schemaVersion: string().optional().min(6).max(20),

    artistId: string().optional(),

    name: string().required(),

    avatarKey: string().optional().url(),

    temporaryAvatar: boolean().optional(),

    deletionQueued: boolean().optional(),

    createdAt: number().optional(),
    updatedAt: number().optional(),
};

const search = {
    _id: string().required(),
    name: string().required(),
}

export const albumSearchSchema = object(search).strict();
export type AlbumSearch = InferType<typeof albumSearchSchema>

export const albumUpdateSchema = object(shape).partial().strict();
export type AlbumUpdate = InferType<typeof albumUpdateSchema>

export const albumSchema = object(shape).strict();
export type Album = InferType<typeof albumSchema>
