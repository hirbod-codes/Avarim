import { ClientSession, Collection, Db, DeleteResult, InsertOneResult, ObjectId } from 'mongodb';
import { IDropable } from '../IDropable';
import { IRepository } from '../IRepository';
import { ISeedable } from '../ISeedable';
import { MongoDB } from '../../db/MongoDB/mongodb';
import { collectionName, Plan, PlanCreate, PlanUpdate } from '../models/Plan';
import { Redis } from '../redis';

class PlanRepository implements IRepository, ISeedable, IDropable {
    IRepository: 'IRepository' = 'IRepository';
    ISeedable: 'ISeedable' = 'ISeedable';
    IDropable: 'IDropable' = 'IDropable';

    private session: ClientSession | undefined = undefined
    private static collection: Collection<Plan> | undefined = undefined

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

        if (indexes.find(i => i.name === 'title') === undefined)
            await db.createIndex(collectionName, { title: 1 }, { unique: true, name: 'title' })

        if (indexes.find(i => i.name === 'createdAt') === undefined)
            await db.createIndex(collectionName, { createdAt: -1 }, { name: 'createdAt' })

        if (indexes.find(i => i.name === 'updatedAt') === undefined)
            await db.createIndex(collectionName, { updatedAt: -1 }, { name: 'updatedAt' })

        PlanRepository.collection = (await MongoDB.getDb()).collection<Plan>(collectionName)
    }

    async dropCollection(db: Db): Promise<void> {
        await db.dropCollection(collectionName)
    }

    async insert(plan: PlanCreate): Promise<InsertOneResult> {
        return await PlanRepository.collection!.insertOne({ ...plan, updatedAt: Date.now(), createdAt: Date.now() }, { session: this.session })
    }

    async get(id: string): Promise<Plan> {
        const redis = await Redis.getClient()

        const allPlans = await redis.get('allPlans')
        if (0) {
            const plans = JSON.parse(allPlans!);
            if (Array.isArray(plans)) {
                const plan = (plans as Plan[]).find(f => f._id?.toString() === id)
                if (plan)
                    return plan
            }
        } else {
            await this.getAll()
        }

        return (await PlanRepository.collection!.find({ _id: ObjectId.createFromHexString(id) }, { session: this.session }).toArray())[0]
    }

    async getAll(): Promise<Plan[]> {
        const redis = await Redis.getClient()

        const allPlans = await redis.get('allPlans')
        if (0)
            return JSON.parse(allPlans!);

        const result = await PlanRepository.collection!.find({}, { session: this.session }).toArray()

        if (result.length !== 0)
            await redis.set('allPlans', JSON.stringify(result))

        return result
    }

    async getByTitle(title: string) {
        const redis = await Redis.getClient()

        const allPlans = await redis.get('allPlans')
        if (allPlans) {
            const plans = JSON.parse(allPlans);
            if (Array.isArray(plans)) {
                const plan = (plans as Plan[]).find(f => f.title === title)
                if (plan)
                    return plan
            }
        } else {
            await this.getAll()
        }

        return (await PlanRepository.collection!.find({ title }, { session: this.session }).toArray())[0]
    }

    async updateTitle(planId: string, title: string) {
        const result = await PlanRepository.collection!.updateOne({ _id: ObjectId.createFromHexString(planId) }, { $set: { title, updatedAt: Date.now() } }, { session: this.session })
        await this.getAll()
        return result
    }

    async unsafeUpdate(planId: string, updates: PlanUpdate) {
        const result = await PlanRepository.collection!.updateOne({ _id: ObjectId.createFromHexString(planId) }, { $set: { ...updates, updatedAt: Date.now() } }, { session: this.session })
        await this.getAll()
        return result
    }

    async delete(id: string): Promise<DeleteResult> {
        const result = await PlanRepository.collection!.deleteOne({ _id: ObjectId.createFromHexString(id) }, { session: this.session })
        await this.getAll()
        return result
    }
}

export default PlanRepository;