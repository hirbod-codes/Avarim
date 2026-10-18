import { boolean, InferType, number, object, string } from 'yup';

export const collectionName = 'artist'

export const schemaVersion = 'v1.0.0'

export const getAvatarKey = (artistId: string) => `avarim/artist/avatar/${artistId}`
export const getBannerKey = (artistId: string) => `avarim/artist/banner/${artistId}`

const shape = {
    schemaVersion: string().optional().min(6).max(20),

    name: string().required(),

    avatarKey: string().optional().url(),
    bannerKey: string().optional().url(),

    temporaryAvatar: boolean().optional(),
    temporaryBanner: boolean().optional(),

    deletionQueued: boolean().optional(),

    createdAt: number().optional(),
    updatedAt: number().optional(),
};

const search = {
    name: string().required(),
}

export const artistSearchSchema = object(search).strict();
export type ArtistSearch = InferType<typeof artistSearchSchema>

export const artistUpdateSchema = object(shape).partial().strict();
export type ArtistUpdate = InferType<typeof artistUpdateSchema>

export const artistSchema = object(shape).strict();
export type Artist = InferType<typeof artistSchema>
