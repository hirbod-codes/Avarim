# implementation overview

## controllers

### to purchase a plan

fetch and check if more than one active subscription exist
check if the active subscription is expired
fetching business plans
resolving currency and payment method and callback url
check if the currency doesn't match
calculating price
deleting old subscriptions with 'paymentNotCompleted' status
creating temporary subscription with status 'paymentNotCompleted'
storing the created subscription in session
requesting payment

1. validation
2. fetch and check if any active subscription exist
3. fetching business plans
4. resolving currency and payment method and `callback url`
5. calculating price
6. deleting old subscriptions with 'paymentNotCompleted' status
7. creating temporary subscription with status 'paymentNotCompleted'
8. storing the created subscription in session for 30 minutes
9. requesting payment
10. sending redirect url to user, so that user visit the payment page
11. user is redirected to `callback url` after payment is finished
12. `callback url` endpoint then does payment verification

### to renewal a plan

plan renewal is just another upgrade, same plan title, new `subscriptionDueTSMS`

### to upgrade to a another plan

1. fetch and check if more than one active subscription exist
2. validating parameters according to active subscription
3. check if the active subscription with same title exist, if it's expired or if the currency doesn't match
4. fetching business plans
5. resolving currency and payment method
6. calculating price
   1. uses `Subscription['currentPeriodEnd']` and `nowTS` time difference to calculate how much user's unused plan worths
   2. uses request body input `subscriptionDueTSMS` and `nowTS` time difference to calculate how much user needs to pay according to requested plan and `subscriptionDueTSMS`
   3. subtracts these unused price from the requested due price to get the `totalPrice`
   4. if current active subscription has a negative `Subscription['payment']['amount']` field, it is then subtracted from `totalPrice`
      1. if `totalPrice` is negative we are in dept to user
         1. the negative amount is then stored as is in subscription `Subscription['payment']['amount']` amount field to be accounted for in future payments
         2. the subscription is then created with `active` status
      2. if zero
         1. the subscription is then created with `active` status
7. deleting old subscriptions with 'paymentNotCompleted' status
8. creating temporary subscription with status 'paymentNotCompleted'
9. storing the created subscription in session
10. requesting payment
11. sending redirect url to user, so that user visit the payment page
12. user is redirected to `callback url` after payment is finished
13. `callback url` endpoint then does payment verification

### payment verification

1. fetching the subscription
2. updating subscription status to 'paymentNotVerified'
   1. this section is added in case, the process is interrupted exactly after verifying payment section, the situation is then handled in a cron job scheduled when starting this server process
3. verifying payment
4. remove user's old active subscriptions
5. updating subscription status to 'active'

if any step fails:

1. cancelling, updating subscription status to 'canceled'
2. reversing payment if already happened(failure can happen after verification)

## models

Usage

Plan

Subscription
type Subscription = {
    schemaVersion?: string | undefined;
    _id?: string | ObjectId | undefined;
    createdAt?: number | undefined;
    updatedAt?: number | undefined;
    processorSubscriptionId?: string | undefined;
    paymentAuthority?: string | undefined;
    completedAt?: number | undefined;
    verifiedAt?: number | undefined;
    refId?: string | undefined;
    cardNumber?: string | undefined;
    cardNumberHash?: string | undefined;
    planTitle: string;
    status: 'active', 'canceled', 'trial', 'paymentNotVerified', 'paymentNotCompleted', 'inDebtToUser';
    userId: string;
    duration: "month" | "year";
    currentPeriodEnd: number;
    paymentMethod: "zarinpal" | "paypal" | "bitcoin" | "zibal";
    price: {
        currency: NonNullable<"IRR" | "USD" | "EUR" | "BTC" | "ETH" | undefined>;
        amount: number;
    };
    privileges: {
        categoriesPerNestedLevel: number;
        nestedLevels: number;
        cardsPerCategory: number;
        contentsPerCardSide: number;
        storageBytes: number;
        valuePerContent: {
            string: number;
            richText: number;
            image: number;
            audio: number;
            video: number;
        };
        allowedContentTypes: {
            string: NonNullable<boolean | undefined>;
            richText: NonNullable<boolean | undefined>;
            image: NonNullable<boolean | undefined>;
            audio: NonNullable<boolean | undefined>;
            video: NonNullable<boolean | undefined>;
        };
    };
    currentPeriodEnd: number;
}
