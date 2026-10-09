import { ClientSession, Db } from "mongodb";

export interface IRepository {
    IRepository: 'IRepository';

    setTransactionSession(session?: ClientSession): void;
    unsetTransactionSession(): void;
    addCollection(db: Db): Promise<void>;
}

export function isIRepository(arg: any): arg is IRepository {
    return arg && arg.IRepository === 'IRepository'
}
