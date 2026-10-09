import { Db } from "mongodb";

export interface ISeedable {
    ISeedable: 'ISeedable';

    /**
     * calling this method multiple times does not add to the number of documents in the collection (use count parameter instead).
     * @param count number of documents in the collection after seed operation.
     */
    seed(count?: number): Promise<void>;
}

export function isISeedable(arg: any): arg is ISeedable {
    return arg && arg.ISeedable === 'ISeedable'
}
