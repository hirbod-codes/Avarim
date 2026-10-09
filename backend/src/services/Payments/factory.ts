import { Zibal } from "./zibal";
import { isProduction, payments } from "../../configs";
import { Zarinpal } from "./zarinpal";

export class PaymentFactory {
    static instantiate(paymentMethod: string): IPay {
        switch (paymentMethod) {
            case 'zarinpal':
                return new Zarinpal(payments.zarinpal.url!, payments.zarinpal.merchantId!)

            case 'zibal':
                return new Zibal(payments.zibal.url!, isProduction ? payments.zibal.merchantId! : 'zibal')

            default:
                throw new Error('UNSUPPORTED_PAYMENT_METHOD')
        }
    }
}
