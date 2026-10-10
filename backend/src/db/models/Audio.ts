import { boolean, array, InferType, number, object, string } from 'yup';
import { contentTypeSchema } from '../common_schemas';

export const collectionName = 'audio'

export const schemaVersion = 'v1.0.0'

const str = string().trim().min(1).max(2000);
const strList = array(str.strict().required()).max(50);
const posInt = number().integer().positive();

const audioTags = {
    audioTitle: str.optional(), // extracted from audio file, might be different
    artists: strList.optional(),
    albumArtists: strList.optional(),
    album: str.optional(),
    trackNumber: posInt.optional(),
    trackTotal: posInt.optional(),
    discNumber: posInt.optional(),
    discTotal: posInt.optional(),

    year: number().integer().min(1000).max(9999).optional(),
    /** ISO-8601 partial date: YYYY, YYYY-MM or YYYY-MM-DD */
    releaseDate: string().matches(/^\d{4}(-\d{2}(-\d{2})?)?$/).optional(),

    genres: strList,
    composers: strList,
    lyricists: strList,
    producers: strList,
    label: str.optional(),
    catalogNumber: str.optional(),
    /** normalised: upper-case, no hyphens */
    isrc: array(string().matches(/^[A-Z]{2}[A-Z0-9]{3}\d{7}$/)).max(10),
    bpm: number().positive().max(400).optional(),
    key: str.optional(),
    compilation: boolean(),
    language: str.optional(),
    copyright: str.optional(),
    comment: string().max(20_000).optional(),
    lyrics: string().max(200_000).optional(),
}

export const audioTagsSchema = object(audioTags).strict();
export type AudioTags = InferType<typeof audioTagsSchema>

const audioTechnical = {
    container: string().optional(),
    ffprobeFormat: string().optional(),
    codec: string().optional(),
    codecProfile: string().optional(),
    lossless: boolean().optional(),
    durationSec: number().optional(),
    bitrate: number().optional(),
    sampleRate: number().optional(),
    bitDepth: number().optional(),
    channels: number().optional(),
    channelLayout: string().optional(),
    encoder: string().optional(),
    sizeBytes: number().required().strict().positive(),
    sha256: string().required(),
    audioSha256: string().required(),
    tagTypes: array(string().required()).optional(),
    replayGain: object({ trackGainDb: number().optional(), trackPeak: number().optional(), albumGainDb: number().optional() }).optional(),
    loudness: object({ integratedLufs: number().optional().strict(), truePeakDbtp: number().optional().strict(), loudnessRangeLu: number().optional().strict() }).optional(),
    waveform: array(number().required().strict()).optional()
}

export const audioTechnicalSchema = object(audioTechnical)
export type TechnicalInfo = InferType<typeof audioTechnicalSchema>

const shape = {
    schemaVersion: string().optional().min(6).max(20),

    title: str.required(),

    contentType: contentTypeSchema.optional(),
    totalFilesBytes: number().integer().min(0).optional(),

    bucketKey: string().optional().url(), // avarim/audio/<audioId>
    webBucketKey: string().optional().url(), // avarim/audio/web/<audioId>
    coverArtKey: string().optional().url(), // avarim/audio/cover_art/<audioId>

    deletionQueued: boolean().optional(),
    temporary: boolean().optional(),
    isPrepared: boolean().optional(),

    createdAt: number().optional(),
    updatedAt: number().optional(),

    tags: audioTagsSchema.optional(),
    technical: audioTechnicalSchema.optional(),
};

const search = {
    title: str.required(),
}

export const audioSearchSchema = object(search).strict();
export type AudioSearch = InferType<typeof audioSearchSchema>

export const audioPatchSchema = object(shape).pick(['title', 'tags']).partial().strict();
export type AudioPatch = InferType<typeof audioPatchSchema>

export const audioUpdateSchema = object(shape).omit(['createdAt', 'updatedAt']).partial().strict();
export type AudioUpdate = InferType<typeof audioUpdateSchema>

export const audioSchema = object(shape).strict();
export type Audio = InferType<typeof audioSchema>
