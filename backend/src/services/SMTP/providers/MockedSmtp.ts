import { getLogger, runWithLogger } from "../../../observability/requestLoggerContext";
import { ISmtp } from "../ISmtp";

export class MockedSmtp implements ISmtp {
    async sendVerificationMessage(code: string, toEmail: string, locale: "en" | "fa"): Promise<boolean> {
        const log = getLogger().child({ step: 'sendVerificationMessage' });

        log.debug({ code, toEmail, locale })

        return await runWithLogger(log, () => this.sendMessage(code, toEmail, locale))
    }

    async sendMessage(message: string, toEmail: string, locale: "en" | "fa"): Promise<boolean> {
        const log = getLogger().child({ step: 'sendMessage' });

        log.debug({ message, toEmail, locale })

        return true;
    }
}
