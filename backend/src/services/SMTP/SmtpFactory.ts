import { isProduction, smsProvider } from "../../configs";
import { ISmtp } from "./ISmtp";
import { MockedSmtp } from "./providers/MockedSmtp";

export class SmtpFactory {
    static instantiate(): ISmtp {
        // if (isProduction)
        //     throw new Error('UNSUPPORTED_SMTP_PROVIDER')

        return new MockedSmtp()
    }
}
