import { InferType, number, object, string } from "yup";

/**
 * Since album and artist collections have many to many relationship, updating an album document with embedded `artistNames` field will be difficult.
 * Therefor, the field is removed and this model is used instead.
 */

export const collectionName = 'artistAlbumAudio'

export const schemaVersion = 'v1.0.0'

const shape = {
    schemaVersion: string().optional().min(6).max(20),

    artistName: string().required(),
    albumName: string().required(),
    audioTitle: string().required(),

    createdAt: number().optional(),
    updatedAt: number().optional(),
};

export const artistAlbumAudioSchema = object(shape).strict();
export type ArtistAlbumAudio = InferType<typeof artistAlbumAudioSchema>

export const artistAlbumAudioUpdateSchema = artistAlbumAudioSchema.pick(['albumName', 'artistName', 'audioTitle']).partial().strict();
export type ArtistAlbumAudioUpdate = InferType<typeof artistAlbumAudioUpdateSchema>
