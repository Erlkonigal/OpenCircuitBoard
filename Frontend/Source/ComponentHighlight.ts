import { BufferImageSource, Container, Graphics, Sprite, Texture } from 'pixi.js';
import { CellStore } from './CellStore';
import { ComponentIndex } from './ComponentIndex';
import { colorKey, colorLevel } from './ColorPyramid';
import { CellSize } from './TileGeometry';
import type { TileView } from './TileRenderer';
/** Transient coverage masks. Dense, fully selected chunks never expand into per-cell objects. */
export class ComponentHighlight {
    readonly Layer = new Container();
    private readonly Detail = new Graphics();
    private readonly Rasters = new Map<string, Sprite>();
    private Source?: CellStore;
    private Signature = '';
    Count = 0;
    constructor(private readonly Color: number) { this.Layer.addChild(this.Detail); }
    draw(source: CellStore, index: ComponentIndex, ids: readonly number[], view: TileView) {
        const signature = ids.slice().sort((a, b) => a - b).join(',');
        if (source !== this.Source || signature !== this.Signature) {
            this.clear();
            this.Source = source;
            this.Signature = signature;
        }
        this.Layer.visible = ids.length > 0;
        if (!ids.length)
            return;
        const wantedIds = new Set(ids), px = view.zoom * CellSize;
        const bounds = { originX: Math.floor((view.x - view.width / (2 * view.zoom)) / CellSize) - 1,
            originY: Math.floor((view.y - view.height / (2 * view.zoom)) / CellSize) - 1,
            width: Math.ceil(view.width / view.zoom / CellSize) + 3, height: Math.ceil(view.height / view.zoom / CellSize) + 3 };
        this.Detail.clear();
        this.Detail.visible = px >= 12;
        if (px >= 12) {
            for (const sprite of this.Rasters.values())
                sprite.visible = false;
            for (const tile of source.query(bounds))
                if (wantedIds.has(tile.componentId))
                    this.Detail.rect(tile.x * CellSize, tile.y * CellSize, CellSize, CellSize);
            this.Detail.fill({ color: this.Color, alpha: .20 });
            for (const tile of source.query(bounds))
                if (wantedIds.has(tile.componentId)) {
                    const x = tile.x * CellSize, y = tile.y * CellSize;
                    for (const [dx, dy, ax, ay, bx, by] of [[-1, 0, x, y, x, y + CellSize], [1, 0, x + CellSize, y, x + CellSize, y + CellSize],
                        [0, -1, x, y, x + CellSize, y], [0, 1, x, y + CellSize, x + CellSize, y + CellSize]]) {
                        if (source.get(`${tile.x + dx},${tile.y + dy}`)?.componentId !== tile.componentId)
                            this.Detail.moveTo(ax, ay).lineTo(bx, by);
                    }
                }
            this.Detail.stroke({ color: this.Color, width: 1.5 / view.zoom });
            this.Count = 1;
            return;
        }
        const level = colorLevel(px), step = 2 ** level, span = 64 * step, wanted = new Set<string>();
        for (const block of source.blocks(bounds, level)) {
            const key = colorKey(level, block.x, block.y);
            wanted.add(key);
            let sprite = this.Rasters.get(key);
            if (!sprite) {
                const sums = new Float64Array(4096), left = block.x * span, top = block.y * span;
                for (const chunk of source.chunks({ originX: left, originY: top, width: span, height: span })) {
                    const chunkKey = `${chunk.X},${chunk.Y}`;
                    let coverage = 0;
                    if (wantedIds.size === index.size) coverage = chunk.Tiles.size;
                    else if (wantedIds.size > chunk.Tiles.size) {
                        for (const tile of chunk.Tiles.values()) if (wantedIds.has(tile.componentId)) coverage++;
                    } else for (const id of wantedIds) coverage += index.chunkCount(id, chunkKey);
                    if (!coverage)
                        continue;
                    if (coverage === 4096) {
                        // Whole chunks can accumulate their exact coverage without visiting their cells.
                        const x = chunk.X * 64 - left, y = chunk.Y * 64 - top;
                        for (let py = Math.floor(y / step); py < Math.ceil((y + 64) / step); py++)
                            for (let px = Math.floor(x / step); px < Math.ceil((x + 64) / step); px++)
                                sums[py * 64 + px] += Math.min(step, 64) ** 2;
                    }
                    else
                        for (const tile of chunk.Tiles.values())
                            if (wantedIds.has(tile.componentId))
                                sums[Math.floor((tile.y - top) / step) * 64 + Math.floor((tile.x - left) / step)]++;
                }
                const pixels = new Uint8Array(16384);
                for (let i = 0; i < 4096; i++)
                    if (sums[i]) {
                        pixels[i * 4] = (this.Color >> 16) & 255;
                        pixels[i * 4 + 1] = (this.Color >> 8) & 255;
                        pixels[i * 4 + 2] = this.Color & 255;
                        pixels[i * 4 + 3] = Math.round(96 * Math.min(1, sums[i] / (step * step)));
                    }
                const texture = new Texture({ source: new BufferImageSource({ resource: pixels, width: 64, height: 64, format: 'rgba8unorm', alphaMode: 'no-premultiply-alpha', scaleMode: 'nearest' }) });
                sprite = new Sprite(texture);
                sprite.position.set(left * CellSize, top * CellSize);
                sprite.scale.set(step * CellSize);
                this.Rasters.set(key, sprite);
                this.Layer.addChild(sprite);
            }
            sprite.visible = true;
        }
        for (const [key, sprite] of this.Rasters)
            if (!wanted.has(key)) {
                sprite.texture.destroy(true);
                sprite.destroy();
                this.Rasters.delete(key);
            }
        this.Count = this.Rasters.size;
    }
    clear() {
        this.Layer.visible = false;
        this.Count = 0;
        this.Detail.clear();
        for (const sprite of this.Rasters.values()) {
            sprite.texture.destroy(true);
            sprite.destroy();
        }
        this.Rasters.clear();
    }
    destroy() { this.clear(); this.Layer.destroy({ children: true }); }
}
