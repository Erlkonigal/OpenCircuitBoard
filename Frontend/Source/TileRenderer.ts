import { AlphaFilter, Assets, BlurFilter, Container, FillGradient, Graphics, GraphicsContext, Matrix, Rectangle, RenderTexture, Sprite, type Renderer, type Texture } from 'pixi.js';
import { cellKey, hasGlyph, iconUrl, inkColor, type Tile, type RenderMode, type Grid } from './Model';
import { IsolationStore } from './IsolationStore';
import { IsolationRenderer } from './IsolationRenderer';
import { CellStore } from './CellStore';
import { ColorCache } from './ColorCache';
import { colorKey, colorLevel, detailLevel } from './ColorPyramid';
import type { RuntimeGrid } from './EditorStore';
import { BottomFace, CellSize, exposedFaces, Extrusion, LeftFace, ShadowMargin } from './TileGeometry';

export interface TileView {
    x: number;
    y: number;
    zoom: number;
    width: number;
    height: number;
}
export interface TileScene {
    occupied: CellStore;
    isolation?: IsolationStore;
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
    Sides: GraphicsContext[];
    Gradients: FillGradient[];
    Tool: string;
    On: boolean;
}
interface TileItem {
    Top: Sprite;
    Sides: Graphics;
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
    private readonly Mask = new Graphics();
    private readonly Source = new Sprite();
    private readonly Soft = new Sprite();
    private readonly Contact = new Sprite();
    private readonly SoftBlur = new BlurFilter({ strength: 6, quality: 4 });
    private readonly ContactBlur = new BlurFilter({ strength: 2, quality: 3 });
    private MaskTexture?: RenderTexture;
    private SoftTexture?: RenderTexture;
    private ContactTexture?: RenderTexture;
    private Geometry: unknown;
    private Transient: unknown;
    private Camera = '';

    constructor(private Renderer: Renderer) {
        this.Soft.alpha = .22;
        this.Contact.alpha = .14;
        this.Layer.addChild(this.Soft, this.Contact);
    }
    update(tiles: readonly Tile[], geometry: unknown, transient: unknown, view: TileView, blocks?: readonly Grid[]) {
        this.Layer.visible = tiles.length > 0 || !!blocks?.length;
        if (!this.Layer.visible)
            return;
        const camera = `${view.x}:${view.y}:${view.zoom}:${view.width}:${view.height}`;
        if (this.Geometry === geometry && this.Transient === transient && this.Camera === camera)
            return;
        this.Geometry = geometry;
        this.Transient = transient;
        this.Camera = camera;
        const padding = Math.ceil(ShadowMargin * view.zoom) + 2;
        const width = Math.ceil(view.width) + padding * 2, height = Math.ceil(view.height) + padding * 2;
        const left = view.x - (view.width / 2 + padding) / view.zoom;
        const top = view.y - (view.height / 2 + padding) / view.zoom;
        for (const name of ['MaskTexture', 'SoftTexture', 'ContactTexture'] as const) {
            if (!this[name])
                this[name] = RenderTexture.create({ width, height, resolution: 1, antialias: false, dynamic: true });
            else if (this[name].width !== width || this[name].height !== height)
                this[name].resize(width, height);
        }
        this.Mask.clear();
        for (const tile of tiles)
            this.Mask.rect(tile.x * CellSize - Extrusion - left, tile.y * CellSize + Extrusion - top, CellSize, CellSize);
        for (const block of blocks ?? []) this.Mask.rect(block.originX * CellSize - Extrusion - left, block.originY * CellSize + Extrusion - top, block.width * CellSize, block.height * CellSize);
        this.Mask.fill(0x000000);
        const transform = new Matrix(view.zoom, 0, 0, view.zoom, 0, 0);
        this.Renderer.render({ container: this.Mask, target: this.MaskTexture, transform, clear: true, clearColor: [0, 0, 0, 0] });
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
    }
    clear() {
        this.Geometry = undefined; this.Transient = undefined; this.Camera = '';
        this.Layer.visible = false; this.Mask.clear();
    }
    destroy() {
        this.Layer.destroy({ children: true });
        this.Mask.destroy();
        this.Source.destroy();
        this.SoftBlur.destroy();
        this.ContactBlur.destroy();
        this.MaskTexture?.destroy(true);
        this.SoftTexture?.destroy(true);
        this.ContactTexture?.destroy(true);
    }
}

