import { Db } from "mongodb";

export interface IDropable {
    IDropable: 'IDropable';

    dropCollection(db: Db): Promise<void>;
}

export function isIDropable(arg: any): arg is IDropable {
    return arg && arg.IDropable === 'IDropable'
}
