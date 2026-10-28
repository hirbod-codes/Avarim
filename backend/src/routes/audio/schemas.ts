import { object, string } from "yup";
import { DEFAULT_PAGE_SIZE, MAX_PAGE, MAX_PAGE_SIZE } from '../schemas';
import { number } from "yup";
import { audioPatchSchema, audioTagsSchema, audioUpdateSchema } from "../../db/models/Audio";
import { array } from "yup";

export const isUploadFinished = object().shape({
    audioId: string().required().label('Audio Id'),
}).required().stripUnknown()

export const isTitleUnique = object().shape({
    title: string().required().label('Title'),
}).required().stripUnknown()

export const postSchema = object().shape({
    title: string().optional().label('Title'),
}).required().stripUnknown()

export const tagUpdateSchema = audioUpdateSchema.pick(['tags']).shape({
    tags: audioTagsSchema.omit(['album', 'albumArtists', 'artists', 'audioTitle', 'lyrics']).partial(),
    audioId: string().required().label('Audio Id'),
}).required().stripUnknown()

export const artistUpdateSchema = object().shape({
    artists: array(string().required().label('Artist').max(1000)).min(1).required(),
    audioId: string().required().label('Audio Id'),
}).required().stripUnknown()

export const albumUpdateSchema = object().shape({
    album: string().nullable().optional().label('Album').max(1000),
    audioId: string().required().label('Audio Id'),
}).required().stripUnknown()

export const lyricsUpdateSchema = object().shape({
    lyrics: string().required().label('Lyrics').max(500000),
    audioId: string().required().label('Audio Id'),
}).required().stripUnknown()

export const titleUpdateSchema = object().shape({
    title: string().required().label('Title'),
    audioId: string().required().label('Audio Id'),
}).required().stripUnknown()

export const listQuerySchema = object().required().shape({
    search: string().max(5000).optional(),
    page: number().integer().min(1).max(MAX_PAGE).default(1).label('Page'),
    pageSize: number().integer().min(1).max(MAX_PAGE_SIZE).default(DEFAULT_PAGE_SIZE).label('Page size'),
}).required().stripUnknown()

export const infoQuerySchema = object().required().shape({
    audioId: string().objectIdString().required().label('Audio id'),
}).required().stripUnknown()

export const signedTokenQuerySchema = object().required().shape({
    audioId: string().objectIdString().required().label('Audio id')
}).required().stripUnknown()

export const ttsQuerySchema = object().required().shape({
    text: string().max(500).required().label('Text'),
    authToken: string().max(500).required().label('Text'),
    userTtsApiKey: string().max(500).optional().label('Token'),
}).required().stripUnknown()

export const fileParamsSchema = object().required().shape({
    audioId: string().objectIdString().required().label('Audio id'),
    download: string().optional().label('Download'),
}).required().stripUnknown()

export const webFileParamsSchema = object().required().shape({
    token: string().required().label('Token'),
    audioId: string().objectIdString().required().label('Audio id'),
    download: string().optional().label('Download'),
}).required().stripUnknown()

export const coverArtParamsSchema = object().required().shape({
    audioId: string().objectIdString().required().label('Audio id'),
}).required().stripUnknown()

export const deleteParamsSchema = object().required().shape({
    audioId: string().objectIdString().required().label('Audio id'),
}).required().stripUnknown()

export const postAudioAlbumSchema = object().required().shape({
    audioId: string().objectIdString().required().label('Audio id'),
    albumId: string().objectIdString().required().label('Album id'),
}).required().stripUnknown()

export const postAudioArtistSchema = object().required().shape({
    audioId: string().objectIdString().required().label('Audio id'),
    artistId: string().objectIdString().required().label('Artist id'),
}).required().stripUnknown()

export const deleteAudioAlbumSchema = object().required().shape({
    audioId: string().objectIdString().required().label('Audio id'),
    albumId: string().objectIdString().label('Album id'),
    artistId: string().objectIdString().label('Artist id'),
}).required().stripUnknown()

export const deleteAudioArtistSchema = object().required().shape({
    audioId: string().objectIdString().required().label('Audio id'),
    artistId: string().objectIdString().label('Artist id'),
    albumId: string().objectIdString().label('Album id'),
}).required().stripUnknown()
