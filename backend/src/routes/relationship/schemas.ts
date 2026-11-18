import { number } from "yup";
import { string } from "yup";
import { object } from "yup";
import { DEFAULT_PAGE_SIZE, MAX_PAGE, MAX_PAGE_SIZE } from "../schemas";

export const createSchema = object().shape({
    artistId: string().nullable().optional().label('Artist id'),
    albumId: string().nullable().optional().label('Album id'),
    audioId: string().required().label('Audio id'),
}).stripUnknown().required()

export const fetchSchema = object().shape({
    artistId: string().nullable().optional().label('Artist id'),
    albumId: string().nullable().optional().label('Album id'),
    audioId: string().optional().label('Audio id'),
    page: number().integer().min(1).max(MAX_PAGE).default(1).label('Page'),
    pageSize: number().integer().min(1).max(MAX_PAGE_SIZE).default(DEFAULT_PAGE_SIZE).label('Page size'),
    search: string().max(5000).optional(),
}).stripUnknown().required()

export const filterSchema = object().shape({
    artistId: string().nullable().optional().label('Artist id'),
    albumId: string().nullable().optional().label('Album id'),
    audioId: string().optional().label('Audio id'),
}).stripUnknown().required()

export const updateSchema = object().shape({
    artistId: string().nullable().optional().label('Artist id'),
    albumId: string().nullable().optional().label('Album id'),
    audioId: string().optional().label('Audio id'),
    topTrackWeight: number().positive().integer().nullable().optional(),
}).stripUnknown().required()

export const artistIdPagePageSizeSchema = object().shape({
    artistId: string().required().label('Artist Id'),
    page: number().integer().min(1).max(MAX_PAGE).default(1).label('Page'),
    pageSize: number().integer().min(1).max(MAX_PAGE_SIZE).default(DEFAULT_PAGE_SIZE).label('Page size'),
}).stripUnknown().required()

export const audioAlbumArtistSchema = object().shape({
    audioId: string().objectIdString().required().label('Audio id'),
    artistId: string().objectIdString().label('Artist id'),
    page: number().integer().min(1).max(MAX_PAGE).default(1).label('Page'),
    pageSize: number().integer().min(1).max(MAX_PAGE_SIZE).default(DEFAULT_PAGE_SIZE).label('Page size'),
}).stripUnknown().required()

export const audioArtistAlbumSchema = object().shape({
    audioId: string().objectIdString().required().label('Audio id'),
    albumId: string().objectIdString().label('Album id'),
    page: number().integer().min(1).max(MAX_PAGE).default(1).label('Page'),
    pageSize: number().integer().min(1).max(MAX_PAGE_SIZE).default(DEFAULT_PAGE_SIZE).label('Page size'),
}).stripUnknown().required()

export const audioAlbumSchema = object().shape({
    audioId: string().objectIdString().required().label('Audio id'),
    page: number().integer().min(1).max(MAX_PAGE).default(1).label('Page'),
    pageSize: number().integer().min(1).max(MAX_PAGE_SIZE).default(DEFAULT_PAGE_SIZE).label('Page size'),
}).stripUnknown().required()

export const audioArtistSchema = object().shape({
    audioId: string().objectIdString().required().label('Audio id'),
    albumId: string().nullable().optional().label('Album Id'),
    page: number().integer().min(1).max(MAX_PAGE).default(1).label('Page'),
    pageSize: number().integer().min(1).max(MAX_PAGE_SIZE).default(DEFAULT_PAGE_SIZE).label('Page size'),
}).stripUnknown().required()

export const albumIdPagePageSizeSchema = object().shape({
    albumId: string().required().label('Album Id'),
    page: number().integer().min(1).max(MAX_PAGE).default(1).label('Page'),
    pageSize: number().integer().min(1).max(MAX_PAGE_SIZE).default(DEFAULT_PAGE_SIZE).label('Page size'),
}).stripUnknown().required()

export const albumAudio = object().shape({
    albumId: string().required().label('Album Id'),
    artistId: string().nullable().optional().label('Artist Id'),
    page: number().integer().min(1).max(MAX_PAGE).default(1).label('Page'),
    pageSize: number().integer().min(1).max(MAX_PAGE_SIZE).default(DEFAULT_PAGE_SIZE).label('Page size'),
}).stripUnknown().required()
