import { boolean, InferType, number, object, string } from 'yup';
import { s3RootName } from '../../configs';

export const collectionName = 'playlistAudio'

export const schemaVersion = 'v1.0.0'

const shape = {
    schemaVersion: string().optional().min(6).max(20),

    playlistId: string().required(),

    audioId: string().required(),

    deletionQueued: boolean().optional(),

    createdAt: number().optional(),
    updatedAt: number().optional(),
};

const search = {
    _id: string().required(),
    playlistId: string().required(),
    audioId: string().required(),
    audioTitle: string().required(),
}

export const playlistAudioSearchSchema = object(search).strict();
export type PlaylistAudioSearch = InferType<typeof playlistAudioSearchSchema>

export const playlistAudioUpdateSchema = object(shape).partial().strict();
export type PlaylistAudioUpdate = InferType<typeof playlistAudioUpdateSchema>

export const playlistAudioSchema = object(shape).strict();
export type PlaylistAudio = InferType<typeof playlistAudioSchema>
