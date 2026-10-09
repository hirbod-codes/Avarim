import RedisClient, { Redis as RedisInstance } from 'ioredis';
import { redisConfig } from '../configs';

export class Redis {
    private static client: RedisInstance | undefined = undefined;

    static async connect(): Promise<RedisInstance> {
        if (Redis.client) return Redis.client;

        const client = new RedisClient({
            host: redisConfig.host,
            port: redisConfig.port,
            password: redisConfig.auth.password,
            db: redisConfig.databaseIndex,
            maxRetriesPerRequest: 3,
            retryStrategy: (attempts: number) => Math.min(attempts * 100, 3000),
            lazyConnect: true,
        });

        client.on('error', (err) => {
            console.error('[Redis] connection error', err);
        });

        client.on('connect', () => {
            console.log('[Redis] connected');
        });

        await client.connect();

        Redis.client = client;
        return client;
    }

    static async getClient(): Promise<RedisInstance> {
        if (!Redis.client) return Redis.connect();
        return Redis.client;
    }

    static async disconnect(): Promise<void> {
        if (Redis.client) {
            await Redis.client.quit();
            Redis.client = undefined;
        }
    }
}
