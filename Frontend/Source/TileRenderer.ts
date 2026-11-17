import { AlphaFilter, Assets, BlurFilter, Container, FillGradient, Graphics, Matrix, Rectangle, RenderTexture, Sprite, type Renderer, type Texture } from 'pixi.js';
import { cellKey, hasGlyph, iconUrl, inkColor, type Tile, type RenderMode } from './Model';
import { CellStore, type CellChunk } from './CellStore';
import { ColorCache } from './ColorCache';
import { HighlightTint, HighlightStrength } from './HighlightStyle';
import { colorKey, colorLevel, detailLevel } from './ColorPyramid';
import type { RuntimeGrid } from './EditorStore';
import { BottomFace, CellSize, Extrusion, LeftFace, ShadowMargin } from './TileGeometry';

export interface TileView {
    x: number;
    y: number;
    zoom: number;
    width: number;
    height: number;
}
export interface TileScene {
    occupied: CellStore;
    highlighted?: readonly number[];
    preview: import('./EditorStore').PlacementPreview | null;
    previewValid: boolean;
    simulating: boolean;
    runtime: RuntimeGrid | null;
    mode: RenderMode;
}
function runtimeStamp(runtime: RuntimeGrid | null, x: number, y: number): unknown {
    if (!runtime?.chunkVersions) return runtime;
    const cx = Math.floor(runtime.originX / 64), cy = Math.floor(runtime.originY / 64);
    const width = Math.floor((runtime.originX + runtime.width - 1) / 64) - cx + 1;
    const height = Math.floor((runtime.originY + runtime.height - 1) / 64) - cy + 1;
    return `${runtime.generation}:${x >= cx && x < cx + width && y >= cy && y < cy + height ? runtime.chunkVersions[(y - cy) * width + x - cx] : 0}`;
}
interface Material {
    Top: Texture;
    Gradients: FillGradient[];
    Tool: string;
    On: boolean;
    Direction: number;
    CrossMask: number;
}
const BoardColor = 0x101a23;
function mixColor(from: number, to: number, amount: number): number {
    let result = 0;
    for (const shift of [16, 8, 0])
        result |= Math.round(((from >> shift) & 255) * (1 - amount) + ((to >> shift) & 255) * amount) << shift;
    return result;
}

// Render an opaque union before reducing opacity. Adjacent cells never accumulate darkness.
export class TileShadow {
    readonly Layer = new Container();
    private readonly ChunkMask = new Container();
    private readonly Source = new Sprite();
    private readonly Soft = new Sprite();
    private readonly Contact = new Sprite();
    private readonly SoftBlur = new BlurFilter({ strength: 6, quality: 4 });
    private readonly ContactBlur = new BlurFilter({ strength: 2, quality: 3 });
    private MaskTexture?: RenderTexture;
    private SoftTexture?: RenderTexture;
    private ContactTexture?: RenderTexture;
    private readonly ChunkMasks = new Map<string, { Source: CellChunk; Graphics: Graphics; Used: number }>();
    private Usage = 0;
    private SourceGeometry?: CellStore;
    private CacheZoom = 0;
    private CacheBounds?: { Left: number; Top: number; Right: number; Bottom: number };

