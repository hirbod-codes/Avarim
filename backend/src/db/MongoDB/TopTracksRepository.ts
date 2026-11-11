import { AnyBulkWriteOperation, BulkWriteResult, ClientSession, Collection, Db, DeleteResult, Filter, InsertOneResult, ObjectId, WithId } from 'mongodb';
import { IDropable } from '../IDropable';
import { IRepository } from '../IRepository';
import { ISeedable } from '../ISeedable';
import { MongoDB } from './mongodb';
import { Audio, collectionName as audioCollection } from '../models/Audio';
import { collectionName as topTracksCollection, TopTracks, TopTracksFilter } from '../models/TopTracks.ts';


class TopTracksRepository implements IRepository, ISeedable, IDropable {
    IRepository: 'IRepository' = 'IRepository';
    ISeedable: 'ISeedable' = 'ISeedable';
    IDropable: 'IDropable' = 'IDropable';

    private session: ClientSession | undefined = undefined
    private static collection: Collection<TopTracks> | undefined = undefined

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
        if (!(await db.listCollections().toArray()).map(e => e.name).includes(topTracksCollection))
            await db.createCollection(topTracksCollection)

        const indexes = await db.collection(topTracksCollection).indexes()

        if (indexes.find(i => i.name === 'uniqueIds') === undefined)
            await db.createIndex(topTracksCollection, { artistId: 1, audioId: 1 }, { unique: true, name: 'uniqueIds' })

        if (indexes.find(i => i.name === 'sortId') === undefined)
            await db.createIndex(topTracksCollection, { sortId: 1 }, { name: 'sortId' })

        if (indexes.find(i => i.name === 'createdAt') === undefined)
            await db.createIndex(topTracksCollection, { createdAt: -1 }, { name: 'createdAt' })

        if (indexes.find(i => i.name === 'updatedAt') === undefined)
            await db.createIndex(topTracksCollection, { updatedAt: -1 }, { name: 'updatedAt' })

        TopTracksRepository.collection = (await MongoDB.getDb()).collection<TopTracks>(topTracksCollection)
    }

    async dropCollection(db: Db): Promise<void> {
        await db.dropCollection(topTracksCollection)
    }

    async insert(topTracks: TopTracks): Promise<InsertOneResult> {
        return await TopTracksRepository.collection!.insertOne({ ...topTracks, updatedAt: Date.now(), createdAt: Date.now() }, { session: this.session })
    }

    async get(id: string): Promise<WithId<TopTracks>[]> {
        return await TopTracksRepository.collection!.find({ _id: ObjectId.createFromHexString(id) }, { session: this.session }).toArray()
    }

    async getBy(filter: Filter<TopTracksFilter>): Promise<WithId<TopTracks>[]> {
        return await TopTracksRepository.collection!.find(filter as any, { session: this.session }).toArray()
    }

    getFromCursor(fromTsMs: number) {
        return TopTracksRepository.collection!.find({ updatedAt: { $gte: fromTsMs } }, { session: this.session })
    }

    async getManyAudio(filter: Filter<TopTracks>, skip: number, limit: number): Promise<WithId<Audio>[]> {
        return await TopTracksRepository.collection!
            .aggregate([
                { $sort: { sortId: 1 } },
                { $match: filter },
                { $group: { _id: { $toObjectId: '$audioId' } } },
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
                { $skip: skip },
                { $limit: limit },
            ])
            .toArray() as WithId<Audio>[]
    }

    async delete(id: string): Promise<DeleteResult> {
        return await TopTracksRepository.collection!.deleteOne({ _id: ObjectId.createFromHexString(id) }, { session: this.session })
    }

    async deleteBulk(ids: string[]): Promise<BulkWriteResult> {
        const bulkWrites: AnyBulkWriteOperation<any>[] = ids.map(id => ({ deleteOne: { filter: { _id: ObjectId.createFromHexString(id) } } }))
        return await TopTracksRepository.collection!.bulkWrite(bulkWrites, { session: this.session })
    }
}

export default TopTracksRepository;