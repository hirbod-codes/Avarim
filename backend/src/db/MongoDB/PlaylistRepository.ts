import { AnyBulkWriteOperation, BulkWriteResult, ClientSession, Collection, Db, DeleteResult, InsertOneResult, ObjectId, WithId } from 'mongodb';
import { IDropable } from '../IDropable';
import { IRepository } from '../IRepository';
import { ISeedable } from '../ISeedable';
import { MongoDB } from './mongodb';
import { collectionName, Playlist, PlaylistUpdate } from '../models/Playlist';

class PlaylistRepository implements IRepository, ISeedable, IDropable {
    IRepository: 'IRepository' = 'IRepository';
    ISeedable: 'ISeedable' = 'ISeedable';
    IDropable: 'IDropable' = 'IDropable';

    private session: ClientSession | undefined = undefined
    private static collection: Collection<Playlist> | undefined = undefined

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

        if (indexes.find(i => i.name === 'name') === undefined)
            await db.createIndex(collectionName, { name: 1 }, { unique: true, name: 'name' })

        if (indexes.find(i => i.name === 'userId') === undefined)
            await db.createIndex(collectionName, { userId: 1 }, { name: 'userId' })

        if (indexes.find(i => i.name === 'createdAt') === undefined)
            await db.createIndex(collectionName, { createdAt: -1 }, { name: 'createdAt' })

        if (indexes.find(i => i.name === 'updatedAt') === undefined)
            await db.createIndex(collectionName, { updatedAt: -1 }, { name: 'updatedAt' })

        PlaylistRepository.collection = (await MongoDB.getDb()).collection<Playlist>(collectionName)
    }

    async dropCollection(db: Db): Promise<void> {
        await db.dropCollection(collectionName)
    }

    async insert(playlist: Playlist): Promise<InsertOneResult> {
        return await PlaylistRepository.collection!.insertOne({ ...playlist, updatedAt: Date.now(), createdAt: Date.now() }, { session: this.session })
    }

    async get(id: string): Promise<WithId<Playlist>> {
        return (await PlaylistRepository.collection!.find({ _id: ObjectId.createFromHexString(id) }, { session: this.session }).toArray())[0]
    }

    async getByName(name: string): Promise<WithId<Playlist>> {
        return (await PlaylistRepository.collection!.find({ name }, { session: this.session }).toArray())[0]
    }

    async getMany(playlistIds: string[]): Promise<WithId<Playlist>[]> {
        return await PlaylistRepository.collection!.find({ _id: { $in: playlistIds.map(m => ObjectId.createFromHexString(m)) } }, { session: this.session }).toArray()
    }

    async getPage(skip: number, limit: number): Promise<Playlist[]> {
        return await PlaylistRepository.collection!.find({}, { session: this.session }).sort({ createdAt: -1 }).skip(skip).limit(limit).toArray()
    }

    async unsafeUpdate(playlistId: string, updates: PlaylistUpdate) {
        return await PlaylistRepository.collection!.updateOne({ _id: ObjectId.createFromHexString(playlistId) }, { $set: { ...updates, updatedAt: Date.now() } }, { session: this.session })
    }

    async delete(id: string): Promise<DeleteResult> {
        return await PlaylistRepository.collection!.deleteOne({ _id: ObjectId.createFromHexString(id) }, { session: this.session })
    }

    async deleteBulk(ids: string[]): Promise<BulkWriteResult> {
        const bulkWrites: AnyBulkWriteOperation<any>[] = ids.map(id => ({ deleteOne: { filter: { _id: ObjectId.createFromHexString(id) } } }))
        return await PlaylistRepository.collection!.bulkWrite(bulkWrites, { session: this.session })
    }
}

export default PlaylistRepository;