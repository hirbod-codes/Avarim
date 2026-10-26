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

    async getManyByAlbumId(albumId: string): Promise<WithId<ArtistAlbumAudio>[]> {
        return await ArtistAlbumAudioRepository.collection!.find({ albumId }, { session: this.session }).toArray()
    }

    async getManyByArtistId(artistId: string): Promise<WithId<ArtistAlbumAudio>[]> {
        return await ArtistAlbumAudioRepository.collection!.find({ artistId }, { session: this.session }).toArray()
    }

    async getManyAlbumByArtistId(artistId: string, skip: number, limit: number): Promise<WithId<Album>[]> {
        return await ArtistAlbumAudioRepository.collection!
            .aggregate([
                { $match: { artistId } },
                { $group: { _id: '$albumId' } },
                {
                    $lookup: {
                        from: albumCollection,
                        localField: '_id',
                        foreignField: '_id',
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

    async getManyAudioByArtistId(artistId: string, skip: number, limit: number): Promise<WithId<Audio>[]> {
        return await ArtistAlbumAudioRepository.collection!
            .aggregate([
                { $match: { artistId } },
                { $group: { _id: '$audioTitle' } },
                {
                    $lookup: {
                        from: audioCollection,
                        localField: '_id',
                        foreignField: '_id',
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

    async getManyAudioByArtistIdByAlbumId(artistId: string, albumId: string | undefined, skip: number, limit: number): Promise<WithId<Audio>[]> {
        return await ArtistAlbumAudioRepository.collection!
            .aggregate([
                { $match: { artistId, albumId } },
                { $group: { _id: '$audioTitle' } },
                {
                    $lookup: {
                        from: audioCollection,
                        localField: '_id',
                        foreignField: '_id',
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

    async getManyArtistByAlbumId(albumId: string, skip: number, limit: number): Promise<WithId<Artist>[]> {
        return await ArtistAlbumAudioRepository.collection!
            .aggregate([
                { $match: { albumId } },
                { $group: { _id: '$artistId' } },
                {
                    $lookup: {
                        from: artistCollection,
                        localField: '_id',
                        foreignField: '_id',
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

    async getManyAudioByAlbumId(albumId: string, skip: number, limit: number): Promise<WithId<Audio>[]> {
        return await ArtistAlbumAudioRepository.collection!
            .aggregate([
                { $match: { albumId } },
                { $group: { _id: '$audioId' } },
                {
                    $lookup: {
                        from: audioCollection,
                        localField: '_id',
                        foreignField: '_id',
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

    async getManyAlbumByAudioId(audioId: string, skip: number, limit: number): Promise<WithId<Album>[]> {
        return await ArtistAlbumAudioRepository.collection!
            .aggregate([
                { $match: { audioId } },
                { $group: { _id: '$albumId' } },
                {
                    $lookup: {
                        from: albumCollection,
                        localField: '_id',
                        foreignField: '_id',
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

    async getManyAlbumByAudioIdByArtistId(audioId: string, artistId: string | undefined, skip: number, limit: number): Promise<WithId<Album>[]> {
        return await ArtistAlbumAudioRepository.collection!
            .aggregate([
                { $match: { audioId, artistId } },
                { $group: { _id: '$albumId' } },
                {
                    $lookup: {
                        from: albumCollection,
                        localField: '_id',
                        foreignField: '_id',
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

    async getManyArtistByAudioIdByAlbumId(audioId: string, albumId: string | undefined, skip: number, limit: number): Promise<WithId<Artist>[]> {
        return await ArtistAlbumAudioRepository.collection!
            .aggregate([
                { $match: { audioId, albumId } },
                { $group: { _id: '$artistId' } },
                {
                    $lookup: {
                        from: artistCollection,
                        localField: '_id',
                        foreignField: '_id',
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

    async getManyArtistByAudioId(audioId: string, skip: number, limit: number): Promise<WithId<Artist>[]> {
        return await ArtistAlbumAudioRepository.collection!
            .aggregate([
                { $match: { audioId } },
                { $group: { _id: '$artistId' } },
                {
                    $lookup: {
                        from: artistCollection,
                        localField: '_id',
                        foreignField: '_id',
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

    async getManyByAlbumIdByAudioId(albumId?: string, audioId?: string): Promise<WithId<ArtistAlbumAudio>[]> {
        return await ArtistAlbumAudioRepository.collection!.find({ albumId, audioId }, { session: this.session }).toArray()
    }

    async deleteManyByArtistIdByAudioId(artistId?: string, audioId?: string) {
        return await ArtistAlbumAudioRepository.collection!.deleteMany({ artistId, audioId }, { session: this.session })
    }

    async deleteManyByAlbumIdByAudioId(albumId?: string, audioId?: string) {
        return await ArtistAlbumAudioRepository.collection!.deleteMany({ albumId, audioId }, { session: this.session })
    }

    async updateManyByAudioId(audioId?: string, updates?: ArtistAlbumAudioUpdate) {
        return await ArtistAlbumAudioRepository.collection!.updateMany({ audioId }, { $set: { ...updates, updatedAt: Date.now() } }, { session: this.session })
    }

    async updateManyByAlbumIdByAudioId(albumId?: string, audioId?: string, updates?: ArtistAlbumAudioUpdate) {
        return await ArtistAlbumAudioRepository.collection!.updateMany({ albumId, audioId }, { $set: { ...updates, updatedAt: Date.now() } }, { session: this.session })
    }

    async upsertManyByAlbumIdByAudioId(albumId?: string, audioId?: string, updates?: ArtistAlbumAudioUpdate) {
        return await ArtistAlbumAudioRepository.collection!.updateMany({ albumId, audioId }, { $set: { ...updates, updatedAt: Date.now() } }, { upsert: true, session: this.session })
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