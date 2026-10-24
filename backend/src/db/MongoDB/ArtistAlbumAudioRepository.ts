import { AnyBulkWriteOperation, BulkWriteResult, ClientSession, Collection, Db, DeleteResult, Filter, InsertOneResult, ObjectId, WithId } from 'mongodb';
import { IDropable } from '../IDropable';
import { IRepository } from '../IRepository';
import { ISeedable } from '../ISeedable';
import { MongoDB } from './mongodb';
import { collectionName as artistAlbumAudioCollection, ArtistAlbumAudio, ArtistAlbumAudioUpdate } from '../models/ArtistAlbumAudio';
import { Album, collectionName as albumCollection } from '../models/Album';
import { Audio, collectionName as audioCollection } from '../models/Audio';
import { Artist, collectionName as artistCollection } from '../models/Artist';

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
        if (!(await db.listCollections().toArray()).map(e => e.name).includes(artistAlbumAudioCollection))
            await db.createCollection(artistAlbumAudioCollection)

        const indexes = await db.collection(artistAlbumAudioCollection).indexes()

        if (indexes.find(i => i.name === 'uniqueNames') === undefined)
            await db.createIndex(artistAlbumAudioCollection, { artistName: 1, albumName: 1, audioTitle: 1 }, { unique: true, name: 'uniqueNames' })

        if (indexes.find(i => i.name === 'createdAt') === undefined)
            await db.createIndex(artistAlbumAudioCollection, { createdAt: -1 }, { name: 'createdAt' })

        if (indexes.find(i => i.name === 'updatedAt') === undefined)
            await db.createIndex(artistAlbumAudioCollection, { updatedAt: -1 }, { name: 'updatedAt' })

        ArtistAlbumAudioRepository.collection = (await MongoDB.getDb()).collection<ArtistAlbumAudio>(artistAlbumAudioCollection)
    }

    async dropCollection(db: Db): Promise<void> {
        await db.dropCollection(artistAlbumAudioCollection)
    }

    async insert(artistAlbumAudio: ArtistAlbumAudio): Promise<InsertOneResult> {
        return await ArtistAlbumAudioRepository.collection!.insertOne({ ...artistAlbumAudio, updatedAt: Date.now(), createdAt: Date.now() }, { session: this.session })
    }

    async get(id: string): Promise<WithId<ArtistAlbumAudio>> {
        return (await ArtistAlbumAudioRepository.collection!.find({ _id: ObjectId.createFromHexString(id) }, { session: this.session }).toArray())[0]
    }

    async getBy(filter: Filter<WithId<ArtistAlbumAudio>>): Promise<WithId<ArtistAlbumAudio>[]> {
        return await ArtistAlbumAudioRepository.collection!.find(filter, { session: this.session }).toArray()
    }

    async getManyByAlbumName(albumName: string): Promise<WithId<ArtistAlbumAudio>[]> {
        return await ArtistAlbumAudioRepository.collection!.find({ albumName }, { session: this.session }).toArray()
    }

    async getManyByArtistName(artistName: string): Promise<WithId<ArtistAlbumAudio>[]> {
        return await ArtistAlbumAudioRepository.collection!.find({ artistName }, { session: this.session }).toArray()
    }

    async getManyAlbumByArtistName(artistName: string, skip: number, limit: number): Promise<WithId<Album>[]> {
        return await ArtistAlbumAudioRepository.collection!
            .aggregate([
                { $match: { artistName } },
                { $group: { _id: '$albumName' } },
                {
                    $lookup: {
                        from: albumCollection,
                        localField: '_id',
                        foreignField: 'name',
                        as: 'album'
                    }
                },
                { $unwind: '$album' },
                { $replaceRoot: { newRoot: '$album' } },

                { $sort: { createdAt: -1, _id: 1 } },
                { $skip: skip },
                { $limit: limit },
            ])
            .toArray() as WithId<Album>[]
    }

    async getManyAudioByArtistName(artistName: string, skip: number, limit: number): Promise<WithId<Audio>[]> {
        return await ArtistAlbumAudioRepository.collection!
            .aggregate([
                { $match: { artistName } },
                { $group: { _id: '$audioTitle' } },
                {
                    $lookup: {
                        from: audioCollection,
                        localField: '_id',
                        foreignField: 'name',
                        as: 'audio'
                    }
                },
                { $unwind: '$audio' },
                { $replaceRoot: { newRoot: '$audio' } },

                { $sort: { createdAt: -1, _id: 1 } },
                { $skip: skip },
                { $limit: limit },
            ])
            .toArray() as WithId<Audio>[]
    }

    async getManyArtistByAlbumName(albumName: string, skip: number, limit: number): Promise<WithId<Artist>[]> {
        return await ArtistAlbumAudioRepository.collection!
            .aggregate([
                { $match: { albumName } },
                { $group: { _id: '$artistName' } },
                {
                    $lookup: {
                        from: artistCollection,
                        localField: '_id',
                        foreignField: 'name',
                        as: 'artist'
                    }
                },
                { $unwind: '$artist' },
                { $replaceRoot: { newRoot: '$artist' } },

                { $sort: { createdAt: -1, _id: 1 } },
                { $skip: skip },
                { $limit: limit },
            ])
            .toArray() as WithId<Artist>[]
    }

    async getManyAudioByAlbumName(albumName: string, skip: number, limit: number): Promise<WithId<Audio>[]> {
        return await ArtistAlbumAudioRepository.collection!
            .aggregate([
                { $match: { albumName } },
                { $group: { _id: '$audioTitle' } },
                {
                    $lookup: {
                        from: audioCollection,
                        localField: '_id',
                        foreignField: 'title',
                        as: 'audio'
                    }
                },
                { $unwind: '$audio' },
                { $replaceRoot: { newRoot: '$audio' } },

                { $sort: { createdAt: -1, _id: 1 } },
                { $skip: skip },
                { $limit: limit },
            ])
            .toArray() as WithId<Audio>[]
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

    async updateArtistName(oldValue: string, newValue: string) {
        return await ArtistAlbumAudioRepository.collection!.updateMany({ artistName: oldValue }, { $set: { artistName: newValue, updatedAt: Date.now() } }, { session: this.session })
    }

    async updateAlbumName(oldValue: string, newValue: string) {
        return await ArtistAlbumAudioRepository.collection!.updateMany({ albumName: oldValue }, { $set: { albumName: newValue, updatedAt: Date.now() } }, { session: this.session })
    }

    async updateAudioName(oldValue: string, newValue: string) {
        return await ArtistAlbumAudioRepository.collection!.updateMany({ audioTitle: oldValue }, { $set: { audioTitle: newValue, updatedAt: Date.now() } }, { session: this.session })
    }

    async deleteBy(filter: ArtistAlbumAudioUpdate): Promise<DeleteResult> {
        return await ArtistAlbumAudioRepository.collection!.deleteMany(filter, { session: this.session })
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