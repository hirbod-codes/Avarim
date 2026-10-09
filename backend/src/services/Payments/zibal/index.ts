import { httpsRequest } from "../../../utils";
import { getLogger, runWithLogger } from "../../../observability/requestLoggerContext";
import { validate } from "../../../lib";
import { verifySchema, reverseSchema } from "./schemas";

export class Zibal implements IPay {
    baseEndpoint: string
    merchantId: string

    constructor(baseEndpoint: string, merchantId: string) {
        this.merchantId = merchantId
        this.baseEndpoint = baseEndpoint
    }

    async request(amount: number, callbackUrl: string) {
        const log = getLogger().child({ step: 'request payment' });

        try {
            const result = await httpsRequest(
                { host: `${this.baseEndpoint.replace('https://', '')}`, path: '/request/lazy', method: 'post', headers: { 'content-type': 'application/json', accept: 'application/json' } },
                JSON.stringify({
                    merchant: this.merchantId,
                    amount,
                    callbackUrl: callbackUrl,
                    description: 'Plan payment',
                    feeMode: 0
                })
            )
            if (!result.response.statusCode || result.response.statusCode < 200 || result.response.statusCode >= 300) {
                log.error({ statusCode: result.response.statusCode, data: result.data }, 'sending request to zibal `/request/lazy` endpoint failed')
                return false
            }

            const data = JSON.parse(result.data) as {
                trackId: string,
                result: number,
                message: string
            }
            log.debug({ data })

            const { result: resultCode, trackId } = data

            if (resultCode !== 100) {
                log.error({ resultCode }, 'request from zibal `/request/lazy` endpoint, responded with errors')
                return false
            }

            log.info('response from zibal `/request/lazy` received successfully')
            return { redirectUrl: `${this.baseEndpoint}/start/${trackId}` }
        } catch (err) {
            log.error({ err }, 'requesting payment failed with error')
            return false
        }
    }

    async verify(params: any) {
        const log = getLogger().child({ step: 'verify payment' });

        try {
            const responseData = await this.sendVerificationRequest(params)
            log.debug({ responseData })
            if (responseData == false) return false;

            const { result, status, refNumber } = responseData

            if (result !== 100 || (status !== 1 && status !== 2)) {
                log.error({ result, status }, 'request from zibal `verify` endpoint, responded with errors')
                return false
            }

            log.info('response from zibal `verify` received successfully')
            return { refId: refNumber }
        } catch (err) {
            log.error({ err }, 'verifying payment failed with error')
            return false
        }
    }

    async isPreviouslyVerified(params: any) {
        const log = getLogger().child({ step: 'verify payment' });

        try {
            const responseData = await this.sendVerificationRequest(params)
            log.debug({ responseData })
            if (responseData == false) return false;

            const { message } = responseData

            // typo is comes from provider side
            if(message === 'previously verifed') return true

            return false
        } catch (err) {
            log.error({ err }, 'verifying payment failed with error')
            return false
        }
    }

    private async sendVerificationRequest(params: any): Promise<false | { result: number, status: number, refNumber: number, message?: string }> {
        const log = getLogger().child({ step: 'Send verification request' });

        try {
            const { trackId } = await runWithLogger(log, () => validate(verifySchema, params))
            log.debug({ trackId })

            const zibalResult = await httpsRequest(
                { host: `${this.baseEndpoint.replace('https://', '')}`, path: '/verify', method: 'post', headers: { 'content-type': 'application/json', accept: 'application/json' } },
                JSON.stringify({
                    merchant: this.merchantId,
                    trackId
                })
            )
            if (!zibalResult.response.statusCode || zibalResult.response.statusCode < 200 || zibalResult.response.statusCode >= 300) {
                log.error({ statusCode: zibalResult.response.statusCode, data: zibalResult.data }, 'sending request to zibal `verify` endpoint failed')
                return false
            }

            const responseData = JSON.parse(zibalResult.data) as {
                result: number,
                status: number,
                refNumber: number,
                message?: string
            }
            log.debug({ responseData })

            return responseData
        } catch (err) {
            log.error({ err }, 'verifying payment failed with error')
            return false
        }
    }

    async reverse(params: any): Promise<boolean> {
        const log = getLogger().child({ step: 'reverse' });

        try {
            const { trackId } = await runWithLogger(log, () => validate(reverseSchema, params))

            const result = await httpsRequest(
                { host: `${this.baseEndpoint.replace('https://', '')}`, path: 'pg/v4/payment/reverse.json', method: 'post', headers: { 'content-type': 'application/json', accept: 'application/json' } },
                JSON.stringify({
                    merchant: this.merchantId,
                    trackId
                })
            )
            if (!result.response.statusCode || result.response.statusCode < 200 || result.response.statusCode >= 300) {
                log.error({ statusCode: result.response.statusCode, data: result.data }, 'sending request to zibal `pg/v4/payment/reverse.json` endpoint failed')
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
                log.error({ errors }, 'request from zibal `pg/v4/payment/reverse.json` endpoint, responded with errors')
                return false
            }

            return true
        } catch (err) {
            log.error({ err }, 'reversing payment failed with error')
            return false
        }
    }
}