    constructor(private Renderer: Renderer) {
        this.Soft.alpha = .22;
        this.Contact.alpha = .14;
        this.Layer.addChild(this.Soft, this.Contact);
    }
    private ensureTextures(width: number, height: number) {
        for (const name of ['MaskTexture', 'SoftTexture', 'ContactTexture'] as const) {
            if (!this[name])
                this[name] = RenderTexture.create({ width, height, resolution: 1, antialias: false, dynamic: true });
            else if (this[name].width !== width || this[name].height !== height)
                this[name].resize(width, height);
        }
    }
    private contains(view: TileView) {
        const bounds = this.CacheBounds;
        if (!bounds) return false;
        const left = view.x - view.width / (2 * view.zoom), top = view.y - view.height / (2 * view.zoom);
        return left >= bounds.Left && top >= bounds.Top
            && left + view.width / view.zoom <= bounds.Right
            && top + view.height / view.zoom <= bounds.Bottom;
    }
    private renderMask(mask: Container, transform: Matrix, view: TileView, left: number, top: number, width: number, height: number) {
        this.ensureTextures(width, height);
        this.Renderer.render({ container: mask, target: this.MaskTexture, transform, clear: true, clearColor: [0, 0, 0, 0] });
        this.Source.texture = this.MaskTexture!;
        this.Source.filterArea = new Rectangle(0, 0, width, height);
        this.SoftBlur.strength = 6 * view.zoom;
        this.ContactBlur.strength = 2 * view.zoom;
        this.Source.position.set(-8 * view.zoom, 8 * view.zoom);
        this.Source.filters = [this.SoftBlur];
        this.Renderer.render({ container: this.Source, target: this.SoftTexture, clear: true, clearColor: [0, 0, 0, 0] });
        this.Source.position.set(0, 0);
        this.Source.filters = [this.ContactBlur];
        this.Renderer.render({ container: this.Source, target: this.ContactTexture, clear: true, clearColor: [0, 0, 0, 0] });
        this.Soft.texture = this.SoftTexture!;
        this.Contact.texture = this.ContactTexture!;
        for (const sprite of [this.Soft, this.Contact]) {
            sprite.position.set(left, top);
            sprite.scale.set(1 / view.zoom);
        }
        this.CacheBounds = { Left: left + ShadowMargin, Top: top + ShadowMargin,
            Right: left + width / view.zoom - ShadowMargin, Bottom: top + height / view.zoom - ShadowMargin };
    }
    update(source: CellStore, view: TileView) {
        this.Layer.visible = source.size > 0;
        if (!this.Layer.visible) return;
        const scale = view.zoom / this.CacheZoom;
        if (this.SourceGeometry === source && scale >= .5 && scale <= 2 && this.contains(view)) return;
        const padding = Math.ceil(Math.max(ShadowMargin * view.zoom, Math.max(view.width, view.height) * .12)) + 2;
        const width = Math.ceil(view.width) + padding * 2, height = Math.ceil(view.height) + padding * 2;
        const left = view.x - (view.width / 2 + padding) / view.zoom;
        const top = view.y - (view.height / 2 + padding) / view.zoom;
        const originX = Math.floor((left - ShadowMargin) / CellSize), originY = Math.floor((top - ShadowMargin) / CellSize);
        const chunks = [...source.chunks({ originX, originY,
            width: Math.ceil((left + width / view.zoom + ShadowMargin) / CellSize) - originX,
            height: Math.ceil((top + height / view.zoom + ShadowMargin) / CellSize) - originY })];
        this.Layer.visible = chunks.length > 0;
        if (!this.Layer.visible) return;
        const wanted = new Set<string>();
        for (const chunk of chunks) {
            const key = `${chunk.X},${chunk.Y}`;
            wanted.add(key);
            let entry = this.ChunkMasks.get(key);
            if (!entry || entry.Source !== chunk) {
                if (entry) {
                    this.ChunkMask.removeChild(entry.Graphics);
                    entry.Graphics.destroy();
                }
                const graphics = new Graphics();
                graphics.position.set(chunk.X * 64 * CellSize, chunk.Y * 64 * CellSize);
                if (chunk.Tiles.size === 4096)
                    graphics.rect(-Extrusion, Extrusion, 64 * CellSize, 64 * CellSize);
                else for (const index of chunk.Tiles.keys())
                    graphics.rect((index % 64) * CellSize - Extrusion, Math.floor(index / 64) * CellSize + Extrusion, CellSize, CellSize);
                graphics.fill(0x000000);
                this.ChunkMask.addChild(graphics);
                entry = { Source: chunk, Graphics: graphics, Used: 0 };
                this.ChunkMasks.set(key, entry);
            }
            entry.Used = ++this.Usage;
            entry.Graphics.visible = true;
        }
        for (const [key, entry] of this.ChunkMasks) {
            if (!wanted.has(key) && entry.Graphics.visible) {
                entry.Graphics.visible = false;
            }
        }
        while (this.ChunkMasks.size > 64) {
            const oldest = [...this.ChunkMasks].filter(([key]) => !wanted.has(key)).sort((a, b) => a[1].Used - b[1].Used)[0];
            if (!oldest) break;
            this.ChunkMask.removeChild(oldest[1].Graphics);
            oldest[1].Graphics.destroy();
            this.ChunkMasks.delete(oldest[0]);
        }
        const transform = new Matrix(view.zoom, 0, 0, view.zoom, -left * view.zoom, -top * view.zoom);
        this.renderMask(this.ChunkMask, transform, view, left, top, width, height);
        this.SourceGeometry = source;
        this.CacheZoom = view.zoom;
    }
    clear() {
        this.SourceGeometry = undefined; this.CacheZoom = 0; this.CacheBounds = undefined;
        this.Layer.visible = false;
        for (const entry of this.ChunkMasks.values()) {
            this.ChunkMask.removeChild(entry.Graphics);
            entry.Graphics.destroy();
        }
        this.ChunkMasks.clear();
    }
    destroy() {
        this.Layer.destroy({ children: true });
        this.ChunkMask.destroy({ children: true });
        this.Source.destroy();
        this.SoftBlur.destroy();
        this.ContactBlur.destroy();
        this.MaskTexture?.destroy(true);
        this.SoftTexture?.destroy(true);
        this.ContactTexture?.destroy(true);
    }
}

