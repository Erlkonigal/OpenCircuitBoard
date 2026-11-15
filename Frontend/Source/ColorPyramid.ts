import { inkColor, type Point, type Tile } from './Model';
export const ColorSize = 64;
export const MaximumColorLevel = 25;
export interface ColorChunk { x: number; y: number; tiles: Tile[]; states?: Uint8Array }
export interface ColorRequest extends Point { level: number }
type ColorSum = [number, number, number, number];
type ColorSums = Float64Array | Map<number, ColorSum>;
interface ColorNode { Sums: ColorSums; Version: number }
function eachSum(sums: ColorSums, visit: (index: number, red: number, green: number, blue: number, coverage: number) => void) {
    if (sums instanceof Map) for (const [index, sum] of sums) visit(index, ...sum);
    else for (let i = 0; i < sums.length; i += 4) if (sums[i + 3]) visit(i / 4, sums[i], sums[i + 1], sums[i + 2], sums[i + 3]);
}
function compactSums(sums: Map<number, ColorSum>): ColorSums {
    if (sums.size <= 256) return sums;
    const dense = new Float64Array(64 * 64 * 4);
    for (const [index, sum] of sums) dense.set(sum, index * 4);
    return dense;
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
export const colorKey = (level: number, x: number, y: number) => `${level}:${x},${y}`;
/** Each node is a 64x64 grid of exact color/coverage sums, never a raster of the full board. */
export class ColorPyramid {
    private readonly Nodes = new Map<string, ColorNode>();
    private Version = 0;
    clear() { this.Nodes.clear(); }
    update(chunks: readonly ColorChunk[]) {
        let dirty = new Map<string, Point>();
        for (const chunk of chunks) {
            const sums = new Map<number, ColorSum>();
            for (let i = 0; i < chunk.tiles.length; i++) {
                const tile = chunk.tiles[i], index = (tile.y - chunk.y * 64) * 64 + tile.x - chunk.x * 64;
                const color = tileColor(tile, chunk.states ? !!chunk.states[i] : tile.isOn);
                sums.set(index, [color[0], color[1], color[2], 1]);
            }
            const key = colorKey(0, chunk.x, chunk.y);
            if (chunk.tiles.length) this.Nodes.set(key, { Sums: compactSums(sums), Version: ++this.Version });
            else this.Nodes.delete(key);
            dirty.set(key, chunk);
        }
        for (let level = 1; level <= MaximumColorLevel && dirty.size; level++) {
            const parents = new Map<string, Point>();
            for (const point of dirty.values()) {
                const x = Math.floor(point.x / 2), y = Math.floor(point.y / 2);
                parents.set(colorKey(level, x, y), { x, y });
            }
            for (const [key, { x, y }] of parents) {
                const sums = new Map<number, ColorSum>();
                for (let qy = 0; qy < 2; qy++) for (let qx = 0; qx < 2; qx++) {
                    const child = this.Nodes.get(colorKey(level - 1, x * 2 + qx, y * 2 + qy));
                    if (!child) continue;
                    eachSum(child.Sums, (index, red, green, blue, coverage) => {
                        const px = Math.floor(index % 64 / 2) + qx * 32, py = Math.floor(index / 128) + qy * 32, out = py * 64 + px;
                        const sum = sums.get(out);
                        if (sum) { sum[0] += red; sum[1] += green; sum[2] += blue; sum[3] += coverage; }
                        else sums.set(out, [red, green, blue, coverage]);
                    });
                }
                if (sums.size) this.Nodes.set(key, { Sums: compactSums(sums), Version: ++this.Version });
                else this.Nodes.delete(key);
            }
            dirty = parents;
        }
    }
    raster(request: ColorRequest): { key: string; version: number; pixels: Uint8Array } {
        const key = colorKey(request.level, request.x, request.y), node = this.Nodes.get(key), pixels = new Uint8Array(64 * 64 * 4);
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
