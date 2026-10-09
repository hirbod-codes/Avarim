import { smsProvider } from "../../configs";
import { IOtp } from "./IOtp";
import { Melipayamak } from "./providers/melipayamak";

export class OtpFactory {
    static instantiate(): IOtp {
        switch (smsProvider.identifier) {
            case 'melipayamak':
                return new Melipayamak({
                    baseEndpoint: smsProvider.melipayamak.baseEndpoint!,
                    username: smsProvider.melipayamak.username!,
                    password: smsProvider.melipayamak.apiKey!,
                    from: smsProvider.melipayamak.from!,
                    verificationMessageReferenceAddress: smsProvider.melipayamak.verificationMessageReferenceAddress!
                })

            default:
                throw new Error('UNSUPPORTED_SMS_PROVIDER')
        }
    }
}
