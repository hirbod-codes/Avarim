import { InferType, number, object, string } from "yup";
import { likeObjectId } from "../common_schemas";

export const collectionName = 'invalidToken'

export const schemaVersion = 'v1.0.0'

export const invalidTokensSchema = object().required().stripUnknown().strict(true).shape({
    schemaVersion: string().optional().min(6).max(20),
    _id: likeObjectId.optional(),
    token: string().required(),
    createdAt: number().optional(),
    updatedAt: number().optional(),
})

export type InvalidToken = InferType<typeof invalidTokensSchema>