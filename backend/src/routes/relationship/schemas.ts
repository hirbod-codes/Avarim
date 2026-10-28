import { number } from "yup";
import { string } from "yup";
import { object } from "yup";
import { DEFAULT_PAGE_SIZE, MAX_PAGE, MAX_PAGE_SIZE } from "../schemas";

export const createSchema = object().required().shape({
    artistId: string().optional().label('Artist id'),
    albumId: string().optional().label('Album id'),
    audioId: string().required().label('Audio id'),
}).stripUnknown().required()

export const fetchSchema = object().required().shape({
    artistId: string().nullable().optional().label('Artist id'),
    albumId: string().nullable().optional().label('Album id'),
    audioId: string().nullable().optional().label('Audio id'),
    page: number().integer().min(1).max(MAX_PAGE).default(1).label('Page'),
    pageSize: number().integer().min(1).max(MAX_PAGE_SIZE).default(DEFAULT_PAGE_SIZE).label('Page size'),
}).stripUnknown().required()

export const filterSchema = object().required().shape({
    artistId: string().nullable().optional().label('Artist id'),
    albumId: string().nullable().optional().label('Album id'),
    audioId: string().nullable().optional().label('Audio id'),
}).stripUnknown().required()

export const updateSchema = object().required().shape({
    artistId: string().nullable().optional().label('Artist id'),
    albumId: string().nullable().optional().label('Album id'),
    audioId: string().nullable().optional().label('Audio id'),
}).stripUnknown().required()

export const artistIdPagePageSizeSchema = object().required().shape({
    artistId: string().required().label('Artist Id'),
    page: number().integer().min(1).max(MAX_PAGE).default(1).label('Page'),
    pageSize: number().integer().min(1).max(MAX_PAGE_SIZE).default(DEFAULT_PAGE_SIZE).label('Page size'),
})

export const audioAlbumArtistSchema = object().required().shape({
    audioId: string().objectIdString().required().label('Audio id'),
    artistId: string().objectIdString().label('Artist id'),
    page: number().integer().min(1).max(MAX_PAGE).default(1).label('Page'),
    pageSize: number().integer().min(1).max(MAX_PAGE_SIZE).default(DEFAULT_PAGE_SIZE).label('Page size'),
}).required().stripUnknown()

export const audioArtistAlbumSchema = object().required().shape({
    audioId: string().objectIdString().required().label('Audio id'),
    albumId: string().objectIdString().label('Album id'),
    page: number().integer().min(1).max(MAX_PAGE).default(1).label('Page'),
    pageSize: number().integer().min(1).max(MAX_PAGE_SIZE).default(DEFAULT_PAGE_SIZE).label('Page size'),
}).required().stripUnknown()

export const audioAlbumSchema = object().required().shape({
    audioId: string().objectIdString().required().label('Audio id'),
    page: number().integer().min(1).max(MAX_PAGE).default(1).label('Page'),
    pageSize: number().integer().min(1).max(MAX_PAGE_SIZE).default(DEFAULT_PAGE_SIZE).label('Page size'),
}).required().stripUnknown()

export const audioArtistSchema = object().required().shape({
    audioId: string().objectIdString().required().label('Audio id'),
    page: number().integer().min(1).max(MAX_PAGE).default(1).label('Page'),
    pageSize: number().integer().min(1).max(MAX_PAGE_SIZE).default(DEFAULT_PAGE_SIZE).label('Page size'),
}).required().stripUnknown()

export const albumNamePagePageSizeSchema = object().required().shape({
    albumId: string().required().label('Album Id'),
    page: number().integer().min(1).max(MAX_PAGE).default(1).label('Page'),
    pageSize: number().integer().min(1).max(MAX_PAGE_SIZE).default(DEFAULT_PAGE_SIZE).label('Page size'),
}).stripUnknown().required()
