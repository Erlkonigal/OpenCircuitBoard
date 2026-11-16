import { inkColor, type Point, type Tile } from './Model';
export const ColorSize = 64;
export const MaximumColorLevel = 25;
export interface ColorChunk { x: number; y: number; tiles: Tile[]; states?: Uint8Array }
export interface ColorStateChunk extends Point { states: Uint8Array }
export interface ColorRequest extends Point { level: number }
type ColorSum = [number, number, number, number];
type ColorSums = Float64Array | Map<number, ColorSum>;
interface ColorNode { Sums: ColorSums; Version: number }
interface ColorSource { Indices: Uint16Array; On: Uint32Array; Off: Uint32Array; States: Uint8Array }
function eachSum(sums: ColorSums, visit: (index: number, red: number, green: number, blue: number, coverage: number) => void) {
    if (sums instanceof Map) for (const [index, sum] of sums) visit(index, ...sum);
    else for (let i = 0; i < sums.length; i += 4) if (sums[i + 3]) visit(i / 4, sums[i], sums[i + 1], sums[i + 2], sums[i + 3]);
}
function compactSums(sums: Float64Array): ColorSums {
    let count = 0;
    for (let i = 3; i < sums.length; i += 4) if (sums[i] && ++count > 256) return sums;
    const sparse = new Map<number, ColorSum>();
    eachSum(sums, (index, red, green, blue, coverage) => sparse.set(index, [red, green, blue, coverage]));
    return sparse;
}
const Colors = new Map<string, number[]>();
export function tileColor(tile: Tile, state = tile.isOn): number[] {
    const id = `${tile.toolId}:${state}`;
    let color = Colors.get(id);
    if (!color) {
        const value = parseInt(inkColor(tile.toolId).slice(1), 16), board = 0x101a23;
        color = [16, 8, 0].map(shift => state ? (value >> shift) & 255 : Math.round(((board >> shift) & 255) * .72 + ((value >> shift) & 255) * .28));
        Colors.set(id, color);
    }
    return color;
}
function packedColor(tile: Tile, on: boolean) { const [red, green, blue] = tileColor(tile, on); return red << 16 | green << 8 | blue; }
function setColor(sums: ColorSums, index: number, color: number) {
    const red = color >> 16 & 255, green = color >> 8 & 255, blue = color & 255;
    if (sums instanceof Map) sums.set(index, [red, green, blue, 1]);
    else { const offset = index * 4; sums[offset] = red; sums[offset + 1] = green; sums[offset + 2] = blue; sums[offset + 3] = 1; }
}
/** A visible color chunk can update in the same display frame as detailed cells. */
export class ColorRaster {
    readonly Pixels = new Uint8Array(64 * 64 * 4);
    private readonly On = new Uint32Array(64 * 64);
    private readonly Off = new Uint32Array(64 * 64);
    readonly Bytes = this.Pixels.byteLength + this.On.byteLength + this.Off.byteLength;
    constructor(private readonly Tiles: ReadonlyMap<number, Tile>) {
        for (const [index, tile] of Tiles) { this.On[index] = packedColor(tile, true); this.Off[index] = packedColor(tile, false); this.Pixels[index * 4 + 3] = 255; }
    }
    update(stateFor: (tile: Tile) => boolean) {
        let start = this.Pixels.length / 4, end = 0;
        for (const [index, tile] of this.Tiles) {
            const color = stateFor(tile) ? this.On[index] : this.Off[index], offset = index * 4;
            const red = color >> 16 & 255, green = color >> 8 & 255, blue = color & 255;
            if (this.Pixels[offset] === red && this.Pixels[offset + 1] === green && this.Pixels[offset + 2] === blue) continue;
            this.Pixels[offset] = red; this.Pixels[offset + 1] = green; this.Pixels[offset + 2] = blue;
            start = Math.min(start, index); end = Math.max(end, index + 1);
        }
        return { start, end };
    }
}
export const colorKey = (level: number, x: number, y: number) => `${level}:${x},${y}`;
/** Each node is a 64x64 grid of exact color/coverage sums, never a raster of the full board. */
export class ColorPyramid {
    private readonly Nodes = new Map<string, ColorNode>();
    private readonly Sources = new Map<string, ColorSource>();
    private readonly Dirty = Array.from({ length: MaximumColorLevel + 1 }, () => new Set<string>());
    private Version = 0;
    clear() { this.Nodes.clear(); this.Sources.clear(); for (const dirty of this.Dirty) dirty.clear(); }
    private invalidate(x: number, y: number) {
        for (let level = 1; level <= MaximumColorLevel; level++) {
            x = Math.floor(x / 2); y = Math.floor(y / 2);
            this.Dirty[level].add(colorKey(level, x, y));
        }
    }
    update(chunks: readonly ColorChunk[]) {
        for (const chunk of chunks) {
            const key = colorKey(0, chunk.x, chunk.y);
            if (!chunk.tiles.length) { this.Nodes.delete(key); this.Sources.delete(key); this.invalidate(chunk.x, chunk.y); continue; }
            const count = chunk.tiles.length, sums: ColorSums = count > 256 ? new Float64Array(64 * 64 * 4) : new Map();
            const source: ColorSource = { Indices: new Uint16Array(count), On: new Uint32Array(count), Off: new Uint32Array(count), States: new Uint8Array(count) };
            for (let i = 0; i < count; i++) {
                const tile = chunk.tiles[i], index = (tile.y - chunk.y * 64) * 64 + tile.x - chunk.x * 64;
                source.Indices[i] = index; source.On[i] = packedColor(tile, true); source.Off[i] = packedColor(tile, false);
                source.States[i] = chunk.states ? chunk.states[i] : Number(tile.isOn);
                setColor(sums, index, source.States[i] ? source.On[i] : source.Off[i]);
            }
            this.Sources.set(key, source); this.Nodes.set(key, { Sums: sums, Version: ++this.Version });
            this.invalidate(chunk.x, chunk.y);
        }
    }
    updateStates(chunks: readonly ColorStateChunk[]) {
        for (const chunk of chunks) {
            const key = colorKey(0, chunk.x, chunk.y), source = this.Sources.get(key), node = this.Nodes.get(key);
            if (!source || !node || source.States.length !== chunk.states.length) throw Error('Color chunk state mismatch');
            let changed = false;
            for (let i = 0; i < chunk.states.length; i++) {
                const state = chunk.states[i];
                if (source.States[i] === state) continue;
                source.States[i] = state; changed = true;
                setColor(node.Sums, source.Indices[i], state ? source.On[i] : source.Off[i]);
            }
            if (changed) { node.Version = ++this.Version; this.invalidate(chunk.x, chunk.y); }
        }
    }
    private node(level: number, x: number, y: number): ColorNode | undefined {
        const key = colorKey(level, x, y);
        if (!level || !this.Dirty[level].delete(key)) return this.Nodes.get(key);
        // Runtime updates only rebuild ancestors requested by a visible raster.
        // Dense reductions use typed arrays instead of allocating a Map entry per cell.
        const sums = new Float64Array(64 * 64 * 4);
        let occupied = false;
        for (let qy = 0; qy < 2; qy++) for (let qx = 0; qx < 2; qx++) {
            const child = this.node(level - 1, x * 2 + qx, y * 2 + qy);
            if (!child) continue;
            occupied = true;
            eachSum(child.Sums, (index, red, green, blue, coverage) => {
                const offset = (Math.floor(index / 128) + qy * 32) * 256 + (Math.floor(index % 64 / 2) + qx * 32) * 4;
                sums[offset] += red; sums[offset + 1] += green; sums[offset + 2] += blue; sums[offset + 3] += coverage;
            });
        }
        if (!occupied) { this.Nodes.delete(key); return; }
        const node = { Sums: compactSums(sums), Version: ++this.Version };
        this.Nodes.set(key, node); return node;
    }
    raster(request: ColorRequest): { key: string; version: number; pixels: Uint8Array } {
        const key = colorKey(request.level, request.x, request.y), node = this.node(request.level, request.x, request.y), pixels = new Uint8Array(64 * 64 * 4);
        if (node) {
            const area = 4 ** request.level;
            eachSum(node.Sums, (index, red, green, blue, coverage) => {
                pixels[index * 4] = Math.round(red / area);
                pixels[index * 4 + 1] = Math.round(green / area);
                pixels[index * 4 + 2] = Math.round(blue / area);
                pixels[index * 4 + 3] = Math.round(coverage / area * 255);
            });
        }
        return { key, version: node?.Version ?? 0, pixels };
    }
}
export function colorLevel(pixelsPerCell: number) { return Math.max(0, Math.min(MaximumColorLevel, Math.ceil(Math.log2(1 / pixelsPerCell)))); }
export function detailLevel(pixelsPerCell: number): 'detail' | 'color' | 'aggregate' { return pixelsPerCell >= 12 ? 'detail' : pixelsPerCell >= 2 ? 'color' : 'aggregate'; }
