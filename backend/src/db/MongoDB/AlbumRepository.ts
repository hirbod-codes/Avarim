import { AnyBulkWriteOperation, BulkWriteResult, ClientSession, Collection, Db, DeleteResult, InsertOneResult, ObjectId, WithId } from 'mongodb';
import { IDropable } from '../IDropable';
import { IRepository } from '../IRepository';
import { ISeedable } from '../ISeedable';
import { MongoDB } from './mongodb';
import { collectionName, Album, AlbumUpdate } from '../models/Album';

class AlbumRepository implements IRepository, ISeedable, IDropable {
    IRepository: 'IRepository' = 'IRepository';
    ISeedable: 'ISeedable' = 'ISeedable';
    IDropable: 'IDropable' = 'IDropable';

    private session: ClientSession | undefined = undefined
    private static collection: Collection<Album> | undefined = undefined

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

        if (indexes.find(i => i.name === 'userId') === undefined)
            await db.createIndex(collectionName, { userId: 1 }, { name: 'userId' })

        if (indexes.find(i => i.name === 'createdAt') === undefined)
            await db.createIndex(collectionName, { createdAt: -1 }, { name: 'createdAt' })

        if (indexes.find(i => i.name === 'updatedAt') === undefined)
            await db.createIndex(collectionName, { updatedAt: -1 }, { name: 'updatedAt' })

        AlbumRepository.collection = (await MongoDB.getDb()).collection<Album>(collectionName)
    }

    async dropCollection(db: Db): Promise<void> {
        await db.dropCollection(collectionName)
    }

    async create(album: Album): Promise<InsertOneResult> {
        return await AlbumRepository.collection!.insertOne({ ...album, updatedAt: Date.now(), createdAt: Date.now() }, { session: this.session })
    }

    async get(id: string): Promise<WithId<Album>> {
        return (await AlbumRepository.collection!.find({ _id: ObjectId.createFromHexString(id) }, { session: this.session }).toArray())[0]
    }

    async getByName(name: string): Promise<WithId<Album>> {
        return (await AlbumRepository.collection!.find({ name }, { session: this.session }).toArray())[0]
    }

    async unsafeUpdate(albumId: string, updates: AlbumUpdate) {
        return await AlbumRepository.collection!.updateOne({ _id: ObjectId.createFromHexString(albumId) }, { $set: { ...updates, updatedAt: Date.now() } }, { session: this.session })
    }

    async delete(id: string): Promise<DeleteResult> {
        return await AlbumRepository.collection!.deleteOne({ _id: ObjectId.createFromHexString(id) }, { session: this.session })
    }

    async deleteBulk(ids: string[]): Promise<BulkWriteResult> {
        const bulkWrites: AnyBulkWriteOperation<any>[] = ids.map(id => ({ deleteOne: { filter: { _id: ObjectId.createFromHexString(id) } } }))
        return await AlbumRepository.collection!.bulkWrite(bulkWrites, { session: this.session })
    }

    async deleteTemporaries(): Promise<DeleteResult> {
        return await AlbumRepository.collection!.deleteMany({ temporary: true }, { session: this.session })
    }
}

export default AlbumRepository;