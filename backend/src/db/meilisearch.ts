import { type Index, type Task, type Settings, type SearchParams, type SearchResponse, type DocumentsQuery, type Filter, Meilisearch } from 'meilisearch';
import { collectionName as audioCollection, AudioSearch } from "./models/Audio";
import { isProduction, meilisearchHost, meilisearchKey, meilisearchPort } from '../configs';
import { ArtistSearch, collectionName as artistCollection } from './models/Artist';
import { AlbumSearch, collectionName as albumCollection } from './models/Album';
import { collectionName as playlistCollection, PlaylistSearch } from './models/Playlist';
import { collectionName as playlistAudioCollection, PlaylistAudioSearch } from './models/PlaylistAudio';
import { ObjectId } from 'mongodb';

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

type FilterValue = string | number | boolean;
/** A scalar means "equals"; an array means "equals any of these" (Meilisearch `IN`). */
export type Where<T> = { [K in Extract<keyof T, string>]?: FilterValue | FilterValue[] };

export interface WriteResult { taskUid: number; status: Task['status'] }

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

/** A document to create: `_id` is optional and generated when missing (a MongoDB-style ObjectId). */
export type NewDoc<T> = Omit<T, '_id'> & { _id?: string };

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

        console.log('prepare playlist index...')
        await meiliPlaylist.ensureIndex();

        console.log('prepare playlist audio index...')
        await meiliPlaylistAudio.ensureIndex();
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
     * Adds documents. `_id` is optional: when missing it is generated the way MongoDB does
     * (a new ObjectId as a 24-char hex string) and returned as `id` (or `ids` for an array).
     * A document that DOES carry an existing `_id` is REPLACED entirely.
     * With { wait: true }, success is "it didn't throw".
     *
     *   const { id } = await meiliPlaylistAudio.create({ playlistId, audioId, audioTitle });
     *   const { ids } = await meiliPlaylistAudio.create([{ playlistId, audioId: 'a1', audioTitle: 'x' }, { ... }]);
     */
    create(doc: NewDoc<T>, o?: WriteOptions): Promise<WriteResult & { id: string }>;
    create(docs: NewDoc<T>[], o?: WriteOptions): Promise<WriteResult & { ids: string[] }>;
    async create(input: NewDoc<T> | NewDoc<T>[], o?: WriteOptions): Promise<(WriteResult & { id: string }) | (WriteResult & { ids: string[] })> {
        const many = Array.isArray(input);
        const docs = (many ? input : [input]).map((d) => this.withId(d));
        const result = await this.add('create', docs, o);
        const ids = docs.map((d) => this.idOf(d));
        return many ? { ...result, ids } : { ...result, id: ids[0] };
    }

    /** Insert-or-replace by primary key. Unlike `create`, the `_id` is required (nothing is generated). */
    upsert(doc: T | T[], o?: WriteOptions) {
        return this.add('upsert', Array.isArray(doc) ? doc : [doc], o);
    }

    /** Keeps a given primary key; generates a MongoDB-style one when it is missing. */
    private withId(doc: NewDoc<T>): T {
        const given = (doc as Record<string, unknown>)[this.primaryKey];
        const id = given === undefined || given === null || given === '' ? new ObjectId().toHexString() : given;
        return { ...doc, [this.primaryKey]: id } as unknown as T;
    }

    private add(op: string, docs: T[], o?: WriteOptions) {
        return this.write(op, () => this.index.addDocuments(docs, { primaryKey: this.primaryKey }), o);
    }

    // /** 
    //  * Adds documents. A document with an existing primary key is REPLACED entirely. 
    //  * With { wait: true }, success is "it didn't throw" 
    // */
    // create(doc: T | T[], o?: WriteOptions) {
    //     return this.write('create', () => this.index.addDocuments(Array.isArray(doc) ? doc : [doc], { primaryKey: this.primaryKey }), o);
    // }

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

    search(q: string, params?: SearchParams): Promise<SearchResponse<T & { _id: any }>> {
        return this.read('search', () => this.index.search(q, params));
    }

    /**
     * Exact-match lookup without knowing the id: `findBy({ audioTitle: 'Midnight Run' })`.
     * Several conditions are ANDed. Always returns an array (empty when nothing matches),
     * because fields like a title aren't unique.
     *
     * Every field you use here MUST be listed in `filterableAttributes`, otherwise
     * Meilisearch rejects it (SearchError kind 'invalid').
     * Matching is exact on the whole value (case-insensitive); for "contains" / typo-tolerant
     * matching use `search()` instead.
     */
    async findBy(where: { [K in Extract<keyof T, string>]?: string | number | boolean }, opts: { limit?: number } = {}): Promise<(T & { _id: any })[]> {
        const filter = Object.entries(where)
            .filter(([, v]) => v !== undefined)
            .map(([field, value]) => `${field} = ${JSON.stringify(value)}`)       // JSON quoting escapes " and \ inside values
            .join(' AND ');
        if (!filter) throw new SearchError('invalid', 'Meilisearch findBy needs at least one condition');
        return (await this.list({ filter, limit: opts.limit ?? 100 })).results as (T & { _id: any })[];
    }

    /**
     * `{ title: 'x', userId: 'u' }`   -> `title = "x" AND userId = "u"`
     * `{ audioId: ['a', 'b'] }`       -> `audioId IN ["a", "b"]`
     * Values are JSON-quoted, so quotes and backslashes inside them are escaped.
     */
    private filterFrom(where: Where<T>): string {
        const parts = Object.entries(where)
            .filter(([, v]) => v !== undefined)
            .map(([field, value]) => {
                if (Array.isArray(value)) {
                    // An empty list matches nothing. Dropping the condition instead would WIDEN the delete
                    // (e.g. { playlistId, audioId: [] } would wipe the whole playlist), so refuse it.
                    if (value.length === 0) throw new SearchError('invalid', `Meilisearch lookup: the "${field}" list must not be empty`);
                    return `${field} IN [${value.map((v) => JSON.stringify(v)).join(', ')}]`;
                }
                return `${field} = ${JSON.stringify(value)}`;
            });
        if (!parts.length) throw new SearchError('invalid', 'Meilisearch lookup needs at least one condition');
        return parts.join(' AND ');
    }

    /** All primary keys matching a filter, paging through every result (no silent 20/100 cap). */
    private async idsMatching(filter: string): Promise<string[]> {
        const ids: string[] = [];
        for (let offset = 0; ; offset += 1000) {
            const page = await this.read('lookup', () => this.index.getDocuments({ filter, limit: 1000, offset, fields: [this.primaryKey as Extract<keyof T, string>] }));
            ids.push(...page.results.map((d) => String(d[this.primaryKey])));
            if (offset + page.results.length >= page.total || page.results.length === 0) return ids;
        }
    }

    /** The document's primary key value, whatever the primary key field is called. */
    idOf(doc: T): string {
        return String(doc[this.primaryKey]);
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

    /**
     * Like MongoDB's `updateMany(where, { $set: patch })`: merges `patch` into EVERY document matching `where`.
     *
     *   await meiliPlaylistAudio.updateBy({ audioId }, { audioTitle: 'New title' });
     *   await meiliPlaylistAudio.updateBy({ playlistId: 'p1', audioId: ['a1', 'a2'] }, { audioTitle: 'x' });
     *
     * Returns how many documents matched (like Mongo's `matchedCount`); `task` is null when nothing matched
     * (no write is enqueued). Fields used in `where` must be in `filterableAttributes`.
     *
     * Meilisearch has no "update by filter" on stable releases, so this is two steps: collect the matching
     * primary keys (paging through all of them), then one partial update for those ids. The two steps aren't
     * atomic: a document created in between is missed. Fine for admin-style traffic, same caveat as `update()`.
     * Like `$set`, top-level fields are replaced as a whole (nested objects are not deep-merged).
     */
    async updateBy(where: Where<T>, patch: Partial<T>, o?: WriteOptions): Promise<{ matched: number; task: WriteResult | null }> {
        if (Object.keys(patch).length === 0) throw new SearchError('invalid', 'Meilisearch updateBy needs at least one field to set');

        const ids = await this.idsMatching(this.filterFrom(where));
        if (ids.length === 0) return { matched: 0, task: null };

        const task = await this.write(
            'updateBy',
            // the primary key is set last, so a primary key inside `patch` can never retarget a document
            () => this.index.updateDocuments(ids.map((id) => ({ ...patch, [this.primaryKey]: id }) as Partial<T>), { primaryKey: this.primaryKey }),
            o,
        );
        return { matched: ids.length, task };
    }

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

    /**
     * Deletes EVERY document matching `where`. Fields must be filterable.
     * `deleteBy({ audioTitle: 'x', userId })`, or `deleteBy({ audioId: audioIds })` for "any of these".
     */
    deleteBy(where: Where<T>, o?: WriteOptions) {
        return this.write('deleteBy', () => this.index.deleteDocuments({ filter: this.filterFrom(where) }), o);
    }

    clear(o?: WriteOptions) {
        return this.write('clear', () => this.index.deleteAllDocuments(), o);
    }
}

