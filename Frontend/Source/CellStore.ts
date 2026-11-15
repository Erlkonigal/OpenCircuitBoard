import { cellKey, contains, parseKey, type Grid, type Point, type Tile } from './Model';

export const ChunkSize = 64;
const RootLevel = 26;
const RootOrigin = -(2 ** 25);
export interface CellChunk {
    readonly X: number;
    readonly Y: number;
    readonly Tiles: ReadonlyMap<number, Tile>;
    readonly Rows: Uint32Array;
    readonly Bounds: Grid;
}
interface Node {
    readonly Children?: readonly (Node | undefined)[];
    readonly Chunk?: CellChunk;
    readonly Bounds: Grid;
    readonly Count: number;
}
export interface CellChange { key: string; before?: Tile; after?: Tile }
export interface CellBlock extends Point { level: number }
export function intersects(a: Grid, b: Grid) {
    return a.originX < b.originX + b.width && b.originX < a.originX + a.width
        && a.originY < b.originY + b.height && b.originY < a.originY + a.height;
}
function union(bounds: readonly Grid[]): Grid {
    const x = Math.min(...bounds.map(b => b.originX)), y = Math.min(...bounds.map(b => b.originY));
    return { originX: x, originY: y, width: Math.max(...bounds.map(b => b.originX + b.width)) - x, height: Math.max(...bounds.map(b => b.originY + b.height)) - y };
}
function chunkFor(x: number, y: number, tiles: ReadonlyMap<number, Tile>): CellChunk | undefined {
    if (!tiles.size) return;
    const rows = new Uint32Array(128);
    let left = Infinity, top = Infinity, right = -Infinity, bottom = -Infinity;
    for (const [index, tile] of tiles) {
        const lx = index % 64, ly = Math.floor(index / 64);
        rows[ly * 2 + (lx >>> 5)] |= 1 << (lx & 31);
        left = Math.min(left, tile.x); top = Math.min(top, tile.y);
        right = Math.max(right, tile.x); bottom = Math.max(bottom, tile.y);
    }
    return { X: x, Y: y, Tiles: tiles, Rows: rows, Bounds: { originX: left, originY: top, width: right - left + 1, height: bottom - top + 1 } };
}
function replace(node: Node | undefined, x: number, y: number, level: number, chunk: CellChunk | undefined): Node | undefined {
    if (!level) return chunk ? { Chunk: chunk, Bounds: chunk.Bounds, Count: chunk.Tiles.size } : undefined;
    const bit = 2 ** (level - 1), index = (Math.floor(x / bit) % 2) + 2 * (Math.floor(y / bit) % 2);
    const children = node?.Children ? [...node.Children] : new Array<Node | undefined>(4);
    children[index] = replace(children[index], x, y, level - 1, chunk);
    const present = children.filter((child): child is Node => !!child);
    return present.length ? { Children: children, Bounds: union(present.map(child => child.Bounds)), Count: present.reduce((n, child) => n + child.Count, 0) } : undefined;
}
function find(root: Node | undefined, x: number, y: number): CellChunk | undefined {
    x -= RootOrigin; y -= RootOrigin;
    if (x < 0 || y < 0 || x >= 2 ** RootLevel || y >= 2 ** RootLevel) return;
    let node = root;
    for (let level = RootLevel; node && level; level--) {
        const bit = 2 ** (level - 1);
        node = node.Children?.[Math.floor(x / bit) % 2 + 2 * (Math.floor(y / bit) % 2)];
    }
    return node?.Chunk;
}
/** Persistent sparse quadtree. Transactions copy affected chunks and their paths only. */
export class CellStore implements ReadonlyMap<string, Tile> {
    readonly [Symbol.toStringTag] = 'CellStore';
    constructor(private readonly Root?: Node, readonly Identity: object = {}) { }
    get size() { return this.Root?.Count ?? 0; }
    get Bounds() { return this.Root?.Bounds ?? null; }
    static from(tiles: Iterable<Tile>) { return new CellStore().update((function* () { for (const tile of tiles) yield [cellKey(tile), tile] as const; })()); }
    chunk(x: number, y: number) { return find(this.Root, x, y); }
    get(key: string) {
        const { x, y } = parseKey(key), cx = Math.floor(x / 64), cy = Math.floor(y / 64);
        return this.chunk(cx, cy)?.Tiles.get((y - cy * 64) * 64 + x - cx * 64);
    }
    has(key: string) { return this.get(key) !== undefined; }
    *chunks(bounds?: Grid): IterableIterator<CellChunk> {
        function* walk(node: Node | undefined): IterableIterator<CellChunk> {
            if (!node || (bounds && !intersects(node.Bounds, bounds))) return;
            if (node.Chunk) yield node.Chunk;
            else for (const child of node.Children!) yield* walk(child);
        }
        yield* walk(this.Root);
    }
    *blocks(bounds: Grid, level: number): IterableIterator<CellBlock> {
        const target = Math.max(0, Math.min(25, level));
        function* walk(node: Node | undefined, depth: number, x: number, y: number): IterableIterator<CellBlock> {
            if (!node || !intersects(node.Bounds, bounds)) return;
            if (depth === target) { yield { x: Math.floor(x / 2 ** depth), y: Math.floor(y / 2 ** depth), level: depth }; return; }
            const half = 2 ** (depth - 1);
            for (let i = 0; i < 4; i++) yield* walk(node.Children?.[i], depth - 1, x + (i % 2) * half, y + Math.floor(i / 2) * half);
        }
        yield* walk(this.Root, RootLevel, RootOrigin, RootOrigin);
    }
    *query(bounds: Grid): IterableIterator<Tile> {
        for (const chunk of this.chunks(bounds)) for (const tile of chunk.Tiles.values()) if (contains(bounds, tile)) yield tile;
    }
    *values(): MapIterator<Tile> { for (const chunk of this.chunks()) yield* chunk.Tiles.values(); }
    *keys(): MapIterator<string> { for (const tile of this.values()) yield cellKey(tile); }
    *entries(): MapIterator<[string, Tile]> { for (const tile of this.values()) yield [cellKey(tile), tile]; }
    [Symbol.iterator]() { return this.entries(); }
    forEach(callback: (value: Tile, key: string, map: ReadonlyMap<string, Tile>) => void, thisArg?: unknown) {
        for (const tile of this.values()) callback.call(thisArg, tile, cellKey(tile), this);
    }
    update(changes: Iterable<readonly [string, Tile | undefined]>): CellStore {
        const dirty = new Map<string, { x: number; y: number; tiles: Map<number, Tile> }>();
        for (const [key, tile] of changes) {
            const { x, y } = parseKey(key), cx = Math.floor(x / 64), cy = Math.floor(y / 64), id = `${cx},${cy}`;
            let chunk = dirty.get(id);
            if (!chunk) { chunk = { x: cx, y: cy, tiles: new Map(this.chunk(cx, cy)?.Tiles) }; dirty.set(id, chunk); }
            const index = (y - cy * 64) * 64 + x - cx * 64;
            if (tile) chunk.tiles.set(index, tile); else chunk.tiles.delete(index);
        }
        if (!dirty.size) return this;
        let root = this.Root;
        for (const { x, y, tiles } of dirty.values()) root = replace(root, x - RootOrigin, y - RootOrigin, RootLevel, chunkFor(x, y, tiles));
        return new CellStore(root, this.Identity);
    }
    *changedChunks(before: CellStore): IterableIterator<{ x: number; y: number; chunk?: CellChunk; before?: CellChunk }> {
        function* walk(a: Node | undefined, b: Node | undefined, level: number, x: number, y: number): IterableIterator<{ x: number; y: number; chunk?: CellChunk; before?: CellChunk }> {
            if (a === b) return;
            if (!level) { yield { x, y, chunk: a?.Chunk, before: b?.Chunk }; return; }
            const half = 2 ** (level - 1);
            for (let i = 0; i < 4; i++) yield* walk(a?.Children?.[i], b?.Children?.[i], level - 1, x + (i % 2) * half, y + Math.floor(i / 2) * half);
        }
        yield* walk(this.Root, before.Root, RootLevel, RootOrigin, RootOrigin);
    }
    *changes(before: CellStore): IterableIterator<CellChange> {
        for (const chunk of this.changedChunks(before)) {
            const keys = new Set([...(chunk.before?.Tiles.keys() ?? []), ...(chunk.chunk?.Tiles.keys() ?? [])]);
            for (const index of keys) {
                const a = chunk.before?.Tiles.get(index), b = chunk.chunk?.Tiles.get(index);
                if (a !== b && JSON.stringify(a) !== JSON.stringify(b)) yield { key: cellKey((a ?? b)!), before: a, after: b };
            }
        }
    }
    private word(x: number, y: number): number {
        const cx = Math.floor(x / 2), cy = Math.floor(y / 64);
        return this.chunk(cx, cy)?.Rows[(y - cy * 64) * 2 + x - cx * 2] ?? 0;
    }
    overlaps(target: CellStore, offset: Point, excluded?: CellStore): boolean {
        const bounds = target.Bounds;
        if (!bounds) return false;
        const localBounds = { ...bounds, originX: bounds.originX - offset.x, originY: bounds.originY - offset.y };
        for (const chunk of this.chunks(localBounds)) for (let row = 0; row < 64; row++) for (let word = 0; word < 2; word++) {
            const bits = chunk.Rows[row * 2 + word];
            if (!bits) continue;
            const x = chunk.X * 64 + word * 32 + offset.x, y = chunk.Y * 64 + row + offset.y;
            const wx = Math.floor(x / 32), shift = x - wx * 32;
            const first = target.word(wx, y) & ~(excluded?.word(wx, y) ?? 0);
            if ((bits << shift) & first) return true;
            if (shift && ((bits >>> (32 - shift)) & (target.word(wx + 1, y) & ~(excluded?.word(wx + 1, y) ?? 0)))) return true;
        }
        return false;
    }
}
const Sources = new WeakMap<readonly Tile[], CellStore>();
export function inkSource(item: { tiles: readonly Tile[] }): CellStore {
    let source = Sources.get(item.tiles);
    if (!source) { source = CellStore.from(item.tiles); Sources.set(item.tiles, source); }
    return source;
}
