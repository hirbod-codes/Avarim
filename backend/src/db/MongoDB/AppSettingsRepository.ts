import { ClientSession, Collection, Db, WithId } from 'mongodb';
import { IDropable } from '../IDropable';
import { IRepository } from '../IRepository';
import { ISeedable } from '../ISeedable';
import { collectionName, AppSettings, AppSettingsUpdate, AppSettingsKey } from '../models/AppSettings';
import { MongoDB } from '../../db/MongoDB/mongodb';
import { Redis } from '../redis';

export default class AppSettingsRepository implements IRepository, ISeedable {
    IRepository: 'IRepository' = 'IRepository';
    ISeedable: 'ISeedable' = 'ISeedable';

    private session: ClientSession | undefined = undefined
    private static collection: Collection<AppSettings> | undefined = undefined

    // shorter than USER_DATA_CACHE_TTL_SECONDS (1800s) since settings are
    // admin-toggled and should propagate reasonably quickly
    private static SETTINGS_CACHE_TTL_SECONDS: number = 300;

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

        if (indexes.find(i => i.name === 'unique-key') === undefined)
            await db.createIndex(collectionName, { key: 1 }, { unique: true, name: 'unique-key' })

        AppSettingsRepository.collection = (await MongoDB.getDb()).collection<AppSettings>(collectionName)
    }

    async getByKey(key: AppSettings['key']): Promise<false | undefined | WithId<AppSettings>> {
        try {
            const redis = await Redis.getClient()
            const cacheKey = `${collectionName}:${key}`

            const cached = await redis.get(cacheKey)
            if (cached)
                return JSON.parse(cached)

            const doc = (await AppSettingsRepository.collection!.find({ key }).toArray())[0]
            if (!doc)
                return undefined

            await redis.set(cacheKey, JSON.stringify(doc), 'EX', AppSettingsRepository.SETTINGS_CACHE_TTL_SECONDS)

            return doc
        } catch (err) {
            console.error(err)
            return false
        }
    }

    /**
     * Upserts by `key` and invalidates the cache entry rather than trying to
     * update it in place, so the next getByKey() re-reads from Mongo.
     */
    async upsertByKey(key: AppSettingsKey, updates: Partial<AppSettingsUpdate>): Promise<boolean> {
        try {
            const redis = await Redis.getClient()

            // ATTENTION: findOneAndUpdate defaults to returning the document before the update was applied (and null on a fresh upsert, since there was no "before" document).
            // Therefore it's not used to update the redis key(hence avoiding the extra roundtrip to mongodb to read the new app setting)
            // Updating the redis record is also subject to race condition(if two admin update at the same time)
            const appSettings = await AppSettingsRepository.collection!.findOneAndUpdate(
                { key },
                {
                    $set: { ...updates, key, updatedAt: Date.now() },
                    $setOnInsert: { createdAt: Date.now() },
                },
                { upsert: true, session: this.session }
            )

            await redis.del(`${collectionName}:${key}`)

            return true
        } catch (err) {
            console.error(err)
            return false
        }
    }
}
