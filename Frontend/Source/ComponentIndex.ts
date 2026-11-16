import { CellStore } from './CellStore';
import { cellKey, type Tile } from './Model';
import { compatibleComponents, connectedRegions } from './ComponentTopology';
interface Entry {
    Size: number;
    Chunks: Map<string, number>;
}
/** Derived, incremental membership and contact index. The immutable cells remain authoritative. */
export class ComponentIndex {
    private Source = new CellStore();
    private readonly Entries = new Map<number, Entry>();
    private readonly Contacts = new Map<number, Map<number, number>>();
    constructor(source = new CellStore()) {
        this.Source = source;
        for (const chunk of source.chunks()) {
            const right = source.chunk(chunk.X + 1, chunk.Y), bottom = source.chunk(chunk.X, chunk.Y + 1);
            for (const [index, tile] of chunk.Tiles) {
                this.membership(tile, 1);
                this.contact(tile.componentId, (index % 64 === 63 ? right?.Tiles.get(index - 63) : chunk.Tiles.get(index + 1))?.componentId, 1);
                this.contact(tile.componentId, (index >= 4032 ? bottom?.Tiles.get(index - 4032) : chunk.Tiles.get(index + 64))?.componentId, 1);
            }
        }
    }
    get size() { return this.Entries.size; }
    ids() { return this.Entries.keys(); }
    chunkCount(id: number, key: string) { return this.Entries.get(id)?.Chunks.get(key) ?? 0; }
    count(id: number) { return this.Entries.get(id)?.Size ?? 0; }
    private membership(tile: Tile, delta: number) {
        let entry = this.Entries.get(tile.componentId);
        if (!entry) {
            entry = { Size: 0, Chunks: new Map() };
            this.Entries.set(tile.componentId, entry);
        }
        const key = `${Math.floor(tile.x / 64)},${Math.floor(tile.y / 64)}`, count = (entry.Chunks.get(key) ?? 0) + delta;
        if (count)
            entry.Chunks.set(key, count);
        else
            entry.Chunks.delete(key);
        entry.Size += delta;
        if (!entry.Size)
            this.Entries.delete(tile.componentId);
    }
    private contact(a: number | undefined, b: number | undefined, delta: number) {
        if (!a || !b || a === b)
            return;
        for (const [x, y] of [[a, b], [b, a]]) {
            let contacts = this.Contacts.get(x);
            if (!contacts) {
                contacts = new Map();
                this.Contacts.set(x, contacts);
            }
            const count = (contacts.get(y) ?? 0) + delta;
            if (count)
                contacts.set(y, count);
            else
                contacts.delete(y);
            if (!contacts.size)
                this.Contacts.delete(x);
        }
    }
    sync(source: CellStore) {
        if (source === this.Source)
            return;
        const changes = [...source.changes(this.Source)], edges = new Map<string, [string, string]>();
        for (const change of changes) {
            if (change.before)
                this.membership(change.before, -1);
            if (change.after)
                this.membership(change.after, 1);
            const tile = (change.after ?? change.before)!;
            for (const [dx, dy] of [[-1, 0], [1, 0], [0, -1], [0, 1]]) {
                const other = `${tile.x + dx},${tile.y + dy}`, pair = [change.key, other].sort() as [string, string];
                edges.set(pair.join(':'), pair);
            }
        }
        for (const [a, b] of edges.values()) {
            this.contact(this.Source.get(a)?.componentId, this.Source.get(b)?.componentId, -1);
            this.contact(source.get(a)?.componentId, source.get(b)?.componentId, 1);
        }
        this.Source = source;
    }
    *members(id: number): IterableIterator<Tile> {
        for (const key of this.Entries.get(id)?.Chunks.keys() ?? []) {
            const [x, y] = key.split(',').map(Number);
            for (const tile of this.Source.chunk(x, y)!.Tiles.values())
                if (tile.componentId === id)
                    yield tile;
        }
    }
    sample(id: number) { return this.members(id).next().value as Tile | undefined; }
    neighbors(id: number) { return this.Contacts.get(id)?.keys() ?? [][Symbol.iterator](); }
    connected(ids: readonly number[]) {
        if (!ids.length)
            return true;
        const wanted = new Set(ids), found = new Set([ids[0]]), queue = [ids[0]];
        for (let i = 0; i < queue.length; i++)
            for (const next of this.neighbors(queue[i]))
                if (wanted.has(next) && !found.has(next)) {
                    found.add(next);
                    queue.push(next);
                }
        return found.size === wanted.size;
    }
    canJoin(ids: readonly number[], id: number) {
        const tile = this.sample(id);
        if (!tile)
            return false;
        return !ids.length || (compatibleComponents(this.sample(ids[0])!, tile) && this.connected([...ids, id]));
    }
    normalize(source: CellStore, ids: Iterable<number>, allocate: () => number): CellStore {
        this.sync(source);
        const changes: [string, Tile][] = [];
        for (const id of new Set(ids)) {
            const regions = connectedRegions(this.members(id));
            for (const region of regions.slice(1)) {
                const componentId = allocate();
                for (const tile of region)
                    changes.push([cellKey(tile), { ...tile, componentId }]);
            }
        }
        if (!changes.length)
            return source;
        const result = source.update(changes);
        this.sync(result);
        return result;
    }
}
