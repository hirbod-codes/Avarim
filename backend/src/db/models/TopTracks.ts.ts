import { InferType, number, object, string } from 'yup';

export const collectionName = 'topTracks'

export const schemaVersion = 'v1.0.0'

const shape = {
    schemaVersion: string().optional().min(6).max(20),

    artistId: string().required(),
    audioId: string().required(),
    sortId: number().integer().positive().required(),

    createdAt: number().optional(),
    updatedAt: number().optional(),
};

export const topTracksFilterSchema = object({
    artistId: string().nullable().optional(),
    audioId: string().nullable().optional(),
    sortId: number().integer().positive().nullable().optional(),
}).strict();
export type TopTracksFilter = InferType<typeof topTracksFilterSchema>

export const topTracksSchema = object(shape).strict();
export type TopTracks = InferType<typeof topTracksSchema>
