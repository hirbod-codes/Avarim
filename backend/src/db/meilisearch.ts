import { type Index, type Task, type Settings, type SearchParams, type SearchResponse, type DocumentsQuery, type Filter, Meilisearch } from 'meilisearch';
import { collectionName as audioCollection, AudioSearch } from "./models/Audio";
import { meilisearchHost, meilisearchKey, meilisearchPort } from '../configs';
import { ArtistSearch } from './models/Artist';
import { AlbumSearch } from './models/Album';

/* ------------------------------------------------------------------ */
/* Errors                                                             */
/* ------------------------------------------------------------------ */

export type SearchErrorKind =
    | 'not_found'        // document or index doesn't exist
    | 'invalid'          // bad request: invalid filter, missing primary key, bad document...
    | 'auth'             // bad/missing API key
    | 'unavailable'      // Meilisearch unreachable or answering 5xx
    | 'timeout'          // request or task wait timed out (the task may still finish later)
    | 'task_failed'      // the write was accepted but failed while being processed
    | 'unknown';

export class SearchError extends Error {
    constructor(
        public readonly kind: SearchErrorKind,
        message: string,
        public readonly code?: string,          // Meilisearch error code, e.g. "document_not_found"
        public readonly cause?: unknown,
    ) {
        super(message);
        this.name = 'SearchError';
    }
}

/**
 * Normalises whatever the SDK throws. Matches on error *names/shape* instead of
 * importing the SDK's error classes: they were renamed (MeiliSearch* -> Meilisearch*)
 * between versions, and this keeps working across both.
 */
function toSearchError(op: string, e: unknown): SearchError {
    if (e instanceof SearchError) return e;
    const err = e as { name?: string; message?: string; code?: string; cause?: { code?: string; message?: string }; response?: { status?: number } };
    const name = err?.name ?? '';
    const code = err?.cause?.code ?? err?.code;               // new SDK: error.cause, old SDK: error.code
    const detail = err?.cause?.message ?? err?.message ?? String(e);
    const msg = `Meilisearch ${op} failed: ${detail}`;

    if (/TimeOut/i.test(name)) return new SearchError('timeout', msg, code, e);
    if (/RequestError|CommunicationError/i.test(name)) return new SearchError('unavailable', msg, code, e);
    if (/ApiError/i.test(name)) {
        const status = err.response?.status;
        if (code === 'document_not_found' || code === 'index_not_found') return new SearchError('not_found', msg, code, e);
        if (status === 401 || status === 403 || code === 'invalid_api_key' || code === 'missing_authorization_header') return new SearchError('auth', msg, code, e);
        if (status && status >= 500) return new SearchError('unavailable', msg, code, e);
        return new SearchError('invalid', msg, code, e);
    }
    return new SearchError('unknown', msg, code, e);
}

/* ------------------------------------------------------------------ */
/* CRUD class                                                         */
/* ------------------------------------------------------------------ */

export interface WriteOptions {
    /**
     * Meilisearch writes are asynchronous: the call only *enqueues* a task, and
     * a bad document fails later, silently. `wait: true` polls the task and throws
     * `SearchError('task_failed')` if it failed. Default: the class-level default.
     */
    wait?: boolean;
}

export interface MeiliCrudOptions {
    primaryKey?: string;              // default '_id'
    settings?: Settings;              // applied by ensureIndex(): filterableAttributes, sortableAttributes, ...
    waitByDefault?: boolean;          // default false (fire-and-forget)
    taskTimeoutMs?: number;           // default 10_000
}

export interface WriteResult { taskUid: number; status: Task['status'] }

export const meili = new Meilisearch({
    host: meilisearchHost + ':' + meilisearchPort.toString(),
    apiKey: meilisearchKey
})

/**
 * usage:
 * 
 * ``` 
 * const treeNodes = new MeiliCrud<AudioSearch>(meili, MEILI_TREE_NODE, {
 * primaryKey: '_id',
 * settings: { filterableAttributes: ['userId', 'parentId'], sortableAttributes: ['createdAt'] },
 * });
 * 
 * await MeiliCrud.setup(); // once at startup, safe to call repeatedly
 * 
 * await treeNodes.create({
 * _id: insertTreeNodeResult.insertedId.toString(),
 * userId: req.user!.userId,
 * parentId: treeNode.parentId ?? null,
 * title: treeNode.title,
 * createdAt: new Date().toISOString(),
 * updatedAt: new Date().toISOString(),
 * }, { wait: true });
 * ```
 */
export class MeiliCrud<T extends Record<string, any>> {
    static async setup() {
        console.log('meilisearch setup...')

        console.log('prepare audio index...')
        await meiliAudio.ensureIndex();

        console.log('prepare artist index...')
        await meiliArtist.ensureIndex();

        console.log('prepare album index...')
        await meiliAlbum.ensureIndex();
    }

    private readonly index: Index<T>;
    private readonly primaryKey: string;
    private readonly waitByDefault: boolean;
    private readonly taskTimeoutMs: number;

    constructor(private readonly client: Meilisearch, readonly indexUid: string, private readonly opts: MeiliCrudOptions = {}) {
        this.primaryKey = opts.primaryKey ?? '_id';
        this.waitByDefault = opts.waitByDefault ?? false;
        this.taskTimeoutMs = opts.taskTimeoutMs ?? 10_000;
        this.index = client.index<T>(indexUid);
    }

    /* ---------- internals ---------- */

