import { AnyBulkWriteOperation, BulkWriteResult, ClientSession, Collection, Db, DeleteResult, InsertManyResult, InsertOneResult, ObjectId, WithId } from 'mongodb';
import { IDropable } from '../IDropable';
import { IRepository } from '../IRepository';
import { ISeedable } from '../ISeedable';
import { MongoDB } from './mongodb';
import { collectionName as playlistAudioCollectionName, PlaylistAudio, PlaylistAudioUpdate } from '../models/PlaylistAudio';
import { Audio, collectionName as audioCollectionName } from '../models/Audio';

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
        if (!(await db.listCollections().toArray()).map(e => e.name).includes(playlistAudioCollectionName))
            await db.createCollection(playlistAudioCollectionName)

        const indexes = await db.collection(playlistAudioCollectionName).indexes()

        if (indexes.find(i => i.name === 'playlistId_audioId_unique') === undefined)
            await db.createIndex(playlistAudioCollectionName, { audioId: 1, playlistId: 1 }, { unique: true, name: 'playlistId_audioId_unique' })

        if (indexes.find(i => i.name === 'createdAt') === undefined)
            await db.createIndex(playlistAudioCollectionName, { createdAt: -1 }, { name: 'createdAt' })

        if (indexes.find(i => i.name === 'updatedAt') === undefined)
            await db.createIndex(playlistAudioCollectionName, { updatedAt: -1 }, { name: 'updatedAt' })

        PlaylistAudioRepository.collection = (await MongoDB.getDb()).collection<PlaylistAudio>(playlistAudioCollectionName)
    }

    async dropCollection(db: Db): Promise<void> {
        await db.dropCollection(playlistAudioCollectionName)
    }

    async insertMany(playlistAudios: PlaylistAudio[]): Promise<InsertManyResult> {
        return await PlaylistAudioRepository.collection!.insertMany(playlistAudios.map((pa) => ({ ...pa, updatedAt: Date.now(), createdAt: Date.now() })), { session: this.session })
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

    async getMany(playlistAudioIds: string[]): Promise<WithId<PlaylistAudio>[]> {
        return await PlaylistAudioRepository.collection!.find({ _id: { $in: playlistAudioIds.map(m => ObjectId.createFromHexString(m)) } }, { session: this.session }).toArray()
    }

    async getAudiosByPlaylistId(playlistId: string, skip: number, limit: number, audioIds: string[] | undefined): Promise<WithId<Audio>[]> {
        const agg = PlaylistAudioRepository.collection!.aggregate<WithId<Audio>>()

        agg.match({ playlistId, audioId: { $in: audioIds } })

        agg.lookup({
            from: audioCollectionName,
            localField: 'audioId',
            foreignField: '_id',
            as: 'audios'
        })

        return agg.skip(skip).limit(limit).toArray()
    }

    async delete(id: string): Promise<DeleteResult> {
        return await PlaylistAudioRepository.collection!.deleteOne({ _id: ObjectId.createFromHexString(id) }, { session: this.session })
    }

    async deleteMany(ids: string[]): Promise<BulkWriteResult> {
        const bulkWrites: AnyBulkWriteOperation<any>[] = ids.map(id => ({ deleteOne: { filter: { _id: ObjectId.createFromHexString(id) } } }))
        return await PlaylistAudioRepository.collection!.bulkWrite(bulkWrites, { session: this.session })
    }

    async deleteManyByPlaylistIdForUser(userId: string, playlistId: string): Promise<DeleteResult> {
        return await PlaylistAudioRepository.collection!.deleteMany({ userId, playlistId }, { session: this.session })
    }

    async deleteManyByPlaylistIdByAudioIdsForUser(userId: string, playlistId: string, audioIds: string[]): Promise<DeleteResult> {
        return await PlaylistAudioRepository.collection!.deleteMany({ userId, playlistId, audioId: { $in: audioIds } }, { session: this.session })
    }
}

export default PlaylistAudioRepository;