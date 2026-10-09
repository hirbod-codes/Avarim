import { ClientSession, Collection, Db, DeleteResult, InsertOneResult, ObjectId, UpdateResult, WithId } from 'mongodb';
import { IDropable } from '../IDropable';
import { IRepository } from '../IRepository';
import { ISeedable } from '../ISeedable';
import { collectionName, User, UserUpdate } from '../models/User';
import { MongoDB } from '../../db/MongoDB/mongodb';
import { Redis } from '../redis';

export class UserRepository implements IRepository, ISeedable, IDropable {
    IDropable: 'IDropable' = 'IDropable';
    IRepository: 'IRepository' = 'IRepository';
    ISeedable: 'ISeedable' = 'ISeedable';

    private session: ClientSession | undefined = undefined
    private static collection: Collection<User> | undefined = undefined

    private static USER_DATA_CACHE_TTL_SECONDS: number = 1_800;

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

        if (indexes.find(i => i.name === 'unique-username') === undefined)
            await db.createIndex(collectionName, { username: 1 }, { sparse: true, unique: true, name: 'unique-username' })

        if (indexes.find(i => i.name === 'unique-email') === undefined)
            await db.createIndex(collectionName, { email: 1 }, { sparse: true, unique: true, name: 'email' })

        if (indexes.find(i => i.name === 'unique-phoneNumber') === undefined)
            await db.createIndex(collectionName, { phoneNumber: 1 }, { sparse: true, unique: true, name: 'phoneNumber' })

        if (indexes.find(i => i.name === 'createdAt') === undefined)
            await db.createIndex(collectionName, { createdAt: -1 }, { name: 'createdAt' })

        if (indexes.find(i => i.name === 'updatedAt') === undefined)
            await db.createIndex(collectionName, { updatedAt: -1 }, { name: 'updatedAt' })

        UserRepository.collection = (await MongoDB.getDb()).collection<User>(collectionName)
    }

    async dropCollection(db: Db): Promise<void> {
        await db.dropCollection(collectionName)
    }

    async create(user: User): Promise<InsertOneResult | false> {
        try {
            return await UserRepository.collection!.insertOne(user, { session: this.session })
        } catch (err) {
            console.error(err)
            return false
        }
    }

    async getAdmins(): Promise<WithId<User>[] | false | undefined> {
        try {
            return await UserRepository.collection!.find({ role: 'admin' }, { session: this.session }).toArray()
        } catch (err) {
            console.error(err)
            return false
        }
    }

    async get(id: string): Promise<WithId<User> | false | undefined> {
        try {
            const redis = await Redis.getClient()

            const userJson = await redis.get(`${collectionName}:${id}`)
            if (userJson)
                return JSON.parse(userJson)

            const user = (await UserRepository.collection!.find({ _id: ObjectId.createFromHexString(id) }, { session: this.session }).toArray())[0]
            if (!user)
                return undefined

            await redis.set(`${collectionName}:${id}`, JSON.stringify(user), 'EX', UserRepository.USER_DATA_CACHE_TTL_SECONDS)

            return user
        } catch (err) {
            console.error(err)
            return false
        }
    }

    async getByUsername(username: string): Promise<WithId<User> | false | undefined> {
        try {
            return (await UserRepository.collection!.find({ username }, { session: this.session }).toArray())[0]
        } catch (err) {
            console.error(err)
            return false
        }
    }

    async getByEmail(email: string): Promise<WithId<User> | false | undefined> {
        try {
            return (await UserRepository.collection!.find({ email }, { session: this.session }).toArray())[0]
        } catch (err) {
            console.error(err)
            return false
        }
    }

    async getByPhoneNumber(phoneNumber: string): Promise<WithId<User> | false | undefined> {
        try {
            return (await UserRepository.collection!.find({ phoneNumber }, { session: this.session }).toArray())[0]
        } catch (err) {
            console.error(err)
            return false
        }
    }

    getTemporaryAvatarFromCursor(fromTsMs: number) {
        return UserRepository.collection!.find({ $and: [{ updatedAt: { $gte: fromTsMs } }, { $or: [{ temporaryAvatar: true }, { deletionQueued: true }] }] }, { session: this.session })
    }

    async updateRefreshToken(id: string, refreshToken: string) {
        try {
            const redis = await Redis.getClient()

            const user = await UserRepository.collection!.findOneAndUpdate({ _id: ObjectId.createFromHexString(id) }, { $set: { refreshToken: refreshToken } }, { session: this.session })
            if (!user)
                return false

            await redis.set(`${collectionName}:${id}`, JSON.stringify(user), 'EX', UserRepository.USER_DATA_CACHE_TTL_SECONDS)

            return true
        } catch (err) {
            console.error(err)
            return false
        }
    }

    async updateAvatarKey(id: string, avatarKey: string) {
        try {
            const redis = await Redis.getClient()

            const user = await UserRepository.collection!.findOneAndUpdate({ _id: ObjectId.createFromHexString(id) }, { $set: { avatarKey, updatedAt: Date.now() } }, { session: this.session })
            if (!user)
                return false

            await redis.set(`${collectionName}:${id}`, JSON.stringify(user), 'EX', UserRepository.USER_DATA_CACHE_TTL_SECONDS)

            return true
        } catch (err) {
            console.error(err)
            return false
        }
    }

    async unsafeUpdate(id: string, updates: UserUpdate) {
        try {
            const redis = await Redis.getClient()

            const user = await UserRepository.collection!.findOneAndUpdate({ _id: ObjectId.createFromHexString(id) }, { $set: { ...updates, updatedAt: Date.now() } }, { session: this.session })
            if (!user)
                return false

            await redis.set(`${collectionName}:${id}`, JSON.stringify(user), 'EX', UserRepository.USER_DATA_CACHE_TTL_SECONDS)

            return true
        } catch (err) {
            console.error(err)
            return false
        }
    }
}
