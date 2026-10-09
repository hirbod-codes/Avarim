import { ClientSession, Collection, Db, DeleteResult, InsertOneResult, ObjectId } from 'mongodb';
import { IDropable } from '../IDropable';
import { IRepository } from '../IRepository';
import { ISeedable } from '../ISeedable';
import { collectionName, schemaVersion } from '../models/InvalidTokens';
import { MongoDB } from '../../db/MongoDB/mongodb';
import { InvalidToken } from '../models/InvalidTokens';

export class InvalidTokensRepository implements IRepository, ISeedable, IDropable {
    IDropable: 'IDropable' = 'IDropable';
    IRepository: 'IRepository' = 'IRepository';
    ISeedable: 'ISeedable' = 'ISeedable';

    private session: ClientSession | undefined = undefined
    private static collection: Collection<InvalidToken> | undefined = undefined

    seed(count?: number): Promise<void> {
        throw new Error('Method not implemented.');
    }

    setTransactionSession(session?: ClientSession): void {
        this.session = session
    }

    unsetTransactionSession(): void {
        this.session = undefined
    }

    async addCollection(db: Db): Promise<void> {
        if (!(await db.listCollections().toArray()).map(e => e.name).includes(collectionName))
            await db.createCollection(collectionName)

        const indexes = await db.collection(collectionName).indexes()

        if (indexes.find(i => i.name === 'unique-token') === undefined)
            await db.createIndex(collectionName, { token: 1 }, { unique: true, name: 'unique-token' })

        InvalidTokensRepository.collection = (await MongoDB.getDb()).collection<InvalidToken>(collectionName)
    }

    async dropCollection(db: Db): Promise<void> {
        await db.dropCollection(collectionName)
    }

    async create(token: string): Promise<InsertOneResult> {
        return await InvalidTokensRepository.collection!.insertOne({ token, schemaVersion })
    }

    async get(id: string) {
        try {
            return (await InvalidTokensRepository.collection!.find({ _id: ObjectId.createFromHexString(id) }).toArray())[0]
        } catch (err) {
            console.error(err)
            return false
        }
    }

    async delete(id: string): Promise<DeleteResult> {
        return await InvalidTokensRepository.collection!.deleteOne({ _id: ObjectId.createFromHexString(id) })
    }
}