function chunkFaces(chunk: CellChunk, occupied: CellStore): { Tile: Tile; Mask: number }[] {
    const left = occupied.chunk(chunk.X - 1, chunk.Y), bottom = occupied.chunk(chunk.X, chunk.Y + 1);
    if (chunk.Tiles.size === 4096) {
        const faces = new Map<number, number>();
        for (let y = 0; y < 64; y++) {
            if (!left?.Tiles.has(y * 64 + 63)) faces.set(y * 64, LeftFace);
        }
        for (let x = 0; x < 64; x++) {
            if (!bottom?.Tiles.has(x)) {
                const index = 63 * 64 + x;
                faces.set(index, (faces.get(index) ?? 0) | BottomFace);
            }
        }
        return [...faces].map(([index, mask]) => ({ Tile: chunk.Tiles.get(index)!, Mask: mask }));
    }
    const faces: { Tile: Tile; Mask: number }[] = [];
    for (const [index, tile] of chunk.Tiles) {
        const x = index % 64, y = Math.floor(index / 64);
        const hasLeft = x ? chunk.Tiles.has(index - 1) : !!left?.Tiles.has(y * 64 + 63);
        const hasBottom = y < 63 ? chunk.Tiles.has(index + 64) : !!bottom?.Tiles.has(x);
        const mask = (hasLeft ? 0 : LeftFace) | (hasBottom ? 0 : BottomFace);
        if (mask) faces.push({ Tile: tile, Mask: mask });
    }
    return faces;
}

class TileGroup {
    readonly Layer = new Container();
    private readonly Sides = new Container();
    private readonly Tops = new Container();
    private readonly Visible = new Map<string, Sprite>();
    private readonly Shadow: TileShadow;
    private readonly Opacity?: AlphaFilter;
    private readonly Raster = new Container();
    private readonly Rasters = new Map<string, Sprite>();
    private readonly BlockSides = new Map<string, { Source: CellChunk; Left?: CellChunk; Bottom?: CellChunk; Runtime: unknown; Highlight: string; Faces: { Tile: Tile; Mask: number }[]; Graphics: Graphics }>();
    private readonly Colors: ColorCache;
    Count = 0;
    Lod = 'detail';
    private Source?: CellStore;
    get Ready() { return this.Lod === 'detail' || this.Colors.Ready; }

