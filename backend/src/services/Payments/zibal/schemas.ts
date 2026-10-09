import { object, string, number } from "yup";

export const verifySchema = object().required().shape({
    trackId: string().required(),
});

export const reverseSchema = object().required().shape({
    trackId: string().required(),
});
