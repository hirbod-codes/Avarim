import { InferType } from "yup"
import { ISchema } from "yup"
import { getLogger } from "../observability/requestLoggerContext";
import { Logger } from "pino";
import { Response } from "express";
import { createHash, randomInt } from "crypto";

export const A_MONTH_IN_MILLISECONDS = 30 * 24 * 60 * 60 * 1000
export const A_YEAR_IN_MILLISECONDS = 12 * 30 * 24 * 60 * 60 * 1000

export async function validate<T extends ISchema<any, any>>(schema: T, input: any): Promise<InferType<T>> {
    return await schema.validate(input)
}

export function handleError(res: Response, err: any, log?: Logger) {
    try {
        log = log ?? getLogger().child({ step: 'handleError' })

        if (err.name === 'ValidationError') {
            log.info({ errors: err.errors ?? err.message }, 'request input validation failed');
            try { return res.status(400).json({ status: 'error', error: err.errors ?? err.message }); } catch (_) { }
        }

        log.error({ err }, 'Unhandled error');
        try { return res.status(500).json({ status: 'error', error_code: 'INTERNAL_ERROR' }); } catch (_) { }
    } catch (err) {
        console.error('handleError function threw Error!!!', err)
    }
}

export function generateCode() {
    return randomInt(100000, 999999).toString();
}

export function hashCode(code: string, extra: string): string {
    // salted with the extra string so a leaked hash table isn't directly usable
    return createHash('sha256').update(`${code}:${extra}`).digest('hex');
}
