import { edgeInGrid, edgeKey, type Grid, type IsolationEdge, type Point } from './Model';
const RootLevel = 26, RootOrigin = -(2 ** 25);
export interface IsolationChunk extends Point { readonly Edges: ReadonlyMap<string, IsolationEdge> }
interface Node { readonly Children?: readonly (Node | undefined)[]; readonly Chunk?: IsolationChunk; readonly Count: number; readonly Bounds: Grid }
function intersects(a: Grid, b: Grid) {
    return a.originX <= b.originX + b.width && b.originX <= a.originX + a.width && a.originY <= b.originY + b.height && b.originY <= a.originY + a.height;
}
function union(bounds: readonly Grid[]): Grid {
    const x = Math.min(...bounds.map(b => b.originX)), y = Math.min(...bounds.map(b => b.originY));
    return { originX: x, originY: y, width: Math.max(...bounds.map(b => b.originX + b.width)) - x, height: Math.max(...bounds.map(b => b.originY + b.height)) - y };
}
function leaf(chunk: IsolationChunk): Node | undefined {
    if (!chunk.Edges.size) return;
    let left = Infinity, top = Infinity, right = -Infinity, bottom = -Infinity;
    for (const edge of chunk.Edges.values()) {
        left = Math.min(left, edge.x); top = Math.min(top, edge.y);
        right = Math.max(right, edge.x + Number(edge.axis === 'horizontal')); bottom = Math.max(bottom, edge.y + Number(edge.axis === 'vertical'));
    }
    return { Chunk: chunk, Count: chunk.Edges.size, Bounds: { originX: left, originY: top, width: right - left, height: bottom - top } };
}
function replace(node: Node | undefined, x: number, y: number, level: number, chunk: IsolationChunk): Node | undefined {
    if (!level) return leaf(chunk);
    const bit = 2 ** (level - 1), index = Math.floor(x / bit) % 2 + 2 * (Math.floor(y / bit) % 2);
    const children = node?.Children ? [...node.Children] : new Array<Node | undefined>(4);
    children[index] = replace(children[index], x, y, level - 1, chunk);
    const present = children.filter((child): child is Node => !!child);
    return present.length ? { Children: children, Count: present.reduce((n, child) => n + child.Count, 0), Bounds: union(present.map(child => child.Bounds)) } : undefined;
}
/** Persistent 64-cell chunks index independent edge segments, including empty space. */
export class IsolationStore {
    constructor(private readonly Root?: Node) {}
    get size() { return this.Root?.Count ?? 0; }
    get Bounds() { return this.Root?.Bounds ?? null; }
    static from(edges: Iterable<IsolationEdge>) { return new IsolationStore().update(edges); }
    chunk(x: number, y: number): IsolationChunk | undefined {
        x -= RootOrigin; y -= RootOrigin;
        if (x < 0 || y < 0 || x >= 2 ** RootLevel || y >= 2 ** RootLevel) return;
        let node = this.Root;
        for (let level = RootLevel; node && level; level--) {
            const bit = 2 ** (level - 1); node = node.Children?.[Math.floor(x / bit) % 2 + 2 * (Math.floor(y / bit) % 2)];
        }
        return node?.Chunk;
    }
    *chunks(bounds?: Grid): IterableIterator<IsolationChunk> {
        function* walk(node: Node | undefined): IterableIterator<IsolationChunk> {
            if (!node || (bounds && !intersects(node.Bounds, bounds))) return;
            if (node.Chunk) yield node.Chunk;
            else for (const child of node.Children!) yield* walk(child);
        }
        yield* walk(this.Root);
    }
    *values(): IterableIterator<IsolationEdge> { for (const chunk of this.chunks()) yield* chunk.Edges.values(); }
    *query(bounds: Grid): IterableIterator<IsolationEdge> {
        for (const chunk of this.chunks(bounds)) for (const edge of chunk.Edges.values()) if (edgeInGrid(edge, bounds)) yield edge;
    }
    get(key: string): IsolationEdge | undefined {
        const [position] = key.split(':'), [x, y] = position.split(',').map(Number);
        return this.chunk(Math.floor(x / 64), Math.floor(y / 64))?.Edges.get(key);
    }
    update(edges: Iterable<IsolationEdge>, remove = false): IsolationStore {
        const dirty = new Map<string, { x: number; y: number; edges: Map<string, IsolationEdge> }>();
        for (const edge of edges) {
            const x = Math.floor(edge.x / 64), y = Math.floor(edge.y / 64), key = edgeKey(edge), id = `${x},${y}`;
            const current = dirty.get(id)?.edges ?? this.chunk(x, y)?.Edges;
            if (remove ? !current?.has(key) : current?.has(key)) continue;
            let chunk = dirty.get(id);
            if (!chunk) { chunk = { x, y, edges: new Map(current) }; dirty.set(id, chunk); }
            if (remove) chunk.edges.delete(key); else chunk.edges.set(key, edge);
        }
        if (!dirty.size) return this;
        let root = this.Root;
        for (const chunk of dirty.values()) root = replace(root, chunk.x - RootOrigin, chunk.y - RootOrigin, RootLevel, { x: chunk.x, y: chunk.y, Edges: chunk.edges });
        return new IsolationStore(root);
    }
}
const Sources = new WeakMap<readonly IsolationEdge[], IsolationStore>();
const Empty = new IsolationStore();
export function isolationSource(item: { isolationEdges?: readonly IsolationEdge[] }): IsolationStore {
    if (!item.isolationEdges?.length) return Empty;
    let source = Sources.get(item.isolationEdges);
    if (!source) { source = IsolationStore.from(item.isolationEdges); Sources.set(item.isolationEdges, source); }
    return source;
}
export function nearestEdge(point: Point): IsolationEdge {
    const x = point.x / 64, y = point.y / 64;
    return Math.abs(x - Math.round(x)) <= Math.abs(y - Math.round(y))
        ? { x: Math.round(x), y: Math.floor(y), axis: 'vertical' } : { x: Math.floor(x), y: Math.round(y), axis: 'horizontal' };
}
export function edgeLine(start: IsolationEdge, point: Point): IsolationEdge[] {
    const end = start.axis === 'horizontal' ? Math.floor(point.x / 64) : Math.floor(point.y / 64);
    const first = start.axis === 'horizontal' ? start.x : start.y;
    return Array.from({ length: Math.abs(end - first) + 1 }, (_, i) => ({ ...start,
        ...(start.axis === 'horizontal' ? { x: Math.min(first, end) + i } : { y: Math.min(first, end) + i }) }));
}
