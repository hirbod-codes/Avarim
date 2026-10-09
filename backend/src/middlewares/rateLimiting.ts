import rateLimit from "express-rate-limit";
import { isProduction } from '../configs';

export const generalRateLimiter = rateLimit({
    skipFailedRequests: isProduction ? false : true,
    skip: () => !isProduction,
    windowMs: 15 * 60 * 1000,
    max: 200,
    message: 'Too many requests, please try again later.',
});

export const authRateLimiter = rateLimit({
    skipFailedRequests: isProduction ? false : true,
    skip: () => !isProduction,
    windowMs: 45 * 1000,
    max: 10,
    message: 'Too many requests to authentication routes, please try again later.',
});