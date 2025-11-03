import { createStore, UseStore, get, set, setMany, getMany, update, del, delMany, clear, keys, values, entries } from 'idb-keyval';

export type CacheHandlerOptions = {
	keysToKeep?: number;
};

export class CacheHandler<T> {
	keysToKeep: CacheHandlerOptions['keysToKeep'];
	private data = new Map<string, T>();

	constructor(options: CacheHandlerOptions = {}) {
		this.keysToKeep = options.keysToKeep;
	}

	has(id: string): boolean {
		return this.data.has(id);
	}

	get(id: string): T | undefined {
		return this.data.get(id);
	}

	set(id: string, result: T) {
		this.data.set(id, result);
		if (this.keysToKeep) this.keepMostRecent();
	}

	private keepMostRecent() {
		if (this.keysToKeep && this.data.size > this.keysToKeep) {
			const keys = [...this.data.keys()];
			const keysToRemove = keys.slice(0, keys.length - this.keysToKeep);
			keysToRemove.forEach(key => this.data.delete(key));
		}
	}
}

export type PersistentCacheHandlerOptions = {
	databaseName: string;
	version: number;
	ttl?: number; // In seconds
};
export type PersistentCacheItemWithExpiry<T> = {
	value: T;
	version: PersistentCacheHandlerOptions['version'];
	expires?: number;
};

export class PersistentCacheHandler<T> {
	private store: UseStore;
	version: PersistentCacheHandlerOptions['version'];
	ttl: PersistentCacheHandlerOptions['ttl'];
	initialized = false;
	waitForInit: Promise<void>;

	constructor(options: PersistentCacheHandlerOptions) {
		this.store = createStore(options.databaseName, 'keyval-store');
		this.version = options.version;
		this.ttl = options.ttl;

		this.waitForInit = this.validateCache();
	}

	private async validateCache() {
		const allKeys = await entries<IDBValidKey, PersistentCacheItemWithExpiry<T>>(this.store);
		const markedForDeletion: IDBValidKey[] = [];
		for (const [id, data] of allKeys) {
			if (!this.isValid(data.version, data.expires)) markedForDeletion.push(id);
		}
		if (markedForDeletion.length) await delMany(markedForDeletion, this.store);
	}
	async get(id: IDBValidKey) {
		await this.waitForInit;
		const cachedData = await get<PersistentCacheItemWithExpiry<T>>(id, this.store);
		if (cachedData && !this.isValid(cachedData.version, cachedData.expires)) {
			await this.del(id);
			return undefined;
		}
		return cachedData?.value;
	}
	async set(id: IDBValidKey, value: T) {
		await this.waitForInit;
		return set(id, this.mapValueForStorage(value), this.store);
	}
	async setMany(entries: [IDBValidKey, T][]) {
		await this.waitForInit;
		return setMany(
			entries.map(([id, value]) => [id, this.mapValueForStorage(value)]),
			this.store,
		);
	}
	async getMany(ids: IDBValidKey[]) {
		await this.waitForInit;
		const cachedData = await getMany<PersistentCacheItemWithExpiry<T>>(ids, this.store);
		const markedForDeletion: IDBValidKey[] = [];
		const data: T[] = [];
		for (const [index, id] of ids.entries()) {
			const { value, expires, version } = cachedData[index] || {};
			if (this.isValid(version, expires)) {
				data.push(value);
				continue;
			}
			markedForDeletion.push(id);
		}
		if (markedForDeletion.length) await this.delMany(markedForDeletion);
		return data;
	}
	async update(id: IDBValidKey, updater: (oldValue: T | undefined) => T) {
		await this.waitForInit;
		return update(id, updater, this.store);
	}
	async del(id: IDBValidKey) {
		await this.waitForInit;
		return del(id, this.store);
	}
	async delMany(ids: IDBValidKey[]) {
		await this.waitForInit;
		return delMany(ids, this.store);
	}
	async clear() {
		await this.waitForInit;
		return clear(this.store);
	}
	async keys() {
		await this.waitForInit;
		return keys(this.store);
	}
	async values() {
		await this.waitForInit;
		return values<T>(this.store);
	}
	async entries() {
		await this.waitForInit;
		return entries<IDBValidKey, T>(this.store);
	}

	get cacheTime() {
		if (this.ttl) return Date.now() + (this.ttl || 0) * 1000;
		return undefined;
	}
	isValid(version: number, expires?: number) {
		if (!version || this.version > version) return false;
		if (typeof expires !== 'number') return true;
		return Date.now() < expires;
	}
	mapValueForStorage(value: T): PersistentCacheItemWithExpiry<T> {
		return {
			value,
			version: this.version,
			expires: this.cacheTime,
		};
	}
}
