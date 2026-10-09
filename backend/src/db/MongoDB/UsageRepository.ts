import { ClientSession, Collection, Db, DeleteResult, InsertOneResult, ObjectId, UpdateResult, WithId } from 'mongodb';
import { IDropable } from '../IDropable';
import { IRepository } from '../IRepository';
import { ISeedable } from '../ISeedable';
import { MongoDB } from '../../db/MongoDB/mongodb';
import { collectionName, Usage, UsageCreate, UsageUpdate } from '../models/Usage';
import { Redis } from '../redis';

class UsageRepository implements IRepository, ISeedable, IDropable {
    IRepository: 'IRepository' = 'IRepository';
    ISeedable: 'ISeedable' = 'ISeedable';
    IDropable: 'IDropable' = 'IDropable';

    private session: ClientSession | undefined = undefined
    private static collection: Collection<Usage> | undefined = undefined

    private static USAGE_DATA_CACHE_TTL_SECONDS: number = 1_800;

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

        if (indexes.find(i => i.name === 'userId') === undefined)
            await db.createIndex(collectionName, { userId: 1 }, { unique: true, name: 'userId' })

        if (indexes.find(i => i.name === 'createdAt') === undefined)
            await db.createIndex(collectionName, { createdAt: -1 }, { name: 'createdAt' })

        if (indexes.find(i => i.name === 'updatedAt') === undefined)
            await db.createIndex(collectionName, { updatedAt: -1 }, { name: 'updatedAt' })

        UsageRepository.collection = (await MongoDB.getDb()).collection<Usage>(collectionName)
    }

    async dropCollection(db: Db): Promise<void> {
        await db.dropCollection(collectionName)
    }

    async insert(plan: UsageCreate): Promise<InsertOneResult> {
        return await UsageRepository.collection!.insertOne({ ...plan, updatedAt: Date.now(), createdAt: Date.now() }, { session: this.session })
    }

    async get(id: string): Promise<Usage> {
        return (await UsageRepository.collection!.find({ _id: ObjectId.createFromHexString(id) }, { session: this.session }).toArray())[0]
    }

    async getByUserId(userId: string): Promise<Usage | undefined> {
        const redis = await Redis.getClient()

        const userJson = await redis.get(`${collectionName}:userId:${userId}`)
        if (userJson)
            return JSON.parse(userJson)

        let usage = (await UsageRepository.collection!.find({ userId }, { session: this.session }).toArray())[0]

        if (!usage) {
            const result = await this.insert({ userId, storageBytes: 0 })

            if (!result.acknowledged)
                return undefined

            usage = (await UsageRepository.collection!.find({ userId }, { session: this.session }).toArray())[0]
        }

        await redis.set(`${collectionName}:userId:${userId}`, JSON.stringify(usage), 'EX', UsageRepository.USAGE_DATA_CACHE_TTL_SECONDS)

        return usage
    }

    async unsafeUpdateForUser(usageId: string, userId: string, updates: UsageUpdate) {
        const usage = await UsageRepository.collection!.findOneAndUpdate({ _id: ObjectId.createFromHexString(usageId), userId }, { $set: { ...updates, updatedAt: Date.now() } }, { session: this.session })

        const redis = await Redis.getClient()
        await redis.set(`${collectionName}:userId:${userId}`, JSON.stringify(usage), 'EX', UsageRepository.USAGE_DATA_CACHE_TTL_SECONDS)

        return usage
    }

    /**
     * @returns Return null if quota would be exceeded, WithId<Usage> otherwise.
     */
    async tryIncrementStorageQuota(userId: string, amount: number, limit: number): Promise<WithId<Usage> | null> {
        const usage = await UsageRepository.collection!.findOneAndUpdate({ userId, storageBytes: { $lte: limit - amount } }, { $inc: { storageBytes: amount }, $set: { updatedAt: Date.now() } }, { session: this.session })

        const redis = await Redis.getClient()
        await redis.set(`${collectionName}:userId:${userId}`, JSON.stringify(usage), 'EX', UsageRepository.USAGE_DATA_CACHE_TTL_SECONDS)

        return usage
    }

    async decrementStorageQuota(userId: string, amount: number): Promise<UpdateResult> {
        const usage = await UsageRepository.collection!.updateOne({ userId, storageBytes: { $gte: amount } }, { $inc: { storageBytes: -amount }, $set: { updatedAt: Date.now() } }, { session: this.session });

        const redis = await Redis.getClient()
        await redis.set(`${collectionName}:userId:${userId}`, JSON.stringify(usage), 'EX', UsageRepository.USAGE_DATA_CACHE_TTL_SECONDS)

        return usage
    }

    async delete(id: string) {
        const result = await UsageRepository.collection!.findOneAndDelete({ _id: ObjectId.createFromHexString(id) }, { session: this.session })
        if (result) {
            const redis = await Redis.getClient()
            await redis.del(`${collectionName}:userId:${result.userId}`)
        }
    }

    async findOneAndDeleteByUserId(id: string) {
        const result = await UsageRepository.collection!.findOneAndDelete({ userId: id }, { session: this.session })
        if (result) {
            const redis = await Redis.getClient()
            await redis.del(`${collectionName}:userId:${result.userId}`)
        }

        return result !== null && result !== undefined
    }

    async deleteByUserId(id: string) {
        const usage = await UsageRepository.collection!.findOne({ userId: id }, { session: this.session })
        if (usage) {
            const redis = await Redis.getClient()
            await redis.del(`${collectionName}:userId:${usage.userId}`)
        }

        return await UsageRepository.collection!.deleteOne({ userId: id }, { session: this.session })
    }
}

export default UsageRepository;