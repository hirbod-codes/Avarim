import { object, string, number } from "yup";

export const verifySchema = object().required().shape({
    authority: string().required(),
    amount: number().required().integer().min(0)
});

export const reverseSchema = object().required().shape({
    authority: string().required(),
});
