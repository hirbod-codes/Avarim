export interface ISmtp {
    sendVerificationMessage(code: string, toEmail: string, locale: 'en' | 'fa'): Promise<boolean>;
    sendMessage(message: string, toEmail: string, locale: 'en' | 'fa'): Promise<boolean>;
}
