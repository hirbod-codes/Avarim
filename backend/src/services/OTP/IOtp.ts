export interface IOtp {
    sendVerificationMessage(code: string, toPhoneNumber: string, locale: 'en' | 'fa'): Promise<boolean>;
    sendMessage(message: string, toPhoneNumber: string, locale: 'en' | 'fa'): Promise<boolean>;
}
