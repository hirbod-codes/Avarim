import { AnyBulkWriteOperation, BulkWriteResult, ClientSession, Collection, Db, DeleteResult, InsertOneResult, ObjectId, WithId } from 'mongodb';
import { IDropable } from '../IDropable';
import { IRepository } from '../IRepository';
import { ISeedable } from '../ISeedable';
import { MongoDB } from './mongodb';
import { collectionName, Artist, ArtistUpdate } from '../models/Artist';

class ArtistRepository implements IRepository, ISeedable, IDropable {
    IRepository: 'IRepository' = 'IRepository';
    ISeedable: 'ISeedable' = 'ISeedable';
    IDropable: 'IDropable' = 'IDropable';

    private session: ClientSession | undefined = undefined
    private static collection: Collection<Artist> | undefined = undefined

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

        if (indexes.find(i => i.name === 'createdAt') === undefined)
            await db.createIndex(collectionName, { createdAt: -1 }, { name: 'createdAt' })

        if (indexes.find(i => i.name === 'updatedAt') === undefined)
            await db.createIndex(collectionName, { updatedAt: -1 }, { name: 'updatedAt' })

        ArtistRepository.collection = (await MongoDB.getDb()).collection<Artist>(collectionName)
    }

    async dropCollection(db: Db): Promise<void> {
        await db.dropCollection(collectionName)
    }

    async insert(artist: Artist): Promise<InsertOneResult> {
        return await ArtistRepository.collection!.insertOne({ ...artist, updatedAt: Date.now(), createdAt: Date.now() }, { session: this.session })
    }

    async get(id: string): Promise<WithId<Artist>> {
        return (await ArtistRepository.collection!.find({ _id: ObjectId.createFromHexString(id) }, { session: this.session }).toArray())[0]
    }

    getFromCursor(fromTsMs: number) {
        return ArtistRepository.collection!.find({ deletionQueued: { $ne: true }, temporary: false, updatedAt: { $gte: fromTsMs } }, { session: this.session })
    }

    async getByName(name: string): Promise<WithId<Artist>> {
        return (await ArtistRepository.collection!.find({ name }, { session: this.session }).toArray())[0]
    }

    async getMany(artistIds: string[]): Promise<WithId<Artist>[]> {
        return await ArtistRepository.collection!.find({ _id: { $in: artistIds.map(m => ObjectId.createFromHexString(m)) } }, { session: this.session }).toArray()
    }

    async getAlbum(artistIds: string[]): Promise<WithId<Artist>[]> {
        return await ArtistRepository.collection!.find({ _id: { $in: artistIds.map(m => ObjectId.createFromHexString(m)) } }, { session: this.session }).toArray()
    }

    async getPage(skip: number, limit: number): Promise<Artist[]> {
        return await ArtistRepository.collection!.find({}, { session: this.session }).sort({ createdAt: -1 }).skip(skip).limit(limit).toArray()
    }

    getDeletablesAvatarFromCursor(fromTsMs: number) {
        return ArtistRepository.collection!.find({ $and: [{ updatedAt: { $gte: fromTsMs } }, { $or: [{ temporaryBanner: true }, { temporaryAvatar: true }, { deletionQueued: true }] }] }, { session: this.session })
    }

    async unsafeUpdate(artistId: string, updates: ArtistUpdate) {
        return await ArtistRepository.collection!.updateOne({ _id: ObjectId.createFromHexString(artistId) }, { $set: { ...updates, updatedAt: Date.now() } }, { session: this.session })
    }

    async delete(id: string): Promise<DeleteResult> {
        return await ArtistRepository.collection!.deleteOne({ _id: ObjectId.createFromHexString(id) }, { session: this.session })
    }

    async deleteBulk(ids: string[]): Promise<BulkWriteResult> {
        const bulkWrites: AnyBulkWriteOperation<any>[] = ids.map(id => ({ deleteOne: { filter: { _id: ObjectId.createFromHexString(id) } } }))
        return await ArtistRepository.collection!.bulkWrite(bulkWrites, { session: this.session })
    }
}

export default ArtistRepository;