class TileGroup {
    readonly Layer = new Container();
    private readonly Sides = new Container();
    private readonly Tops = new Container();
    private readonly Visible = new Map<string, TileItem>();
    private readonly Shadow: TileShadow;
    private readonly Opacity?: AlphaFilter;
    private readonly Raster = new Container();
    private readonly RasterSides = new Container();
    private readonly Rasters = new Map<string, Sprite>();
    private readonly BlockSides = new Map<string, { Source: unknown; Left: unknown; Bottom: unknown; Runtime: unknown; Graphics: Graphics }>();
    private readonly Colors: ColorCache;
    private readonly BatchedShadow: TileShadow;
    Count = 0;
    Lod = 'detail';
    private Source?: CellStore;
    private ShadowSource?: CellStore;
    private ShadowCamera = '';
    get Ready() { return this.Lod === 'detail' || this.Colors.Ready; }

    constructor(private readonly Renderer: Renderer, redraw: () => void, alpha = 1) {
        this.Shadow = new TileShadow(Renderer);
        this.BatchedShadow = new TileShadow(Renderer);
        this.Colors = new ColorCache(redraw);
        this.Layer.addChild(this.Shadow.Layer, this.BatchedShadow.Layer, this.RasterSides, this.Sides, this.Raster, this.Tops);
        if (alpha !== 1) {
            this.Opacity = new AlphaFilter({ alpha });
            this.Layer.filters = [this.Opacity];
        }
    }
    private update(tiles: readonly Tile[], occupied: { has(key: string): boolean }, materialFor: (tile: Tile) => Material, tint: number, view: TileView, geometry: unknown, transient: unknown, mode: RenderMode) {
        this.Layer.visible = tiles.length > 0;
        if (this.Opacity) {
            // Pixi transforms this local rectangle into the render target's coordinates.
            this.Layer.filterArea = new Rectangle(view.x - view.width / (2 * view.zoom), view.y - view.height / (2 * view.zoom), view.width / view.zoom, view.height / view.zoom);
        }
        const desired = new Set<string>();
        for (const tile of tiles) {
            const key = cellKey(tile), material = materialFor(tile), faces = mode === '2.5d' ? exposedFaces(tile, occupied) : 0;
            desired.add(key);
            let item = this.Visible.get(key);
            if (!item) {
                item = { Top: new Sprite(material.Top), Sides: new Graphics({ context: material.Sides[faces] }) };
                this.Tops.addChild(item.Top);
                this.Sides.addChild(item.Sides);
                this.Visible.set(key, item);
            }
            item.Top.texture = material.Top;
            item.Sides.context = material.Sides[faces];
            item.Sides.visible = faces !== 0;
            item.Top.position.set(tile.x * CellSize, tile.y * CellSize);
            item.Sides.position.copyFrom(item.Top.position);
            item.Top.tint = tint;
            item.Sides.tint = tint;
        }
        for (const [key, item] of this.Visible) {
            if (!desired.has(key)) {
                item.Top.destroy();
                item.Sides.destroy();
                this.Visible.delete(key);
            }
        }
        if (mode === '2.5d') this.Shadow.update(tiles, geometry, transient, view);
        else this.Shadow.Layer.visible = false;
    }
    draw(source: CellStore, materialFor: (tile: Tile) => Material, view: TileView, mode: RenderMode, runtime: RuntimeGrid | null, tint = 0xffffff) {
        if (!source.size) { this.clear(); return; }
        this.Source = source; this.Layer.visible = true;
        this.Colors.sync(source, runtime);
        this.Lod = detailLevel(view.zoom * CellSize);
        const bounds = { originX: Math.floor((view.x - view.width / (2 * view.zoom) - CellSize - ShadowMargin) / CellSize),
            originY: Math.floor((view.y - view.height / (2 * view.zoom) - CellSize - ShadowMargin) / CellSize),
            width: Math.ceil(view.width / view.zoom / CellSize) + 6, height: Math.ceil(view.height / view.zoom / CellSize) + 6 };
        this.Raster.visible = this.RasterSides.visible = this.Lod !== 'detail';
        this.Tops.visible = this.Sides.visible = this.Lod === 'detail';
        this.BatchedShadow.Layer.visible = false;
        if (this.Lod === 'detail') {
            const tiles = [...source.query(bounds)];
            this.update(tiles, source, materialFor, tint, view, source, null, mode);
            this.Count = tiles.length;
            return;
        }
        this.Shadow.Layer.visible = false;
        // Clear detailed objects when leaving their LOD; don't retain a second complete scene.
        for (const item of this.Visible.values()) { item.Top.destroy(); item.Sides.destroy(); }
        this.Visible.clear();
        if (this.Opacity) this.Layer.filterArea = new Rectangle(view.x - view.width / (2 * view.zoom), view.y - view.height / (2 * view.zoom), view.width / view.zoom, view.height / view.zoom);
        const level = colorLevel(view.zoom * CellSize), wanted = new Set<string>(), sidesWanted = new Set<string>();
        const shadowTiles: Tile[] = [], shadowBlocks: Grid[] = [];
        const shadowCamera = `${view.x}:${view.y}:${view.zoom}:${view.width}:${view.height}`;
        const updateShadow = this.ShadowSource !== source || this.ShadowCamera !== shadowCamera;
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
            if (this.Lod === 'color' && mode === '2.5d') {
                const chunk = source.chunk(block.x, block.y)!;
                const left = source.chunk(block.x - 1, block.y), bottom = source.chunk(block.x, block.y + 1);
                let entry = this.BlockSides.get(key);
                const runtimeKey = runtimeStamp(runtime, block.x, block.y);
                if (!entry || entry.Source !== chunk || entry.Left !== left || entry.Bottom !== bottom || entry.Runtime !== runtimeKey) {
                    if (entry) entry.Graphics.destroy();
                    const graphics = new Graphics();
                    graphics.position.set(block.x * 64 * CellSize, block.y * 64 * CellSize);
                    for (const tile of chunk.Tiles.values()) {
                        const faces = exposedFaces(tile, source); if (!faces) continue;
                        const material = materialFor(tile), x = (tile.x - block.x * 64) * CellSize, y = (tile.y - block.y * 64) * CellSize;
                        graphics.setTransform(new Matrix(1, 0, 0, 1, x, y));
                        if (faces & LeftFace) graphics.poly([-Extrusion, Extrusion, 0, 0, 0, CellSize, -Extrusion, CellSize + Extrusion]).fill(material.Gradients[0]);
                        if (faces & BottomFace) graphics.poly([-Extrusion, CellSize + Extrusion, 0, CellSize, CellSize, CellSize, CellSize - Extrusion, CellSize + Extrusion]).fill(material.Gradients[1]);
                    }
                    this.RasterSides.addChild(graphics);
                    entry = { Source: chunk, Left: left, Bottom: bottom, Runtime: runtimeKey, Graphics: graphics };
                    this.BlockSides.set(key, entry);
                }
                entry.Graphics.tint = tint; sidesWanted.add(key);
                if (updateShadow && chunk.Tiles.size === 4096) shadowBlocks.push({ originX: block.x * 64, originY: block.y * 64, width: 64, height: 64 });
                else if (updateShadow) shadowTiles.push(...chunk.Tiles.values());
            }
        }
        for (const [key, sprite] of this.Rasters) if (!wanted.has(key)) { sprite.destroy(); this.Rasters.delete(key); }
        for (const [key, entry] of this.BlockSides) if (!sidesWanted.has(key)) { entry.Graphics.destroy(); this.BlockSides.delete(key); }
        if (this.Lod === 'color' && mode === '2.5d') {
            if (updateShadow) this.BatchedShadow.update(shadowTiles, source, null, view, shadowBlocks);
            else this.BatchedShadow.Layer.visible = true;
            this.ShadowSource = source; this.ShadowCamera = shadowCamera;
        }
        else this.ShadowSource = undefined;
        this.Count = this.Rasters.size + this.BlockSides.size;
        this.Colors.flush();
    }
    clear() {
        if (!this.Source && !this.Layer.visible) return;
        this.Source = undefined; this.Layer.visible = false; this.Count = 0; this.Colors.clear();
        this.Shadow.clear(); this.BatchedShadow.clear(); this.ShadowSource = undefined; this.ShadowCamera = '';
        for (const item of this.Visible.values()) { item.Top.destroy(); item.Sides.destroy(); }
        this.Visible.clear();
        for (const sprite of this.Rasters.values()) sprite.destroy();
        this.Rasters.clear();
        for (const entry of this.BlockSides.values()) entry.Graphics.destroy();
        this.BlockSides.clear();
    }
    destroy() {
        this.Shadow.destroy();
        this.BatchedShadow.destroy();
        this.Colors.destroy();
        this.Layer.destroy({ children: true });
        this.Opacity?.destroy();
        this.Visible.clear();
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
    private readonly Isolation = new IsolationRenderer();
    private readonly MovingIsolation = new IsolationRenderer(.2);
    private readonly PreviewIsolation = new IsolationRenderer(.5);
    private BoardIsolation?: IsolationStore;
    private OriginalIsolation?: IsolationStore;
    private SolidIsolation?: IsolationStore;

    private BoardSource?: CellStore;
    private MovingSource?: CellStore;
    private SolidSource = new CellStore();
    constructor(private Renderer: Renderer, redraw: () => void = () => {}) {
        this.Solid = new TileGroup(Renderer, redraw);
        this.Moving = new TileGroup(Renderer, redraw, .2);
        this.Preview = new TileGroup(Renderer, redraw, .5);
        this.Layer.addChild(this.Solid.Layer, this.Moving.Layer, this.Preview.Layer, this.Isolation.Layer, this.MovingIsolation.Layer, this.PreviewIsolation.Layer);
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
            material.Top = this.makeTop(material.Tool, material.On);
        }
    }
    private makeTop(tool: string, on: boolean): Texture {
        const color = parseInt(inkColor(tool).slice(1), 16);
        const face = new Container();
        face.addChild(new Graphics().rect(0, 0, CellSize, CellSize).fill(on ? color : mixColor(BoardColor, color, .28)));
        const icon = this.Icons.get(`${tool}:${on}`);
        if (icon && hasGlyph(tool)) {
            const sprite = new Sprite(icon);
            sprite.width = CellSize;
            sprite.height = CellSize;
            sprite.tint = on ? 0x425766 : 0x7b8997;
            sprite.alpha = on ? .65 : .5;
            face.addChild(sprite);
        }
        const texture = this.Renderer.generateTexture({ target: face, frame: new Rectangle(0, 0, CellSize, CellSize), resolution: 2 });
        face.destroy({ children: true });
        return texture;
    }
    private material(tool: string, on: boolean): Material {
        const id = `${tool}:${on}`;
        let material = this.Materials.get(id);
        if (material)
            return material;
        const color = parseInt(inkColor(tool).slice(1), 16);
        const base = on ? color : mixColor(BoardColor, color, .28);
        const left = new FillGradient({ type: 'linear', textureSpace: 'global', start: { x: 0, y: 0 }, end: { x: -Extrusion, y: 0 }, colorStops: [{ offset: 0, color: mixColor(0, base, .56) }, { offset: 1, color: mixColor(0, base, .36) }] });
        const bottom = new FillGradient({ type: 'linear', textureSpace: 'global', start: { x: 0, y: CellSize }, end: { x: 0, y: CellSize + Extrusion }, colorStops: [{ offset: 0, color: mixColor(0, base, .46) }, { offset: 1, color: mixColor(0, base, .28) }] });
        const sides = Array.from({ length: 4 }, (_, mask) => {
            const context = new GraphicsContext();
            if (mask & LeftFace)
                context.poly([-Extrusion, Extrusion, 0, 0, 0, CellSize, -Extrusion, CellSize + Extrusion]).fill(left);
            if (mask & BottomFace)
                context.poly([-Extrusion, CellSize + Extrusion, 0, CellSize, CellSize, CellSize, CellSize - Extrusion, CellSize + Extrusion]).fill(bottom);
            return context;
        });
        material = { Top: this.makeTop(tool, on), Sides: sides, Gradients: [left, bottom], Tool: tool, On: on };
        this.Materials.set(id, material);
        return material;
    }
    get Ready() { return this.Solid.Ready && (!this.Moving.Layer.visible || this.Moving.Ready) && (!this.Preview.Layer.visible || this.Preview.Ready); }
    get Count() { return this.Solid.Count + (this.Moving.Layer.visible ? this.Moving.Count : 0) + (this.Preview.Layer.visible ? this.Preview.Count : 0); }
    get EdgeCount() { return this.Isolation.Count + this.MovingIsolation.Count + this.PreviewIsolation.Count; }
    get Lod() { return this.Solid.Lod; }
    draw(scene: TileScene, view: TileView) {
        const moving = scene.preview?.Kind === 'move' ? scene.preview.Source : undefined;
        const movingEdges = scene.preview?.Kind === 'move' ? scene.preview.Isolation : undefined;
        if (scene.isolation !== this.BoardIsolation || movingEdges !== this.OriginalIsolation) {
            this.SolidIsolation = movingEdges ? scene.isolation?.update(movingEdges.values(), true) : scene.isolation;
            this.BoardIsolation = scene.isolation; this.OriginalIsolation = movingEdges;
        }
        this.Isolation.draw(this.SolidIsolation, view);
        this.MovingIsolation.draw(movingEdges, view);
        if (this.BoardSource !== scene.occupied || this.MovingSource !== moving) {
            this.SolidSource = moving ? scene.occupied.update((function* () { for (const key of moving.keys()) yield [key, undefined] as const; })()) : scene.occupied;
            this.BoardSource = scene.occupied; this.MovingSource = moving;
        }
        const materialFor = (tile: Tile) => {
            const runtime = scene.runtime;
            const x = runtime ? tile.x - runtime.originX : -1, y = runtime ? tile.y - runtime.originY : -1;
            const on = scene.simulating && runtime && x >= 0 && x < runtime.width && y >= 0 && y < runtime.height ? !!runtime.states[y * runtime.width + x] : tile.isOn;
            return this.material(tile.toolId, on);
        };
        this.Solid.draw(this.SolidSource, materialFor, view, scene.mode, scene.simulating ? scene.runtime : null);
        if (moving) this.Moving.draw(moving, materialFor, view, scene.mode, null); else this.Moving.clear();
        if (scene.preview) {
            const offset = scene.preview.Offset;
            this.Preview.Layer.position.set(offset.x * CellSize, offset.y * CellSize);
            const previewView = { ...view, x: view.x - offset.x * CellSize, y: view.y - offset.y * CellSize };
            this.PreviewIsolation.Layer.position.copyFrom(this.Preview.Layer.position);
            this.PreviewIsolation.draw(scene.preview.Isolation, previewView);
            this.Preview.draw(scene.preview.Source, tile => this.material(tile.toolId, tile.isOn), previewView, scene.mode, null, scene.previewValid ? 0xffffff : 0xff657e);
        }
        else { this.Preview.clear(); this.PreviewIsolation.clear(); }
        for (const texture of this.Retired) texture.destroy(true);
        this.Retired.length = 0;
    }
    release() {
        this.BoardSource = undefined; this.MovingSource = undefined; this.SolidSource = new CellStore();
        this.Isolation.clear(); this.MovingIsolation.clear(); this.PreviewIsolation.clear(); this.BoardIsolation = undefined; this.OriginalIsolation = undefined; this.SolidIsolation = undefined;
        this.Solid.clear(); this.Moving.clear(); this.Preview.clear();
    }
    destroy() {
        this.Disposed = true;
        this.Isolation.destroy(); this.MovingIsolation.destroy(); this.PreviewIsolation.destroy();
        this.Solid.destroy();
        this.Moving.destroy();
        this.Preview.destroy();
        this.Layer.destroy();
        for (const material of this.Materials.values()) {
            material.Top.destroy(true);
            for (const context of material.Sides)
                context.destroy();
            for (const gradient of material.Gradients)
                gradient.destroy();
        }
        for (const texture of this.Retired)
            texture.destroy(true);
        this.Materials.clear();
        this.Icons.clear();
    }
}
