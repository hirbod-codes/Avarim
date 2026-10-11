import { AnyBulkWriteOperation, BulkWriteResult, ClientSession, Collection, Db, DeleteResult, InsertOneResult, ObjectId, WithId } from 'mongodb';
import { IDropable } from '../IDropable';
import { IRepository } from '../IRepository';
import { ISeedable } from '../ISeedable';
import { MongoDB } from '../MongoDB/mongodb';
import { collectionName, Audio, AudioUpdate } from '../models/Audio';

class AudioRepository implements IRepository, ISeedable, IDropable {
    IRepository: 'IRepository' = 'IRepository';
    ISeedable: 'ISeedable' = 'ISeedable';
    IDropable: 'IDropable' = 'IDropable';

    private session: ClientSession | undefined = undefined
    private static collection: Collection<Audio> | undefined = undefined

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

        if (indexes.find(i => i.name === 'audioSha256') === undefined)
            await db.createIndex(collectionName, { 'technical.audioSha256': 1 }, { unique: true, name: 'audioSha256' })

        if (indexes.find(i => i.name === 'artists') === undefined)
            await db.createIndex(collectionName, { 'tags.artists': 1 }, { name: 'artists' })

        if (indexes.find(i => i.name === 'album') === undefined)
            await db.createIndex(collectionName, { 'tags.album': 1 }, { name: 'album' })

        if (indexes.find(i => i.name === 'createdAt') === undefined)
            await db.createIndex(collectionName, { createdAt: -1 }, { name: 'createdAt' })

        if (indexes.find(i => i.name === 'updatedAt') === undefined)
            await db.createIndex(collectionName, { updatedAt: -1 }, { name: 'updatedAt' })

        AudioRepository.collection = (await MongoDB.getDb()).collection<Audio>(collectionName)
    }

    async dropCollection(db: Db): Promise<void> {
        await db.dropCollection(collectionName)
    }

    async insert(audio: Audio): Promise<InsertOneResult> {
        return await AudioRepository.collection!.insertOne({ ...audio, updatedAt: Date.now(), createdAt: Date.now() }, { session: this.session })
    }

    async get(id: string): Promise<WithId<Audio>> {
        return (await AudioRepository.collection!.find({ deletionQueued: { $ne: true }, temporary: false, _id: ObjectId.createFromHexString(id) }, { session: this.session }).toArray())[0]
    }

    async getUnsafe(id: string): Promise<WithId<Audio>> {
        return (await AudioRepository.collection!.find({ _id: ObjectId.createFromHexString(id) }, { session: this.session }).toArray())[0]
    }

    async getByTitle(title: string): Promise<WithId<Audio>> {
        return (await AudioRepository.collection!.find({ deletionQueued: { $ne: true }, temporary: false, title }, { session: this.session }).toArray())[0]
    }

    async getByTitleUnsafe(title: string): Promise<WithId<Audio>> {
        return (await AudioRepository.collection!.find({ title }, { session: this.session }).toArray())[0]
    }

    async getByTitleByAudioSha256(title: string, audioSha256: string): Promise<WithId<Audio>> {
        return (await AudioRepository.collection!.find({ deletionQueued: { $ne: true }, temporary: false, title, 'technical.audioSha256': audioSha256 }, { session: this.session }).toArray())[0]
    }

    async getByAudioSha256(audioSha256: string) {
        return (await AudioRepository.collection!.find({ deletionQueued: { $ne: true }, temporary: false, 'technical.audioSha256': audioSha256 }, { session: this.session }).toArray())[0]
    }

    async getMany(audioIds: string[]): Promise<WithId<Audio>[]> {
        return await AudioRepository.collection!.find({ deletionQueued: { $ne: true }, temporary: false, _id: { $in: audioIds.map(m => ObjectId.createFromHexString(m)) } }, { session: this.session }).toArray()
    }

    async getByUserId(userId: string) {
        return await AudioRepository.collection!.find({ deletionQueued: { $ne: true }, temporary: false }, { session: this.session }).toArray()
    }

    async getPage(skip: number, limit: number): Promise<Audio[]> {
        return await AudioRepository.collection!.find({ deletionQueued: { $ne: true }, temporary: false }, { session: this.session }).sort({ createdAt: -1 }).skip(skip).limit(limit).toArray()
    }

    getFromCursor(fromTsMs: number) {
        return AudioRepository.collection!.find({ temporary: false, updatedAt: { $gte: fromTsMs } }, { session: this.session })
    }

    getTemporariesFromCursor(fromTsMs: number) {
        return AudioRepository.collection!.find({ $and: [{ updatedAt: { $gte: fromTsMs } }, { $or: [{ temporaryAvatar: true }, { deletionQueued: true }] }] }, { session: this.session })
    }

    async updateTitle(audioId: string, title: string) {
        return await AudioRepository.collection!.updateOne({ temporary: false, _id: ObjectId.createFromHexString(audioId) }, { $set: { title, updatedAt: Date.now() } }, { session: this.session })
    }

    async unsafeUpdate(audioId: string, updates: AudioUpdate) {
        return await AudioRepository.collection!.updateOne({ _id: ObjectId.createFromHexString(audioId) }, { $set: { ...updates, updatedAt: Date.now() } }, { session: this.session })
    }

    async delete(id: string): Promise<DeleteResult> {
        return await AudioRepository.collection!.deleteOne({ _id: ObjectId.createFromHexString(id) }, { session: this.session })
    }

    async deleteBulk(ids: string[]): Promise<BulkWriteResult> {
        const bulkWrites: AnyBulkWriteOperation<any>[] = ids.map(id => ({ deleteOne: { filter: { _id: ObjectId.createFromHexString(id) } } }))
        return await AudioRepository.collection!.bulkWrite(bulkWrites, { session: this.session })
    }

    async deleteForUser(id: string): Promise<DeleteResult> {
        return await AudioRepository.collection!.deleteOne({ _id: ObjectId.createFromHexString(id) }, { session: this.session })
    }

    async deleteTemporaries(): Promise<DeleteResult> {
        return await AudioRepository.collection!.deleteMany({ temporary: true }, { session: this.session })
    }
}

export default AudioRepository;