export const meiliAudio = new MeiliCrud<AudioSearch>(meili, isProduction ? `avarim_${audioCollection}` : `dev_avarim_${audioCollection}`, {
    primaryKey: '_id',
    settings: { filterableAttributes: ['_id', 'title', 'lyrics'], sortableAttributes: ['_id', 'title', 'lyrics'], searchableAttributes: ['title', 'lyrics'] },
    waitByDefault: true
});

export const meiliArtist = new MeiliCrud<ArtistSearch>(meili, isProduction ? `avarim_${artistCollection}` : `dev_avarim_${artistCollection}`, {
    primaryKey: '_id',
    settings: { filterableAttributes: ['_id', 'name'], sortableAttributes: ['_id', 'name'], searchableAttributes: ['name'] },
    waitByDefault: true
});

export const meiliAlbum = new MeiliCrud<AlbumSearch>(meili, isProduction ? `avarim_${albumCollection}` : `dev_avarim_${albumCollection}`, {
    primaryKey: '_id',
    settings: { filterableAttributes: ['_id', 'name'], sortableAttributes: ['_id', 'name'], searchableAttributes: ['name'] },
    waitByDefault: true
});

export const meiliPlaylist = new MeiliCrud<PlaylistSearch>(meili, isProduction ? `avarim_${playlistCollection}` : `dev_avarim_${playlistCollection}`, {
    primaryKey: '_id',
    settings: { filterableAttributes: ['_id', 'name'], sortableAttributes: ['_id', 'name'], searchableAttributes: ['name'] },
    waitByDefault: true
});

// to be able to search for audios in a playlist
export const meiliPlaylistAudio = new MeiliCrud<PlaylistAudioSearch>(meili, isProduction ? `avarim_${playlistAudioCollection}` : `dev_avarim_${playlistAudioCollection}`, {
    primaryKey: '_id',
    settings: { filterableAttributes: ['_id', 'playlistId', 'audioId', 'audioTitle'], sortableAttributes: ['_id', 'playlistId', 'audioTitle'], searchableAttributes: ['audioTitle'] },
    waitByDefault: true
});
