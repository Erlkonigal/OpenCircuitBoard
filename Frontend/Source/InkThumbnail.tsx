import { useEffect, useRef } from 'react';
import { Application, Container } from 'pixi.js';
import { isolationSource } from './IsolationStore';
import { inkSource } from './CellStore';
import { RenderBudget } from './ColorCache';
import { TileRenderer } from './TileRenderer';
import { useEditor } from './EditorStore';
import { ToolIds, type ClipboardItem, type RenderMode } from './Model';
const Width = 200, Height = 92;
const Images = new WeakMap<ClipboardItem, Map<RenderMode, HTMLCanvasElement>>();
class ThumbnailRenderer {
    private App?: Application;
    private Tiles?: TileRenderer;
    private World?: Container;
    private Queue = Promise.resolve();
    private Redraw?: () => void;
    private async init() {
        if (this.App) return;
        const app = new Application();
        await app.init({ width: Width, height: Height, resolution: 2, background: '#0c141d', antialias: true, autoStart: false, preference: 'webgl', useBackBuffer: true, preserveDrawingBuffer: true });
        this.App = app; this.World = new Container();
        this.Tiles = new TileRenderer(app.renderer, () => this.Redraw?.());
        this.World.addChild(this.Tiles.Layer); app.stage.addChild(this.World);
        await this.Tiles.loadIcons(ToolIds.slice(1));
    }
    render(item: ClipboardItem, mode: RenderMode, active: () => boolean): Promise<HTMLCanvasElement | null> {
        const run = async () => {
            if (!active()) return null;
            const existing = Images.get(item), cached = existing?.get(mode);
            if (cached) { RenderBudget.touch(cached, Width * Height * 16, () => existing!.delete(mode)); return cached; }
            await this.init();
            const app = this.App!, tiles = this.Tiles!, world = this.World!;
            const depth = mode === '2.5d' ? .375 : 0;
            const pixelsPerCell = Math.min(176 / (item.width + depth), 68 / (item.height + depth), 20);
            const x = (item.width / 2 - depth / 2) * 64, y = (item.height / 2 + depth / 2) * 64;
            const view = { x, y, width: Width, height: Height, zoom: pixelsPerCell / 64 };
            const source = inkSource(item);
            const draw = () => {
                world.scale.set(view.zoom); world.position.set(Width / 2 - x * view.zoom, Height / 2 - y * view.zoom);
                tiles.draw({ occupied: source, isolation: isolationSource(item), preview: null, previewValid: true, simulating: false, runtime: null, mode }, view);
            };
            await new Promise<void>((resolve, reject) => {
                const timeout = window.setTimeout(() => { this.Redraw = undefined; reject(Error('ThumbnailRenderTimeout')); }, 30000);
                this.Redraw = () => {
                    try {
                        draw();
                        if (tiles.Ready) { window.clearTimeout(timeout); this.Redraw = undefined; resolve(); }
                    }
                    catch (error) { window.clearTimeout(timeout); this.Redraw = undefined; reject(error); }
                };
                this.Redraw();
            });
            app.render();
            const canvas = document.createElement('canvas'); canvas.width = Width * 2; canvas.height = Height * 2;
            canvas.getContext('2d')!.drawImage(app.canvas, 0, 0);
            let modes = Images.get(item);
            if (!modes) { modes = new Map(); Images.set(item, modes); }
            modes.set(mode, canvas);
            const savedModes = modes;
            RenderBudget.touch(canvas, canvas.width * canvas.height * 4, () => savedModes.delete(mode));
            tiles.release();
            return canvas;
        };
        const result = this.Queue.then(run);
        this.Queue = result.then(() => {}, () => {});
        return result;
    }
}
const Thumbnails = new ThumbnailRenderer();
export function InkThumbnail({ item }: { item: ClipboardItem }) {
    const canvas = useRef<HTMLCanvasElement>(null);
    const mode = useEditor(state => state.RenderMode);
    useEffect(() => {
        const element = canvas.current!;
        let disposed = false, requested = false;
        element.dataset.ready = 'false';
        const observer = new IntersectionObserver(entries => {
            if (requested || !entries.some(entry => entry.isIntersecting)) return;
            requested = true;
            void Thumbnails.render(item, mode, () => !disposed).then(image => {
                if (disposed || !image) return;
                const context = element.getContext('2d')!;
                context.clearRect(0, 0, element.width, element.height);
                context.drawImage(image, 0, 0, element.width, element.height);
                element.dataset.ready = 'true';
            }).catch(error => { if (!disposed) { element.dataset.error = String(error); useEditor.getState().log(String(error)); } });
        }, { rootMargin: '100px' });
        observer.observe(element);
        return () => { disposed = true; observer.disconnect(); };
    }, [item, mode]);
    return <canvas width={Width * 2} height={Height * 2} ref={canvas} className="clipboard-thumbnail" aria-label="Ink preview"/>;
}
