import { BufferImageSource, Container, Graphics, Sprite, Texture } from 'pixi.js';
import { CellStore } from './CellStore';
import { ComponentIndex } from './ComponentIndex';
import { colorKey, colorLevel, tileColor } from './ColorPyramid';
import { CellSize } from './TileGeometry';
import type { Grid } from './Model';
import type { RuntimeGrid } from './EditorStore';
import type { TileView } from './TileRenderer';
const UnderlayColor = 0x0b1220;
const SelectionColor = 0x8bdcff;
const LightTint = 0xf0f8ff;
const PaleTint = 0x5a9fd8;
function strokeEdges(graphics: Graphics, edges: readonly number[], color: number, width: number) {
    for (let i = 0; i < edges.length; i += 4)
        graphics.moveTo(edges[i], edges[i + 1]).lineTo(edges[i + 2], edges[i + 3]);
    graphics.stroke({ color, width, cap: 'butt', join: 'round' });
}
/** Whole-surface emphasis, cached by membership, palette and view. No outlines or per-cell display objects. */
export class ComponentHighlight {
    readonly Layer = new Container();
    private readonly Detail = new Graphics();
    private readonly Rasters = new Map<string, Sprite>();
    private Source?: CellStore;
    private Signature = '';
    private Camera = '';
    private readonly Strength: number;
    Count = 0;
    constructor(kind: 'hover' | 'selected') {
        this.Strength = kind === 'hover' ? .16 : .32;
        this.Layer.addChild(this.Detail);
    }
    draw(source: CellStore, index: ComponentIndex, ids: readonly number[], view: TileView, runtime: RuntimeGrid | null = null) {
        const paleIds = new Set<number>();
        for (const id of ids) {
            const tile = index.sample(id);
            if (!tile) continue;
            const x = runtime ? tile.x - runtime.originX : -1, y = runtime ? tile.y - runtime.originY : -1;
            const on = runtime && x >= 0 && x < runtime.width && y >= 0 && y < runtime.height ? !!runtime.states[y * runtime.width + x] : tile.isOn;
            const [r, g, b] = tileColor(tile, on);
            // Near-white surfaces need a blue tint; white-on-white would disappear.
            if (r * .2126 + g * .7152 + b * .0722 > 220) paleIds.add(id);
        }
        const signature = `${ids.slice().sort((a, b) => a - b).join(',')}:${[...paleIds].sort((a, b) => a - b).join(',')}`;
        if (source !== this.Source || signature !== this.Signature) {
            this.clear(); this.Source = source; this.Signature = signature;
        }
        this.Layer.visible = ids.length > 0;
        if (!ids.length) return;
        const camera = `${view.x}:${view.y}:${view.zoom}:${view.width}:${view.height}`;
        if (camera === this.Camera) return;
        this.Camera = camera;
        const wantedIds = new Set(ids), px = view.zoom * CellSize;
        const bounds = { originX: Math.floor((view.x - view.width / (2 * view.zoom)) / CellSize) - 1,
            originY: Math.floor((view.y - view.height / (2 * view.zoom)) / CellSize) - 1,
            width: Math.ceil(view.width / view.zoom / CellSize) + 3, height: Math.ceil(view.height / view.zoom / CellSize) + 3 };
        this.Detail.clear(); this.Detail.visible = px >= 12;
        if (px >= 12) {
            for (const sprite of this.Rasters.values()) sprite.visible = false;
            const tiles = [...source.query(bounds)].filter(tile => wantedIds.has(tile.componentId));
            for (const pale of [false, true]) {
                for (const tile of tiles) if (paleIds.has(tile.componentId) === pale)
                    this.Detail.rect(tile.x * CellSize, tile.y * CellSize, CellSize, CellSize);
                this.Detail.fill({ color: pale ? PaleTint : LightTint, alpha: this.Strength });
            }
            this.Count = 1;
            return;
        }
        const level = colorLevel(px), step = 2 ** level, span = 64 * step, wanted = new Set<string>();
        for (const block of source.blocks(bounds, level)) {
            const key = colorKey(level, block.x, block.y);
            wanted.add(key);
            let sprite = this.Rasters.get(key);
            if (!sprite) {
                const sums = new Float64Array(4096), pales = new Float64Array(4096), left = block.x * span, top = block.y * span;
                for (const chunk of source.chunks({ originX: left, originY: top, width: span, height: span })) {
                    const chunkKey = `${chunk.X},${chunk.Y}`;
                    let coverage = 0, paleCount = 0;
                    if (wantedIds.size === index.size) coverage = chunk.Tiles.size;
                    else if (wantedIds.size > chunk.Tiles.size) {
                        for (const tile of chunk.Tiles.values()) if (wantedIds.has(tile.componentId)) coverage++;
                    }
                    else for (const id of wantedIds) coverage += index.chunkCount(id, chunkKey);
                    if (!coverage) continue;
                    for (const id of paleIds) paleCount += index.chunkCount(id, chunkKey);
                    if (coverage === 4096 && (paleCount === 0 || paleCount === 4096)) {
                        const x = chunk.X * 64 - left, y = chunk.Y * 64 - top;
                        for (let py = Math.floor(y / step); py < Math.ceil((y + 64) / step); py++)
                            for (let px = Math.floor(x / step); px < Math.ceil((x + 64) / step); px++) {
                                sums[py * 64 + px] += Math.min(step, 64) ** 2;
                                if (paleCount) pales[py * 64 + px] += Math.min(step, 64) ** 2;
                            }
                    }
                    else for (const tile of chunk.Tiles.values()) if (wantedIds.has(tile.componentId)) {
                        const offset = Math.floor((tile.y - top) / step) * 64 + Math.floor((tile.x - left) / step);
                        sums[offset]++;
                        if (paleIds.has(tile.componentId)) pales[offset]++;
                    }
                }
                const pixels = new Uint8Array(16384);
                for (let i = 0; i < 4096; i++) if (sums[i]) {
                    const pale = pales[i] / sums[i];
                    for (const [channel, shift] of [16, 8, 0].entries())
                        pixels[i * 4 + channel] = Math.round(((LightTint >> shift) & 255) * (1 - pale) + ((PaleTint >> shift) & 255) * pale);
                    pixels[i * 4 + 3] = Math.round(255 * this.Strength * Math.min(1, sums[i] / (step * step)));
                }
                const texture = new Texture({ source: new BufferImageSource({ resource: pixels, width: 64, height: 64, format: 'rgba8unorm', alphaMode: 'no-premultiply-alpha', scaleMode: 'nearest' }) });
                sprite = new Sprite(texture);
                sprite.position.set(left * CellSize, top * CellSize); sprite.scale.set(step * CellSize);
                this.Rasters.set(key, sprite); this.Layer.addChild(sprite);
            }
            sprite.visible = true;
        }
        for (const [key, sprite] of this.Rasters) if (!wanted.has(key)) {
            sprite.texture.destroy(true); sprite.destroy(); this.Rasters.delete(key);
        }
        this.Count = this.Rasters.size;
    }
    clear() {
        this.Layer.visible = false; this.Count = 0; this.Camera = ''; this.Detail.clear();
        for (const sprite of this.Rasters.values()) { sprite.texture.destroy(true); sprite.destroy(); }
        this.Rasters.clear();
    }
    destroy() { this.clear(); this.Layer.destroy({ children: true }); }
}
/** The overlay uses camera-relative world coordinates; all decoration sizes are CSS pixels. */
export function drawMarquee(graphics: Graphics, bounds: Grid, view: TileView) {
    const x = bounds.originX * CellSize - view.x, y = bounds.originY * CellSize - view.y;
    const width = bounds.width * CellSize, height = bounds.height * CellSize, edges: number[] = [];
    graphics.rect(x, y, width, height).fill({ color: SelectionColor, alpha: .04 });
    const corners = [[x, y], [x + width, y], [x + width, y + height], [x, y + height]];
    let phase = 0;
    for (let i = 0; i < 4; i++) {
        const [ax, ay] = corners[i], [bx, by] = corners[(i + 1) % 4];
        const length = Math.hypot(bx - ax, by - ay), screenLength = length * view.zoom;
        for (let offset = -phase; offset < screenLength; offset += 10) {
            const from = Math.max(0, offset) / screenLength, to = Math.min(screenLength, offset + 6) / screenLength;
            if (to > from) edges.push(ax + (bx - ax) * from, ay + (by - ay) * from, ax + (bx - ax) * to, ay + (by - ay) * to);
        }
        phase = (phase + screenLength) % 10;
        const corner = Math.min(8 / view.zoom, length / 2) / length;
        edges.push(ax, ay, ax + (bx - ax) * corner, ay + (by - ay) * corner,
            bx, by, bx - (bx - ax) * corner, by - (by - ay) * corner);
    }
    strokeEdges(graphics, edges, UnderlayColor, 3.5 / view.zoom);
    strokeEdges(graphics, edges, SelectionColor, 1.5 / view.zoom);
}
