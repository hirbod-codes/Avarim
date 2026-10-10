import { number } from "yup";
import { string } from "yup";
import { object } from "yup";
import { DEFAULT_PAGE_SIZE, MAX_PAGE, MAX_PAGE_SIZE } from "../schemas";

export const postSchema = object().required().shape({
    name: string().required().label('Name'),
})

export const listQuerySchema = object().required().shape({
    search: string().max(5000).optional(),
    page: number().integer().min(1).max(MAX_PAGE).default(1).label('Page'),
    pageSize: number().integer().min(1).max(MAX_PAGE_SIZE).default(DEFAULT_PAGE_SIZE).label('Page size'),
}).required().strict().stripUnknown()

export const avatarParamsSchema = object().required().shape({
    artistId: string().objectIdString().required().label('Artist id'),
}).required().strict().stripUnknown()

export const bannerParamsSchema = object().required().shape({
    artistId: string().objectIdString().required().label('Artist id'),
}).required().strict().stripUnknown()

export const deleteParamsSchema = object().required().shape({
    artistId: string().objectIdString().required().label('Artist id'),
}).required().strict().stripUnknown()
