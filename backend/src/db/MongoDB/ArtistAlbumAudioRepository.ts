import { AnyBulkWriteOperation, BulkWriteResult, ClientSession, Collection, Db, DeleteResult, InsertOneResult, ObjectId, WithId } from 'mongodb';
import { IDropable } from '../IDropable';
import { IRepository } from '../IRepository';
import { ISeedable } from '../ISeedable';
import { MongoDB } from './mongodb';
import { collectionName, ArtistAlbumAudio, ArtistAlbumAudioUpdate } from '../models/ArtistAlbumAudio';

class ArtistAlbumAudioRepository implements IRepository, ISeedable, IDropable {
    IRepository: 'IRepository' = 'IRepository';
    ISeedable: 'ISeedable' = 'ISeedable';
    IDropable: 'IDropable' = 'IDropable';

    private session: ClientSession | undefined = undefined
    private static collection: Collection<ArtistAlbumAudio> | undefined = undefined

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

        if (indexes.find(i => i.name === 'uniqueNames') === undefined)
            await db.createIndex(collectionName, { artistName: 1, albumName: 1, audioTitle: 1 }, { unique: true, name: 'uniqueNames' })

        if (indexes.find(i => i.name === 'createdAt') === undefined)
            await db.createIndex(collectionName, { createdAt: -1 }, { name: 'createdAt' })

        if (indexes.find(i => i.name === 'updatedAt') === undefined)
            await db.createIndex(collectionName, { updatedAt: -1 }, { name: 'updatedAt' })

        ArtistAlbumAudioRepository.collection = (await MongoDB.getDb()).collection<ArtistAlbumAudio>(collectionName)
    }

    async dropCollection(db: Db): Promise<void> {
        await db.dropCollection(collectionName)
    }

    async insert(artistAlbumAudio: ArtistAlbumAudio): Promise<InsertOneResult> {
        return await ArtistAlbumAudioRepository.collection!.insertOne({ ...artistAlbumAudio, updatedAt: Date.now(), createdAt: Date.now() }, { session: this.session })
    }

    async get(id: string): Promise<WithId<ArtistAlbumAudio>> {
        return (await ArtistAlbumAudioRepository.collection!.find({ _id: ObjectId.createFromHexString(id) }, { session: this.session }).toArray())[0]
    }

    async getManyByAlbumName(albumName: string): Promise<WithId<ArtistAlbumAudio>[]> {
        return await ArtistAlbumAudioRepository.collection!.find({ albumName }, { session: this.session }).toArray()
    }

    async getManyByArtistName(artistName: string): Promise<WithId<ArtistAlbumAudio>[]> {
        return await ArtistAlbumAudioRepository.collection!.find({ artistName }, { session: this.session }).toArray()
    }

    async getManyByAlbumNameByAudioTitle(albumName: string, audioTitle: string): Promise<WithId<ArtistAlbumAudio>[]> {
        return await ArtistAlbumAudioRepository.collection!.find({ albumName, audioTitle }, { session: this.session }).toArray()
    }

    async deleteManyByArtistNameByAudioTitle(artistName: string, audioTitle: string) {
        return await ArtistAlbumAudioRepository.collection!.deleteMany({ artistName, audioTitle }, { session: this.session })
    }

    async deleteManyByAlbumNameByAudioTitle(albumName: string, audioTitle: string) {
        return await ArtistAlbumAudioRepository.collection!.deleteMany({ albumName, audioTitle }, { session: this.session })
    }

    async updateManyByAudioTitle(audioTitle: string, updates: ArtistAlbumAudioUpdate) {
        return await ArtistAlbumAudioRepository.collection!.updateMany({ audioTitle }, { $set: { ...updates, updatedAt: Date.now() } }, { session: this.session })
    }

    async updateManyByAlbumNameByAudioTitle(albumName: string, audioTitle: string, updates: ArtistAlbumAudioUpdate) {
        return await ArtistAlbumAudioRepository.collection!.updateMany({ albumName, audioTitle }, { $set: { ...updates, updatedAt: Date.now() } }, { session: this.session })
    }

    async upsertManyByAlbumNameByAudioTitle(albumName: string, audioTitle: string, updates: ArtistAlbumAudioUpdate) {
        return await ArtistAlbumAudioRepository.collection!.updateMany({ albumName, audioTitle }, { $set: { ...updates, updatedAt: Date.now() } }, { upsert: true, session: this.session })
    }

    async delete(id: string): Promise<DeleteResult> {
        return await ArtistAlbumAudioRepository.collection!.deleteOne({ _id: ObjectId.createFromHexString(id) }, { session: this.session })
    }

    async deleteBulk(ids: string[]): Promise<BulkWriteResult> {
        const bulkWrites: AnyBulkWriteOperation<any>[] = ids.map(id => ({ deleteOne: { filter: { _id: ObjectId.createFromHexString(id) } } }))
        return await ArtistAlbumAudioRepository.collection!.bulkWrite(bulkWrites, { session: this.session })
    }

    async deleteTemporaries(): Promise<DeleteResult> {
        return await ArtistAlbumAudioRepository.collection!.deleteMany({ temporary: true }, { session: this.session })
    }
}

export default ArtistAlbumAudioRepository;