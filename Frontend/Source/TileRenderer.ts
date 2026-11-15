import { AlphaFilter, Assets, BlurFilter, Container, FillGradient, Graphics, GraphicsContext, Matrix, Rectangle, RenderTexture, Sprite, type Renderer, type Texture } from 'pixi.js';
import { cellKey, iconUrl, inkColor, type Tile } from './Model';
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
    occupied: ReadonlyMap<string, Tile>;
    visible: ReadonlyMap<string, Tile>;
    preview: readonly Tile[];
    moving: readonly string[] | null;
    previewValid: boolean;
    simulating: boolean;
    runtime: RuntimeGrid | null;
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
class TileShadow {
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
    update(tiles: readonly Tile[], geometry: unknown, transient: unknown, view: TileView) {
        this.Layer.visible = tiles.length > 0;
        if (!tiles.length)
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
            this.Mask.rect(tile.x * CellSize - Extrusion, tile.y * CellSize + Extrusion, CellSize, CellSize);
        this.Mask.fill(0x000000);
        const transform = new Matrix(view.zoom, 0, 0, view.zoom, -left * view.zoom, -top * view.zoom);
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

    constructor(renderer: Renderer, alpha = 1) {
        this.Shadow = new TileShadow(renderer);
        this.Layer.addChild(this.Shadow.Layer, this.Sides, this.Tops);
        if (alpha !== 1) {
            this.Opacity = new AlphaFilter({ alpha });
            this.Layer.filters = [this.Opacity];
        }
    }
    update(tiles: readonly Tile[], occupied: { has(key: string): boolean }, materialFor: (tile: Tile) => Material, tint: number, view: TileView, geometry: unknown, transient: unknown) {
        this.Layer.visible = tiles.length > 0;
        if (this.Opacity) {
            // Pixi transforms this local rectangle into the render target's coordinates.
            this.Layer.filterArea = new Rectangle(view.x - view.width / (2 * view.zoom), view.y - view.height / (2 * view.zoom), view.width / view.zoom, view.height / view.zoom);
        }
        const desired = new Set<string>();
        for (const tile of tiles) {
            const key = cellKey(tile), material = materialFor(tile), faces = exposedFaces(tile, occupied);
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
        this.Shadow.update(tiles, geometry, transient, view);
    }
    destroy() {
        this.Shadow.destroy();
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

    constructor(private Renderer: Renderer) {
        this.Solid = new TileGroup(Renderer);
        this.Moving = new TileGroup(Renderer, .2);
        this.Preview = new TileGroup(Renderer, .5);
        this.Layer.addChild(this.Solid.Layer, this.Moving.Layer, this.Preview.Layer);
    }
    async loadIcons(ids: Iterable<string>) {
        await Promise.all([...ids].flatMap(id => [true, false].map(async on => {
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
        if (icon) {
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
    draw(scene: TileScene, view: TileView) {
        const moving = new Set(scene.moving ?? []), solid: Tile[] = [], sources: Tile[] = [];
        for (const [key, tile] of scene.visible)
            (moving.has(key) ? sources : solid).push(tile);
        const previewKeys = new Set(scene.preview.map(cellKey));
        const left = view.x - view.width / (2 * view.zoom) - CellSize - ShadowMargin;
        const right = view.x + view.width / (2 * view.zoom) + CellSize + ShadowMargin;
        const top = view.y - view.height / (2 * view.zoom) - CellSize - ShadowMargin;
        const bottom = view.y + view.height / (2 * view.zoom) + CellSize + ShadowMargin;
        const preview = scene.preview.filter(tile => tile.x * CellSize > left && tile.x * CellSize < right && tile.y * CellSize > top && tile.y * CellSize < bottom);
        const materialFor = (tile: Tile) => {
            const runtime = scene.runtime;
            const x = runtime ? tile.x - runtime.originX : -1, y = runtime ? tile.y - runtime.originY : -1;
            const on = scene.simulating && runtime && x >= 0 && x < runtime.width && y >= 0 && y < runtime.height ? !!runtime.states[y * runtime.width + x] : tile.isOn;
            return this.material(tile.toolId, on);
        };
        this.Solid.update(solid, scene.occupied, materialFor, 0xffffff, view, scene.occupied, scene.moving);
        this.Moving.update(sources, scene.occupied, materialFor, 0xffffff, view, scene.occupied, scene.moving);
        this.Preview.update(preview, previewKeys, tile => this.material(tile.toolId, tile.isOn), scene.previewValid ? 0xffffff : 0xff657e, view, scene.preview, null);
        for (const texture of this.Retired)
            texture.destroy(true);
        this.Retired.length = 0;
    }
    destroy() {
        this.Disposed = true;
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
