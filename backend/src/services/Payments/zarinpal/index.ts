import { randomUUID } from "crypto";
import { httpsRequest } from "../../../utils";
import { getLogger, runWithLogger } from "../../../observability/requestLoggerContext";
import { validate } from "../../../lib";
import { verifySchema, reverseSchema } from "./schemas";

export class Zarinpal implements IPay {
    baseEndpoint: string
    merchantId: string

    constructor(baseEndpoint: string, merchantId: string) {
        this.merchantId = merchantId
        this.baseEndpoint = baseEndpoint
    }

    isPreviouslyVerified(params: any): Promise<boolean> {
        throw new Error("Method not implemented.");
    }

    async request(amount: number, callbackUrl: string) {
        const log = getLogger().child({ step: 'request' });

        try {
            const result = await httpsRequest(
                { host: `${this.baseEndpoint.replace('https://', '')}`, path: 'pg/v4/payment/request.json', method: 'post', headers: { 'content-type': 'application/json', accept: 'application/json' } },
                JSON.stringify({
                    // merchant_id: this.merchantId,
                    merchant_id: randomUUID(),
                    amount,
                    currency: "IRR",
                    callback_url: callbackUrl,
                    description: 'plan payment',
                    metadata: {
                        auto_verify: false
                    }
                })
            )
            if (!result.response.statusCode || result.response.statusCode < 200 || result.response.statusCode >= 300) {
                log.error({ statusCode: result.response.statusCode }, 'sending request to zarinpal `pg/v4/payment/request.json` endpoint failed')
                return false
            }

            const data = JSON.parse(result.data) as {
                data: {
                    code: number,
                    message: string,
                    authority: string,
                    fee_type: "Merchant",
                    fee: number
                },
                errors: []
            }
            log.debug({ data })

            const { data: { code, authority }, errors } = data

            if (!errors || errors.length !== 0 || code !== 100) {
                log.error({ errors }, 'request from zarinpal `pg/v4/payment/request.json` endpoint, responded with errors')
                return false
            }

            return { redirectUrl: `https://payment.zarinpal.com/pg/StartPay/${authority}` }
        } catch (error) {
            log.error({ error }, 'requesting payment failed with error')
            return false
        }
    }

    async verify(params: any) {
        const log = getLogger().child({ step: 'verify' });

        try {
            const { authority, amount } = await runWithLogger(log, () => validate(verifySchema, params))

            const result = await httpsRequest(
                { host: `${this.baseEndpoint.replace('https://', '')}`, path: 'pg/v4/payment/verify.json', method: 'post', headers: { 'content-type': 'application/json', accept: 'application/json' } },
                JSON.stringify({
                    // merchant_id: this.merchantId,
                    merchant_id: randomUUID(),
                    amount,
                    authority
                })
            )
            if (!result.response.statusCode || result.response.statusCode < 200 || result.response.statusCode >= 300) {
                log.error({ statusCode: result.response.statusCode }, 'sending request to zarinpal `pg/v4/payment/verify.json` endpoint failed')
                return false
            }

            const responseData = JSON.parse(result.data) as {
                data: {
                    code: number,
                    message: string,
                    card_hash: string,
                    card_pan: string,
                    ref_id: number | undefined | null,
                    fee_type: 'Merchant',
                    fee: number
                },
                errors: []
            }
            log.debug({ responseData })

            const { data: { ref_id, card_pan, card_hash, code }, errors } = responseData

            if (!errors || errors.length !== 0 || (code !== 100 && code !== 101) || ref_id === undefined || ref_id === null) {
                log.error({ errors }, 'request from zarinpal `pg/v4/payment/verify.json` endpoint, responded with errors')
                return false
            }

            return { refId: ref_id.toString(), cardNumber: card_pan, cardNumberHash: card_hash }
        } catch (error) {
            log.error({ error }, 'verifying payment failed with error')
            return false
        }
    }

    async reverse(params: any): Promise<boolean> {
        const log = getLogger().child({ step: 'reverse' });

        try {
            const { authority } = await runWithLogger(log, () => validate(reverseSchema, params))

            const result = await httpsRequest(
                { host: `${this.baseEndpoint.replace('https://', '')}`, path: 'pg/v4/payment/reverse.json', method: 'post', headers: { 'content-type': 'application/json', accept: 'application/json' } },
                JSON.stringify({
                    // merchant_id: this.merchantId,
                    merchant_id: randomUUID(),
                    authority
                })
            )
            if (!result.response.statusCode || result.response.statusCode < 200 || result.response.statusCode >= 300) {
                log.error({ statusCode: result.response.statusCode }, 'sending request to zarinpal `pg/v4/payment/reverse.json` endpoint failed')
                return false
            }

            const responseData = JSON.parse(result.data) as {
                data: {
                    code: number,
                    message: string
                },
                errors: []
            }
            log.debug({ responseData })

            const { data: { code }, errors } = responseData

            if (!errors || errors.length !== 0 || code !== 100) {
                log.error({ errors }, 'request from zarinpal `pg/v4/payment/reverse.json` endpoint, responded with errors')
                return false
            }

            return true
        } catch (error) {
            log.error({ error }, 'reversing payment failed with error')
            return false
        }
    }
}