    /** Wrap a read: normalise errors only. */
    private async read<R>(op: string, fn: () => Promise<R>): Promise<R> {
        try { return await fn(); } catch (e) { throw toSearchError(op, e); }
    }

    /** Wrap a write: enqueue, optionally wait for completion, and surface failed tasks. */
    private async write(op: string, enqueue: () => ReturnType<Index<T>['addDocuments']>, o?: WriteOptions): Promise<WriteResult> {
        try {
            const enqueued = enqueue();
            const wait = o?.wait ?? this.waitByDefault;
            if (!wait) {
                const t = await enqueued;
                return { taskUid: t.taskUid, status: t.status };
            }
            const task = await enqueued.waitTask({ timeout: this.taskTimeoutMs });
            if (task.status !== 'succeeded') {
                throw new SearchError('task_failed', `Meilisearch ${op} task ${task.uid} ${task.status}: ${task.error?.message ?? 'no details'}`, task.error?.code);
            }
            return { taskUid: task.uid, status: task.status };
        } catch (e) {
            throw toSearchError(op, e);
        }
    }

    /* ---------- setup ---------- */

    /** Idempotent: creates the index with the primary key if missing, then applies settings. Call once at startup. */
    async ensureIndex(): Promise<void> {
        try {
            const task = await this.client.createIndex(this.indexUid, { primaryKey: this.primaryKey }).waitTask({ timeout: this.taskTimeoutMs });
            // 'index_already_exists' is the expected failure on every start after the first
            if (task.status === 'failed' && task.error?.code !== 'index_already_exists')
                throw new SearchError('task_failed', `createIndex failed: ${task.error?.message}`, task.error?.code);
            if (this.opts.settings) {
                const s = await this.index.updateSettings(this.opts.settings).waitTask({ timeout: this.taskTimeoutMs });
                if (s.status !== 'succeeded') throw new SearchError('task_failed', `updateSettings failed: ${s.error?.message}`, s.error?.code);
            }
        } catch (e) {
            throw toSearchError('ensureIndex', e);
        }
    }

    /* ---------- create ---------- */

    /** 
     * Adds documents. A document with an existing primary key is REPLACED entirely. 
     * With { wait: true }, success is "it didn't throw" 
    */
    create(doc: T | T[], o?: WriteOptions) {
        return this.write('create', () => this.index.addDocuments(Array.isArray(doc) ? doc : [doc], { primaryKey: this.primaryKey }), o);
    }

    /* ---------- read ---------- */

    /** Returns null when the document doesn't exist (instead of throwing). */
    async get(id: string, fields?: Extract<keyof T, string>[]): Promise<T | null> {
        try {
            return await this.read('get', () => this.index.getDocument(id, fields ? { fields } : undefined));
        } catch (e) {
            if (e instanceof SearchError && e.code === 'document_not_found') return null;
            throw e;
        }
    }

    list(query?: DocumentsQuery<T>) {
        return this.read('list', () => this.index.getDocuments(query));
    }

    search(q: string, params?: SearchParams): Promise<SearchResponse<T>> {
        return this.read('search', () => this.index.search(q, params));
    }

    /* ---------- update ---------- */

    /**
     * Partial update: merges `patch` into the stored document.
     * Meilisearch's own updateDocuments UPSERTS (it would create a half-empty
     * document for an unknown id), so we check existence first and throw not_found.
     * The check and the write aren't atomic; fine for admin-style traffic.
     */
    async update(id: string, patch: Partial<T>, o?: WriteOptions): Promise<WriteResult> {
        if (!(await this.get(id, [this.primaryKey as Extract<keyof T, string>]))) throw new SearchError('not_found', `Meilisearch update failed: document "${id}" not found`, 'document_not_found');
        return this.write('update', () => this.index.updateDocuments([{ ...patch, [this.primaryKey]: id } as Partial<T>], { primaryKey: this.primaryKey }), o);
    }

    /** Insert-or-replace by primary key (same as create, named for intent). */
    upsert(doc: T | T[], o?: WriteOptions) { return this.create(doc, o); }

    /* ---------- delete ---------- */

    /** Deleting a missing id is not an error in Meilisearch; the task simply succeeds. */
    delete(id: string, o?: WriteOptions) {
        return this.write('delete', () => this.index.deleteDocument(id), o);
    }
    deleteMany(ids: string[], o?: WriteOptions) {
        return this.write('deleteMany', () => this.index.deleteDocuments(ids), o);
    }
    /** Requires the attributes used in the filter to be in `filterableAttributes`. */
    deleteByFilter(filter: Filter, o?: WriteOptions) {
        return this.write('deleteByFilter', () => this.index.deleteDocuments({ filter }), o);
    }
    clear(o?: WriteOptions) {
        return this.write('clear', () => this.index.deleteAllDocuments(), o);
    }
}

export const meiliAudio = new MeiliCrud<AudioSearch>(meili, audioCollection, {
    primaryKey: '_id',
    settings: { filterableAttributes: ['_id', 'title'], sortableAttributes: ['_id', 'title'], searchableAttributes: ['title'] },
});

export const meiliArtist = new MeiliCrud<ArtistSearch>(meili, audioCollection, {
    primaryKey: '_id',
    settings: { filterableAttributes: ['_id', 'name'], sortableAttributes: ['_id', 'name'], searchableAttributes: ['name'] },
});

export const meiliAlbum = new MeiliCrud<AlbumSearch>(meili, audioCollection, {
    primaryKey: '_id',
    settings: { filterableAttributes: ['_id', 'name'], sortableAttributes: ['_id', 'name'], searchableAttributes: ['name'] },
});