    constructor(renderer: Renderer, redraw: () => void, alpha = 1) {
        this.Shadow = new TileShadow(renderer);
        this.Colors = new ColorCache(redraw);
        this.Layer.addChild(this.Shadow.Layer, this.Sides, this.Raster, this.Tops);
        if (alpha !== 1) {
            this.Opacity = new AlphaFilter({ alpha });
            this.Layer.filters = [this.Opacity];
        }
    }
    private update(tiles: readonly Tile[], materialFor: (tile: Tile) => Material, tint: number) {
        const desired = new Set<string>();
        for (const tile of tiles) {
            const key = cellKey(tile), material = materialFor(tile);
            desired.add(key);
            let sprite = this.Visible.get(key);
            if (!sprite) {
                sprite = new Sprite(material.Top);
                this.Tops.addChild(sprite);
                this.Visible.set(key, sprite);
            }
            sprite.texture = material.Top;
            sprite.position.set(tile.x * CellSize, tile.y * CellSize);
            sprite.tint = tint;
        }
        for (const [key, sprite] of this.Visible) if (!desired.has(key)) {
            sprite.destroy(); this.Visible.delete(key);
        }
    }
    private updateSides(source: CellStore, chunks: Iterable<CellChunk>, materialFor: (tile: Tile) => Material, runtime: RuntimeGrid | null, tint: number, highlightStamp: string) {
        const wanted = new Set<string>();
        for (const chunk of chunks) {
            const key = colorKey(0, chunk.X, chunk.Y); wanted.add(key);
            const left = source.chunk(chunk.X - 1, chunk.Y), bottom = source.chunk(chunk.X, chunk.Y + 1);
            let entry = this.BlockSides.get(key);
            const runtimeKey = runtimeStamp(runtime, chunk.X, chunk.Y);
            const geometryChanged = !entry || entry.Source !== chunk || entry.Left !== left || entry.Bottom !== bottom;
            const faces = geometryChanged ? chunkFaces(chunk, source) : entry!.Faces;
            if (geometryChanged || faces.length && (entry!.Runtime !== runtimeKey || entry!.Highlight !== highlightStamp)) {
                entry?.Graphics.destroy();
                const graphics = new Graphics();
                graphics.position.set(chunk.X * 64 * CellSize, chunk.Y * 64 * CellSize);
                for (const { Tile: tile, Mask: mask } of faces) {
                    const material = materialFor(tile), x = (tile.x - chunk.X * 64) * CellSize, y = (tile.y - chunk.Y * 64) * CellSize;
                    graphics.setTransform(new Matrix(1, 0, 0, 1, x, y));
                    if (mask & LeftFace) graphics.poly([-Extrusion, Extrusion, 0, 0, 0, CellSize, -Extrusion, CellSize + Extrusion]).fill(material.Gradients[0]);
                    if (mask & BottomFace) graphics.poly([-Extrusion, CellSize + Extrusion, 0, CellSize, CellSize, CellSize, CellSize - Extrusion, CellSize + Extrusion]).fill(material.Gradients[1]);
                }
                this.Sides.addChild(graphics);
                entry = { Source: chunk, Left: left, Bottom: bottom, Runtime: runtimeKey, Highlight: highlightStamp, Faces: faces, Graphics: graphics };
                this.BlockSides.set(key, entry);
            }
            entry!.Runtime = runtimeKey; entry!.Highlight = highlightStamp; entry!.Graphics.tint = tint;
        }
        for (const [key, entry] of this.BlockSides) if (!wanted.has(key)) {
            entry.Graphics.destroy(); this.BlockSides.delete(key);
        }
    }
    private clearDetail() {
        // Detach once before destroying sprites so a LOD change remains linear.
        this.Tops.removeChildren();
        for (const sprite of this.Visible.values()) sprite.destroy();
        this.Visible.clear();
    }
    prepareRuntime(runtime: RuntimeGrid | null) { if (this.Source && this.Lod === 'aggregate') this.Colors.prepare(this.Source, runtime); }
    draw(source: CellStore, materialFor: (tile: Tile) => Material, view: TileView, mode: RenderMode, runtime: RuntimeGrid | null, tint = 0xffffff, highlightStamp = '') {
        if (!source.size) { this.clear(); return; }
        this.Source = source; this.Layer.visible = true;
        this.Colors.sync(source, runtime);
        this.Colors.begin();
        this.Lod = detailLevel(view.zoom * CellSize);
        const bounds = { originX: Math.floor((view.x - view.width / (2 * view.zoom) - CellSize - ShadowMargin) / CellSize),
            originY: Math.floor((view.y - view.height / (2 * view.zoom) - CellSize - ShadowMargin) / CellSize),
            width: Math.ceil(view.width / view.zoom / CellSize) + 6, height: Math.ceil(view.height / view.zoom / CellSize) + 6 };
        this.Raster.visible = this.Lod !== 'detail';
        this.Tops.visible = this.Lod === 'detail';
        this.Sides.visible = this.Lod !== 'aggregate' && mode === '2.5d';
        if (this.Opacity) this.Layer.filterArea = new Rectangle(view.x - view.width / (2 * view.zoom), view.y - view.height / (2 * view.zoom), view.width / view.zoom, view.height / view.zoom);
        if (this.Sides.visible) {
            this.Shadow.update(source, view);
            this.updateSides(source, source.chunks(bounds), materialFor, runtime, tint, highlightStamp);
        }
        else this.Shadow.Layer.visible = false;
        if (this.Lod === 'detail') {
            const tiles = [...source.query(bounds)];
            this.update(tiles, materialFor, tint);
            this.Count = tiles.length + (this.Sides.visible ? this.BlockSides.size : 0);
            return;
        }
        this.clearDetail();
        const level = colorLevel(view.zoom * CellSize), wanted = new Set<string>();
        for (const block of source.blocks(bounds, level)) {
            const key = colorKey(level, block.x, block.y); wanted.add(key);
            const texture = this.Colors.texture(block);
            let sprite = this.Rasters.get(key);
            if (texture) {
                if (!sprite) { sprite = new Sprite(texture); this.Rasters.set(key, sprite); this.Raster.addChild(sprite); }
                sprite.visible = true; sprite.texture = texture; sprite.position.set(block.x * 64 * 2 ** level * CellSize, block.y * 64 * 2 ** level * CellSize);
                sprite.scale.set(2 ** level * CellSize); sprite.tint = tint;
            }
            if (!texture && sprite) sprite.visible = false;
        }
        for (const [key, sprite] of this.Rasters) if (!wanted.has(key)) { sprite.destroy(); this.Rasters.delete(key); }
        this.Count = this.Rasters.size + (this.Sides.visible ? this.BlockSides.size : 0);
        this.Colors.flush();
    }
    clear() {
        if (!this.Source && !this.Layer.visible) return;
        this.Source = undefined; this.Layer.visible = false; this.Count = 0; this.Colors.clear();
        this.Shadow.clear(); this.clearDetail();
        for (const sprite of this.Rasters.values()) sprite.destroy();
        this.Rasters.clear();
        for (const entry of this.BlockSides.values()) entry.Graphics.destroy();
        this.BlockSides.clear();
    }
    destroy() {
        this.clear();
        this.Shadow.destroy(); this.Colors.destroy();
        this.Layer.destroy({ children: true });
        this.Opacity?.destroy();
    }
}

