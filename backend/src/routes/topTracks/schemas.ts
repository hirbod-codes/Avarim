import { number, object, string } from "yup";
import { DEFAULT_PAGE_SIZE, MAX_PAGE, MAX_PAGE_SIZE } from "../schemas";

export const postSchema = object().required().shape({
    artistId: string().required().label('Artist id'),
    audioId: string().required().label('Audio id'),
    sortId: number().required().label('Sort id'),
}).stripUnknown().required()

export const listSchema = object().required().shape({
    artistId: string().required().label('Artist id'),
    page: number().integer().min(1).max(MAX_PAGE).default(1).label('Page'),
    pageSize: number().integer().min(1).max(MAX_PAGE_SIZE).default(DEFAULT_PAGE_SIZE).label('Page size'),
}).stripUnknown().required()

export const fetchSchema = object().required().shape({
    artistId: string().nullable().optional().label('Artist id'),
    audioId: string().nullable().optional().label('Audio id'),
    sortId: number().nullable().optional().label('Sort id'),
}).stripUnknown().required()

export const deleteSchema = object().required().shape({
    topTracksId: string().required().label('TopTracks id'),
}).stripUnknown().required()