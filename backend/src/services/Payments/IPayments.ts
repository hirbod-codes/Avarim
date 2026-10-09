interface IPay {
    request(amount: number, callbackUrl: string): Promise<false | { redirectUrl: string }>
    verify(params: any): Promise<false | (any & { refId: string })>
    isPreviouslyVerified(params: any): Promise<boolean>
    reverse(params: any): Promise<boolean>
}