export class TileRenderer {
    readonly Layer = new Container();
    private readonly Solid: TileGroup;
    private readonly Moving: TileGroup;
    private readonly Preview: TileGroup;
    private readonly Materials = new Map<string, Material>();
    private readonly Icons = new Map<string, Texture>();
    private readonly Retired: Texture[] = [];
    private Disposed = false;
    private BoardSource?: CellStore;
    private MovingSource?: CellStore;
    private SolidSource = new CellStore();
    constructor(private Renderer: Renderer, redraw: () => void = () => {}) {
        this.Solid = new TileGroup(Renderer, redraw);
        this.Moving = new TileGroup(Renderer, redraw, .2);
        this.Preview = new TileGroup(Renderer, redraw, .5);
        this.Layer.addChild(this.Solid.Layer, this.Moving.Layer, this.Preview.Layer);
    }
    async loadIcons(ids: Iterable<string>) {
        await Promise.all([...ids].filter(hasGlyph).flatMap(id => [true, false].map(async on => {
            try {
                const texture = await Assets.load<Texture>(iconUrl(id, on));
                if (!this.Disposed)
                    this.Icons.set(`${id}:${on}`, texture);
            }
            catch { /* Colored materials remain usable if an icon cannot load. */ }
        })));
        if (this.Disposed)
            return;
        for (const material of this.Materials.values()) {
            this.Retired.push(material.Top);
            material.Top = this.makeTop(material.Tool, material.On, material.Direction, material.CrossMask);
        }
    }
    private makeTop(tool: string, on: boolean, direction = 0, crossMask = 0): Texture {
        const color = parseInt(inkColor(tool).slice(1), 16);
        const face = new Container();
        face.addChild(new Graphics().rect(0, 0, CellSize, CellSize).fill(on ? color : mixColor(BoardColor, color, .28)));
        const icon = this.Icons.get(`${tool}:${on}`);
        if (icon && hasGlyph(tool)) {
            const sprite = new Sprite(icon);
            sprite.anchor.set(.5); sprite.position.set(CellSize/2); sprite.rotation = direction * Math.PI/2;
            sprite.width = CellSize;
            sprite.height = CellSize;
            sprite.tint = on ? 0x425766 : 0x7b8997;
            sprite.alpha = on ? .65 : .5;
            face.addChild(sprite);
        }
        if(tool==='cross'&&crossMask){const marks=new Graphics();for(let c=0;c<8;c++)if(crossMask&(1<<c))marks.circle(18+(c%4)*9,25+Math.floor(c/4)*12,3).fill(parseInt(inkColor(['trace','traceRed','traceGreen','traceBlue','traceCyan','traceMagenta','traceOrange','traceWhite'][c]).slice(1),16));face.addChild(marks);}
        const texture = this.Renderer.generateTexture({ target: face, frame: new Rectangle(0, 0, CellSize, CellSize), resolution: 2 });
        face.destroy({ children: true });
        return texture;
    }
    private material(tool: string, on: boolean, highlighted = false, direction = 0, crossMask = 0): Material {
        const id = `${tool}:${on}:${highlighted}:${direction}:${crossMask}`;
        let material = this.Materials.get(id);
        if (material)
            return material;
        const color = parseInt(inkColor(tool).slice(1), 16);
        const base = on ? color : mixColor(BoardColor, color, .28);
        // Blend the side materials inside their normal layer, below all top faces.
        // This preserves gradients and diagonal occlusion without stacking surface overlays.
        const sideColor = (shade: number) => {
            const color = mixColor(0, base, shade);
            return highlighted ? mixColor(color, HighlightTint, HighlightStrength) : color;
        };
        const left = new FillGradient({ type: 'linear', textureSpace: 'global', start: { x: 0, y: 0 }, end: { x: -Extrusion, y: 0 }, colorStops: [{ offset: 0, color: sideColor(.56) }, { offset: 1, color: sideColor(.36) }] });
        const bottom = new FillGradient({ type: 'linear', textureSpace: 'global', start: { x: 0, y: CellSize }, end: { x: 0, y: CellSize + Extrusion }, colorStops: [{ offset: 0, color: sideColor(.46) }, { offset: 1, color: sideColor(.28) }] });
        material = { Top: this.makeTop(tool, on, direction, crossMask), Gradients: [left, bottom], Tool: tool, On: on, Direction: direction, CrossMask: crossMask };
        this.Materials.set(id, material);
        return material;
    }
    get Ready() { return this.Solid.Ready && (!this.Moving.Layer.visible || this.Moving.Ready) && (!this.Preview.Layer.visible || this.Preview.Ready); }
    get Count() { return this.Solid.Count + (this.Moving.Layer.visible ? this.Moving.Count : 0) + (this.Preview.Layer.visible ? this.Preview.Count : 0); }
    get Lod() { return this.Solid.Lod; }
    prepareRuntime(runtime: RuntimeGrid | null) { this.Solid.prepareRuntime(runtime); }
    draw(scene: TileScene, view: TileView) {
        const moving = scene.preview?.Kind === 'move' ? scene.preview.Source : undefined;
        if (this.BoardSource !== scene.occupied || this.MovingSource !== moving) {
            this.SolidSource = moving ? scene.occupied.update((function* () { for (const key of moving.keys()) yield [key, undefined] as const; })()) : scene.occupied;
            this.BoardSource = scene.occupied; this.MovingSource = moving;
        }
        const highlighted = new Set(scene.highlighted ?? []), highlightStamp = [...highlighted].sort((a,b)=>a-b).join(',');
        const materialFor = (tile: Tile) => {
            const runtime = scene.runtime;
            const x = runtime ? tile.x - runtime.originX : -1, y = runtime ? tile.y - runtime.originY : -1;
            const on = scene.simulating && runtime && x >= 0 && x < runtime.width && y >= 0 && y < runtime.height ? !!runtime.states[y * runtime.width + x] : tile.isOn;
            return this.material(tile.toolId, on, highlighted.has(tile.componentId), tile.direction??0, tile.crossMask??0);
        };
        this.Solid.draw(this.SolidSource, materialFor, view, scene.mode, scene.simulating ? scene.runtime : null, 0xffffff, highlightStamp);
        if (moving) this.Moving.draw(moving, materialFor, view, scene.mode, null, 0xffffff, highlightStamp); else this.Moving.clear();
        if (scene.preview) {
            const offset = scene.preview.Offset;
            this.Preview.Layer.position.set(offset.x * CellSize, offset.y * CellSize);
            const previewView = { ...view, x: view.x - offset.x * CellSize, y: view.y - offset.y * CellSize };
            this.Preview.draw(scene.preview.Source, tile => this.material(tile.toolId, tile.isOn, false, tile.direction??0, tile.crossMask??0), previewView, scene.mode, null, scene.previewValid ? 0xffffff : 0xff657e);
        }
        else this.Preview.clear();
        for (const texture of this.Retired) texture.destroy(true);
        this.Retired.length = 0;
    }
    release() {
        this.BoardSource = undefined; this.MovingSource = undefined; this.SolidSource = new CellStore();
        this.Solid.clear(); this.Moving.clear(); this.Preview.clear();
    }
    destroy() {
        this.Disposed = true;
        this.Solid.destroy();
        this.Moving.destroy();
        this.Preview.destroy();
        this.Layer.destroy();
        for (const material of this.Materials.values()) {
            material.Top.destroy(true);
            for (const gradient of material.Gradients)
                gradient.destroy();
        }
        for (const texture of this.Retired)
            texture.destroy(true);
        this.Materials.clear();
        this.Icons.clear();
    }
}
