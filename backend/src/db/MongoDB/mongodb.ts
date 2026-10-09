import { ClientSession, Db, MongoClient } from 'mongodb'
import { DbConfigurationError } from '../exceptions/DbConfigurationError'
import { ConnectionError } from '../exceptions/ConnectionError'
import { IRepository, isIRepository } from '../IRepository'
import { ISeedable, isISeedable } from '../ISeedable'
import { IDropable, isIDropable } from '../IDropable'

export type MongodbConfig = {
    supportsTransaction: boolean;
    url: string;
    databaseName: string;
    auth?: {
        username: string;
        password: string;
    };
}

export class MongoDB {
    private static client: MongoClient | undefined = undefined

    public static config: MongodbConfig

    private static seeding: boolean = false

    private static repositories: IRepository[] = []
    private static seedables: ISeedable[] = []
    private static dropables: IDropable[] = []

    addRepository(repository: IRepository | ISeedable | IDropable) {
        if (isIRepository(repository) && MongoDB.repositories.find(f => f.constructor === repository.constructor) === undefined)
            MongoDB.repositories.push(repository)

        if (isISeedable(repository) && MongoDB.seedables.find(f => f.constructor === repository.constructor) === undefined)
            MongoDB.seedables.push(repository)

        if (isIDropable(repository) && MongoDB.dropables.find(f => f.constructor === repository.constructor) === undefined)
            MongoDB.dropables.push(repository)
    }

    removeRepository(index: number) {
        MongoDB.repositories = MongoDB.repositories.slice(0, index).concat(MongoDB.repositories.slice(index + 1))
    }

    static getDbInstance() {
        return new MongoDB()
    }

    async checkConnectionHealth(): Promise<boolean> {
        try {
            const db = await MongoDB.getDb(await MongoDB.getClient())
            const stats = await db.stats()
            console.log({ stats })
            return stats.ok as boolean
        } catch (error) {
            console.error(error)
            return false
        }
    }

    // For transactions between more than one collection, make sure same instance of MongoDB class is passed to getInstance static method of repository classes
    protected session: ClientSession | undefined = undefined

    async startTransaction(): Promise<ClientSession | undefined> {
        const funcName = 'startTransaction'

        console.log(funcName, 'called')

        const supportsTransaction = MongoDB.config?.supportsTransaction
        console.log({ supportsTransaction })
        if (!supportsTransaction) {
            console.log(funcName, 'Transactions are not supported.')
            return
        }

        this.session = (await MongoDB.getClient()).startSession()

        this.session.startTransaction()

        return this.session
    }

    async abortTransaction(): Promise<void> {
        const funcName = 'abortTransaction'

        console.log(funcName, 'called')

        const supportsTransaction = MongoDB.config?.supportsTransaction
        if (!supportsTransaction) {
            console.log(funcName, 'Transactions are not supported.')
            return
        }

        await this.session?.abortTransaction()
    }

    async commitTransaction(): Promise<void> {
        const funcName = 'commitTransaction'

        console.log(funcName, 'called')

        const supportsTransaction = MongoDB.config?.supportsTransaction
        if (!supportsTransaction) {
            console.log(funcName, 'Transactions are not supported.')
            return
        }

        await this.session?.commitTransaction()
    }

    async endSession(): Promise<void> {
        const funcName = 'endSession'

        console.log(funcName, 'called')

        const supportsTransaction = MongoDB.config?.supportsTransaction
        if (!supportsTransaction) {
            console.log(funcName, 'Transactions are not supported.')
            return
        }

        await this.session?.endSession()
    }

    static async getClient(): Promise<MongoClient> {
        try {
            if (MongoDB.client !== undefined)
                return MongoDB.client

            console.log('creating mongodb client...')

            if (!MongoDB.config)
                throw new Error('Mongodb configuration not found.')

            const client = new MongoClient(MongoDB.config.url, {
                authMechanism: "DEFAULT",
                auth: MongoDB.config.auth
                    ? {
                        username: MongoDB.config.auth.username,
                        password: MongoDB.config.auth.password,
                    }
                    : undefined
            })

            await client.connect()

            try {
                const adminDb = client.db().admin();
                await adminDb.ping();
                console.log('MongoDB is healthy');
            } catch (e) {
                console.error('MongoDB health check failed:', e)
                throw e
            }

            MongoDB.client = client

            return client
        } catch (error) {
            console.error(error)

            if (error instanceof DbConfigurationError)
                throw error
            else
                throw new ConnectionError()
        }
    }

    static async getDb(client?: MongoClient): Promise<Db> {
        try {
            if (client === undefined)
                client = MongoDB.client ?? await MongoDB.getClient()

            if (!MongoDB.config)
                throw new Error('Mongodb configuration not found.')

            return client.db(MongoDB.config.databaseName)
        } catch (error) {
            console.error(error);
            await client?.close()
            MongoDB.client = undefined
            throw error
        }
    }

    async reset() {
        MongoDB.client = undefined
        if (this.session !== undefined)
            try { await this.session.abortTransaction() }
            finally { this.session = undefined }

        MongoDB.repositories = []
    }

    async dropSeedableCollections() {
        const db = await MongoDB.getDb()
        for (const repository of MongoDB.dropables)
            await repository.dropCollection(db)
    }

    async createCollections() {
        const db = await MongoDB.getDb()
        for (const repository of MongoDB.repositories)
            repository.addCollection(db)
    }

    async seedCollections() {
        console.time('seed')

        MongoDB.seeding = true

        try {
            let safety = 0
            while (safety < 10_000) {
                safety++

                let failed = false
                for (const repository of MongoDB.seedables)
                    try { await repository.seed() }
                    catch (e) { failed = true; console.error(e) }

                if (!failed)
                    break
            }
        } catch (e) {
            console.error(e)
            throw e
        }

        console.timeEnd('seed')

        MongoDB.seeding = false
    }

    public static isSeeding(): boolean { return MongoDB.seeding }
}
