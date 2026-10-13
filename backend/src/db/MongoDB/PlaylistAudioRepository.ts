import { AnyBulkWriteOperation, BulkWriteResult, ClientSession, Collection, Db, DeleteResult, InsertOneResult, ObjectId, WithId } from 'mongodb';
import { IDropable } from '../IDropable';
import { IRepository } from '../IRepository';
import { ISeedable } from '../ISeedable';
import { MongoDB } from './mongodb';
import { collectionName, PlaylistAudio, PlaylistAudioUpdate } from '../models/PlaylistAudio';

class PlaylistAudioRepository implements IRepository, ISeedable, IDropable {
    IRepository: 'IRepository' = 'IRepository';
    ISeedable: 'ISeedable' = 'ISeedable';
    IDropable: 'IDropable' = 'IDropable';

    private session: ClientSession | undefined = undefined
    private static collection: Collection<PlaylistAudio> | undefined = undefined

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

        if (indexes.find(i => i.name === 'audioId') === undefined)
            await db.createIndex(collectionName, { audioId: 1 }, { name: 'audioId' })

        if (indexes.find(i => i.name === 'playlistId') === undefined)
            await db.createIndex(collectionName, { playlistId: 1 }, { name: 'playlistId' })

        if (indexes.find(i => i.name === 'createdAt') === undefined)
            await db.createIndex(collectionName, { createdAt: -1 }, { name: 'createdAt' })

        if (indexes.find(i => i.name === 'updatedAt') === undefined)
            await db.createIndex(collectionName, { updatedAt: -1 }, { name: 'updatedAt' })

        PlaylistAudioRepository.collection = (await MongoDB.getDb()).collection<PlaylistAudio>(collectionName)
    }

    async dropCollection(db: Db): Promise<void> {
        await db.dropCollection(collectionName)
    }

    async insert(playlistAudio: PlaylistAudio): Promise<InsertOneResult> {
        return await PlaylistAudioRepository.collection!.insertOne({ ...playlistAudio, updatedAt: Date.now(), createdAt: Date.now() }, { session: this.session })
    }

    async get(id: string): Promise<WithId<PlaylistAudio>> {
        return (await PlaylistAudioRepository.collection!.find({ _id: ObjectId.createFromHexString(id) }, { session: this.session }).toArray())[0]
    }

    async getByName(name: string): Promise<WithId<PlaylistAudio>> {
        return (await PlaylistAudioRepository.collection!.find({ name }, { session: this.session }).toArray())[0]
    }

    async getByPlaylistNameForUser(userId: string, name: string): Promise<WithId<PlaylistAudio>[]> {
        return await PlaylistAudioRepository.collection!.find({ name, userId }, { session: this.session }).toArray()
    }

    async getByPlaylistIdForUser(userId: string, playlistId: string): Promise<WithId<PlaylistAudio>[]> {
        return await PlaylistAudioRepository.collection!.find({ playlistId, userId }, { session: this.session }).toArray()
    }

    async getMany(playlistAudioIds: string[]): Promise<WithId<PlaylistAudio>[]> {
        return await PlaylistAudioRepository.collection!.find({ _id: { $in: playlistAudioIds.map(m => ObjectId.createFromHexString(m)) } }, { session: this.session }).toArray()
    }

    async getPage(skip: number, limit: number): Promise<PlaylistAudio[]> {
        return await PlaylistAudioRepository.collection!.find({}, { session: this.session }).sort({ createdAt: -1 }).skip(skip).limit(limit).toArray()
    }

    async unsafeUpdate(playlistAudioId: string, updates: PlaylistAudioUpdate) {
        return await PlaylistAudioRepository.collection!.updateOne({ _id: ObjectId.createFromHexString(playlistAudioId) }, { $set: { ...updates, updatedAt: Date.now() } }, { session: this.session })
    }

    async delete(id: string): Promise<DeleteResult> {
        return await PlaylistAudioRepository.collection!.deleteOne({ _id: ObjectId.createFromHexString(id) }, { session: this.session })
    }

    async deleteBulk(ids: string[]): Promise<BulkWriteResult> {
        const bulkWrites: AnyBulkWriteOperation<any>[] = ids.map(id => ({ deleteOne: { filter: { _id: ObjectId.createFromHexString(id) } } }))
        return await PlaylistAudioRepository.collection!.bulkWrite(bulkWrites, { session: this.session })
    }
}

export default PlaylistAudioRepository;