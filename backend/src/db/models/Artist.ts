import { boolean, InferType, number, object, string } from 'yup';

export const collectionName = 'artist'

export const schemaVersion = 'v1.0.0'

const shape = {
    schemaVersion: string().optional().min(6).max(20),

    name: string().required(),

    avatarKey: string().optional().url(), // avarim/artist/avatar/<artistId>

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
