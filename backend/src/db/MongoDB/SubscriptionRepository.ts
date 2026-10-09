import { ClientSession, Collection, Db, DeleteResult, FindCursor, InsertOneResult, ObjectId, WithId } from 'mongodb';
import { IDropable } from '../IDropable';
import { IRepository } from '../IRepository';
import { ISeedable } from '../ISeedable';
import { MongoDB } from '../../db/MongoDB/mongodb';
import { collectionName, Subscription, SubscriptionCreate, SubscriptionUpdate } from '../models/Subscription';
import { Redis } from '../redis';
import { A_MONTH_IN_MILLISECONDS } from '../../lib';

class SubscriptionRepository implements IRepository, ISeedable, IDropable {
    IRepository: 'IRepository' = 'IRepository';
    ISeedable: 'ISeedable' = 'ISeedable';
    IDropable: 'IDropable' = 'IDropable';

    private session: ClientSession | undefined = undefined
    private static collection: Collection<Subscription> | undefined = undefined

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
            await db.createIndex(collectionName, { userId: 1 }, { unique: true, partialFilterExpression: { status: { $in: ['active', 'cancel'] } }, name: 'userId_active' })

        if (indexes.find(i => i.name === 'planTitle') === undefined)
            await db.createIndex(collectionName, { planTitle: 1 }, { name: 'planTitle' })

        if (indexes.find(i => i.name === 'createdAt') === undefined)
            await db.createIndex(collectionName, { createdAt: -1 }, { name: 'createdAt' })

        if (indexes.find(i => i.name === 'updatedAt') === undefined)
            await db.createIndex(collectionName, { updatedAt: -1 }, { name: 'updatedAt' })

        SubscriptionRepository.collection = (await MongoDB.getDb()).collection<Subscription>(collectionName)
    }

    async dropCollection(db: Db): Promise<void> {
        await db.dropCollection(collectionName)
    }

    async insert(plan: SubscriptionCreate): Promise<InsertOneResult> {
        return await SubscriptionRepository.collection!.insertOne({ ...plan, updatedAt: Date.now(), createdAt: Date.now() }, { session: this.session })
    }

    async get(id: string): Promise<WithId<Subscription>> {
        return (await SubscriptionRepository.collection!.find({ _id: ObjectId.createFromHexString(id) }, { session: this.session }).toArray())[0]
    }

    async getForUser(userId: string): Promise<WithId<Subscription>[]> {
        return await SubscriptionRepository.collection!.find({ userId }, { session: this.session }).toArray()
    }

    async getByStatusByTitleForUser(userId: string, status: Subscription['status'][], planTitle: string): Promise<WithId<Subscription>[]> {
        return await SubscriptionRepository.collection!.find({ userId, status: { $in: status }, planTitle }, { session: this.session }).toArray()
    }

    async getByStatusForUser(userId: string, status: Subscription['status'][]): Promise<WithId<Subscription>[]> {
        return await SubscriptionRepository.collection!.find({ userId, status: { $in: status } }, { session: this.session }).toArray()
    }

    async getByStatus(status: Subscription['status'][]): Promise<WithId<Subscription>[]> {
        return await SubscriptionRepository.collection!.find({ status: { $in: status } }, { session: this.session }).toArray()
    }

    async getCreatedBeforeByStatusCursor(status: Subscription['status'][], createdBeforeTSMS: number): Promise<FindCursor<WithId<Subscription>>> {
        return SubscriptionRepository.collection!.find({ createdAt: { $lte: createdBeforeTSMS }, status: { $in: status } }, { session: this.session })
    }

    async getUnhandledExpiredBeforeCursor(expiredBeforeTSMS: number): Promise<FindCursor<WithId<Subscription>>> {
        return SubscriptionRepository.collection!.find({ status: { $ne: 'expired' }, currentPeriodEnd: { $lte: expiredBeforeTSMS } }, { session: this.session })
    }

    async getActiveByUserId(userId: string): Promise<WithId<Subscription>[]> {
        const redis = await Redis.getClient()
        await redis.del(`${collectionName}:active:${userId}`)

        const subscription = await redis.get(`${collectionName}:active:${userId}`)
        if (subscription)
            return JSON.parse(subscription)

        const result = await SubscriptionRepository.collection!.find({ userId, status: { $in: ['active', 'trial'] } }, { session: this.session }).toArray()
        if (result)
            await redis.set(`${collectionName}:active:${userId}`, JSON.stringify(result), 'EX', A_MONTH_IN_MILLISECONDS / 1000)

        return result
    }

    async cancelByStatus(status: Subscription['status'][], hoursOld: number) {
        return await SubscriptionRepository.collection!.updateMany({ status: { $in: status }, createdAt: { $lte: Date.now() - (hoursOld * 60 * 60 * 1000) } }, { $set: { status: 'canceled', updatedAt: Date.now() } })
    }

    async inactivateForUser(userId: string) {
        const redis = await Redis.getClient()

        await redis.del(`${collectionName}:active:${userId}`)

        return await SubscriptionRepository.collection!.updateMany({ userId, status: { $in: ['active', 'trial'] } }, { $set: { status: 'canceled', updatedAt: Date.now() } }, { session: this.session })
    }

    async unsafeUpdate(subscriptionId: string, userId: string, updates: SubscriptionUpdate) {
        const redis = await Redis.getClient()

        await redis.del(`${collectionName}:active:${userId}`)

        return await SubscriptionRepository.collection!.updateOne({ _id: ObjectId.createFromHexString(subscriptionId), userId }, { $set: { ...updates, updatedAt: Date.now() } }, { session: this.session })
    }

    async deleteDanglingStatusForUser(userId: string): Promise<DeleteResult> {
        return await SubscriptionRepository.collection!.deleteMany({ userId, status: { $in: ['paymentNotCompleted', 'paymentNotVerified'] } }, { session: this.session })
    }

    async deleteByStatusForUser(userId: string, status: Subscription['status'][]): Promise<DeleteResult> {
        if (status.includes('active') || status.includes('trial')) {
            const redis = await Redis.getClient()

            await redis.del(`${collectionName}:active:${userId}`)
        }

        return await SubscriptionRepository.collection!.deleteMany({ userId, status: { $in: status } }, { session: this.session })
    }

    async delete(id: string): Promise<WithId<Subscription> | null | undefined> {
        const result = await SubscriptionRepository.collection!.findOneAndDelete({ _id: ObjectId.createFromHexString(id) }, { session: this.session })
        if (result) {
            const redis = await Redis.getClient()

            await redis.del(`${collectionName}:active:${result.userId}`)
        }

        return result
    }
}

export default SubscriptionRepository;
