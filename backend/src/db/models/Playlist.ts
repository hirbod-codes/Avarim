import { boolean, InferType, number, object, string } from 'yup';

export const collectionName = 'playlist'

export const schemaVersion = 'v1.0.0'

export const getAvatarKey = (playlistId: string) => `avarim/playlist/avatar/${playlistId}`

const shape = {
    schemaVersion: string().optional().min(6).max(20),

    userId: string().required(),

    name: string().required(),

    avatarKey: string().optional().url(),

    deletionQueued: boolean().optional(),

    createdAt: number().optional(),
    updatedAt: number().optional(),
};

const search = {
    _id: string().required(),
    name: string().required(),
}

export const playlistSearchSchema = object(search).strict();
export type PlaylistSearch = InferType<typeof playlistSearchSchema>

export const playlistUpdateSchema = object(shape).partial().strict();
export type PlaylistUpdate = InferType<typeof playlistUpdateSchema>

export const playlistSchema = object(shape).strict();
export type Playlist = InferType<typeof playlistSchema>
