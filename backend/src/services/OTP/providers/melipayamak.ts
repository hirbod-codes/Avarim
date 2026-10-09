import { isProduction } from "../../../configs";
import { getLogger, runWithLogger } from "../../../observability/requestLoggerContext";
import { httpsRequest } from "../../../utils";
import { IOtp } from "../IOtp";

export class Melipayamak implements IOtp {
    private baseEndpoint: string
    private username: string
    private password: string
    private from: string
    private verificationMessageReferenceAddress: string

    constructor({ baseEndpoint, username, password, from, verificationMessageReferenceAddress }: { baseEndpoint: string, username: string, password: string, from: string, verificationMessageReferenceAddress: string }) {
        this.baseEndpoint = baseEndpoint
        this.username = username
        this.password = password
        this.from = from
        this.verificationMessageReferenceAddress = verificationMessageReferenceAddress
    }

    async sendVerificationMessage(code: string, toPhoneNumber: string, locale: 'en' | 'fa'): Promise<boolean> {
        const log = getLogger().child({ module: 'otp', step: 'sendVerificationMessage' });

        try {
            log.debug({ ...(isProduction ? {} : { code }), toPhoneNumber, locale })

            const message = locale === 'en'
                ? `Your verification code: 
${code}

لغو 11
`
                : `کد ورود شما: 
${code}

لغو 11
`

            return await runWithLogger(log, () => this.sendMessage(message, toPhoneNumber))
        } catch (error) {
            log.error({ error }, 'failed to send verification code')
            return false
        }
    }

    async sendMessage(message: string, toPhoneNumber: string): Promise<boolean> {
        const log = getLogger().child({ module: 'otp', step: 'sendMessage' });

        try {
            log.debug({ ...(isProduction ? {} : { message }), toPhoneNumber })

            const result = await httpsRequest({
                host: `${this.baseEndpoint.replace('https://', '')}`,
                path: '/api/SendSMS/SendSMS',
                method: 'post',
                headers: {
                    'Content-Type': 'application/json'
                }
            }, JSON.stringify({
                username: this.username,
                password: this.password,
                from: this.from,
                to: toPhoneNumber,
                text: message
            }))
            log.debug({ statusCode: result.response.statusCode })

            if (result.response.statusCode && result.response.statusCode > 199 && result.response.statusCode < 300) {
                const data = JSON.parse(result.data)
                log.debug({ data })
                if (data.RetStatus === 1) {
                    log.info('successfully sent verification code')
                    return true
                }
            }

            log.info('failed to send verification code')
            return false
        } catch (error) {
            log.error({ error }, 'failed to send verification code')
            return false
        }
    }
}
