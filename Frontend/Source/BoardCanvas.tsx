import { useEffect, useRef } from 'react';
import { Application, Container, Graphics } from 'pixi.js';
import { TileRenderer } from './TileRenderer';
import { CellSize as Size, ShadowMargin } from './TileGeometry';
import { useEditor } from './EditorStore';
import { cellKey, contains, lineCells, parseKey, type Grid, type Point, type Tile } from './Model';
export interface CameraCommand {
    action: 'none' | 'in' | 'out' | 'fit';
    sequence: number;
}
interface Props {
    onZoom?: (zoom: number) => void;
    cameraCommand?: CameraCommand;
    onLatch: (point: Point) => void;
    onSettings: (x: number, y: number) => void;
    onCursor: (point: Point) => void;
}
interface View {
    x: number;
    y: number;
    zoom: number;
    width: number;
    height: number;
}
export function minimumZoom(grid: Grid, width: number, height: number) { return Math.min(width / (grid.width * Size), height / (grid.height * Size), 1.25); }
export function BoardCanvas({ onLatch, onSettings, onCursor, onZoom, cameraCommand }: Props) {
    const host = useRef<HTMLDivElement>(null), view = useRef<View>({ x: 0, y: 0, zoom: .5, width: 736, height: 658 });
    const hover = useRef<Point | null>(null);
    const requestDraw = useRef<() => void>(() => { });
    const drag = useRef<{
        kind: string;
        start: Point;
        last: Point;
        screen: Point;
        view: Point;
        corner?: number;
        grid?: Grid;
    } | null>(null);
    useEffect(() => {
        const element = host.current!;
        let disposed = false;
        const app = new Application();
        let unsubscribe = () => { };
        let observer: ResizeObserver | undefined;
        let frame = 0;
        let tileRenderer: TileRenderer | undefined;
        void (async () => {
            await app.init({ background: '#0c1219', antialias: true, resolution: window.devicePixelRatio || 1, autoDensity: true, autoStart: false, preference: 'webgl', preserveDrawingBuffer: true });
            if (disposed) {
                app.destroy(true);
                return;
            }
            element.appendChild(app.canvas);
            app.canvas.setAttribute('aria-label', 'Circuit board');
            const world = new Container(), board = new Graphics(), overlay = new Graphics();
            tileRenderer = new TileRenderer(app.renderer);
            app.stage.addChild(world);
            world.addChild(board, tileRenderer.Layer, overlay);
            let bucketRevision = -1, buckets = new Map<string, Tile[]>();
            const draw = () => {
                frame = 0;
                if (disposed)
                    return;
                const s = useEditor.getState(), v = view.current, g = s.Board.grid;
                const min = minimumZoom(g, v.width, v.height);
                v.zoom = Math.max(min, Math.min(1.25, v.zoom));
                v.x = Math.min((g.originX + g.width) * Size, Math.max(g.originX * Size, v.x));
                v.y = Math.min((g.originY + g.height) * Size, Math.max(g.originY * Size, v.y));
                world.position.set(v.width / 2 - v.x * v.zoom, v.height / 2 - v.y * v.zoom);
                world.scale.set(v.zoom);
                board.clear();
                board.roundRect(g.originX * Size, g.originY * Size, g.width * Size, g.height * Size, Size).fill('#101a23');
                const left = v.x - v.width / (2 * v.zoom), top = v.y - v.height / (2 * v.zoom), right = v.x + v.width / (2 * v.zoom), bottom = v.y + v.height / (2 * v.zoom);
                const step = 256;
                for (let y = Math.floor(Math.max(top, g.originY * Size) / step) * step; y < Math.min(bottom, (g.originY + g.height) * Size); y += step) {
                    for (let x = Math.floor(Math.max(left, g.originX * Size) / step) * step; x < Math.min(right, (g.originX + g.width) * Size); x += step) {
                        if (x < g.originX * Size || y < g.originY * Size)
                            continue;
                        board.poly([x, y + 64, x + 96, y + 8, x + 192, y + 64, x + 192, y + 176, x + 96, y + 232, x, y + 176]).stroke({ color: '#304638', alpha: .15, width: 1 / v.zoom });
                    }
                }
                board.roundRect(g.originX * Size, g.originY * Size, g.width * Size, g.height * Size, Size).stroke({ color: '#31483f', width: 1.5 / v.zoom });
                if (bucketRevision !== s.Revision) {
                    buckets = new Map();
                    for (const tile of s.Tiles.values()) {
                        const key = `${Math.floor(tile.x / 32)},${Math.floor(tile.y / 32)}`;
                        let bucket = buckets.get(key);
                        if (!bucket)
                            buckets.set(key, bucket = []);
                        bucket.push(tile);
                    }
                    bucketRevision = s.Revision;
                }
                const desired = new Map<string, Tile>();
                for (let cy = Math.floor(top / Size / 32) - 1; cy <= Math.floor(bottom / Size / 32) + 1; cy++) {
                    for (let cx = Math.floor(left / Size / 32) - 1; cx <= Math.floor(right / Size / 32) + 1; cx++) {
                        for (const t of buckets.get(`${cx},${cy}`) ?? []) {
                            if (t.x * Size < right + Size + ShadowMargin && t.x * Size > left - Size * 2 - ShadowMargin && t.y * Size < bottom + Size + ShadowMargin && t.y * Size > top - Size * 2 - ShadowMargin)
                                desired.set(cellKey(t), t);
                        }
                    }
                }
                tileRenderer!.draw({ occupied: s.Tiles, visible: desired, preview: s.Preview,
                    moving: s.Preview.length && !s.PasteAnchor ? s.Selection?.cells ?? null : null,
                    previewValid: s.PreviewValid, simulating: s.Simulating, runtime: s.RuntimeGrid }, v);
                overlay.clear();
                const rectangle = (bounds: Grid, color: string, fill = false) => { overlay.rect(bounds.originX * Size, bounds.originY * Size, bounds.width * Size, bounds.height * Size); if (fill)
                    overlay.fill({ color, alpha: .08 }); overlay.stroke({ color, width: 2 / v.zoom }); };
                if (hover.current && !s.Simulating && !s.PasteAnchor && !s.Selection && contains(g, hover.current))
                    rectangle({ originX: hover.current.x, originY: hover.current.y, width: 1, height: 1 }, '#f2c94c', true);
                if (s.Selection)
                    rectangle(s.Selection.bounds, '#82baff', true);
                if (s.PasteAnchor) {
                    const clip = s.Clipboard[s.ClipboardIndex];
                    if (clip)
                        rectangle({ originX: s.PasteAnchor.x, originY: s.PasteAnchor.y, width: clip.width, height: clip.height }, s.PreviewValid ? '#69e6a6' : '#ff657e', true);
                }
                const d = drag.current;
                if (d?.kind === 'select') {
                    const a = d.start, b = d.last;
                    rectangle({ originX: Math.min(a.x, b.x), originY: Math.min(a.y, b.y), width: Math.abs(a.x - b.x) + 1, height: Math.abs(a.y - b.y) + 1 }, '#82baff', true);
                }
                if (!s.Simulating) {
                    for (const [x, y] of [[g.originX, g.originY], [g.originX + g.width, g.originY], [g.originX, g.originY + g.height], [g.originX + g.width, g.originY + g.height]])
                        overlay.circle(x * Size, y * Size, 5 / v.zoom).fill('#7093b6').stroke({ color: '#111720', width: 2 / v.zoom });
                }
                app.render();
                onZoom?.(v.zoom);
            };
            requestDraw.current = () => { if (!frame)
                frame = requestAnimationFrame(draw); };
            unsubscribe = useEditor.subscribe(requestDraw.current);
            observer = new ResizeObserver(() => { const r = element.getBoundingClientRect(); view.current.width = r.width; view.current.height = r.height; app.renderer.resize(r.width, r.height); requestDraw.current(); });
            observer.observe(element);
            // Resolve shared SVG textures once, then reuse generated faces for all cells.
            const ids = new Set([...useEditor.getState().Tiles.values()].map(t => t.toolId));
            for (const id of ['cross', 'mesh', 'bus', 'busRed', 'busGreen', 'busYellow', 'busCyan', 'busMagenta', 'read', 'write', 'trace', 'traceRed', 'traceGreen', 'traceBlue', 'traceCyan', 'traceMagenta', 'buffer', 'and', 'or', 'xor', 'not', 'nand', 'nor', 'xnor', 'latch', 'clock', 'led'])
                ids.add(id);
            await tileRenderer.loadIcons(ids);
            if (disposed)
                return;
            element.dataset.renderReady = 'true';
            requestDraw.current();
        })().catch(error => { element.dataset.renderError = String(error); useEditor.getState().log(String(error)); });
        return () => { disposed = true; unsubscribe(); observer?.disconnect(); cancelAnimationFrame(frame); requestDraw.current = () => { }; tileRenderer?.destroy(); if (app.renderer)
            app.destroy(true, { children: true }); };
    }, []);
    useEffect(() => { if (!cameraCommand || cameraCommand.action === 'none')
        return; const v = view.current, g = useEditor.getState().Board.grid, min = minimumZoom(g, v.width, v.height); if (cameraCommand.action === 'fit') {
        v.zoom = min;
        v.x = (g.originX + g.width / 2) * Size;
        v.y = (g.originY + g.height / 2) * Size;
    }
    else {
        v.zoom = Math.max(min, Math.min(1.25, v.zoom + (cameraCommand.action === 'in' ? .05 : -.05)));
    } onZoom?.(v.zoom); requestDraw.current(); }, [cameraCommand]);
    const screen = (event: {
        clientX: number;
        clientY: number;
    }) => { const r = host.current!.getBoundingClientRect(); return { x: event.clientX - r.left, y: event.clientY - r.top }; };
    const world = (p: Point) => { const v = view.current; return { x: v.x + (p.x - v.width / 2) / v.zoom, y: v.y + (p.y - v.height / 2) / v.zoom }; };
    const cell = (p: Point) => { const w = world(p); return { x: Math.floor(w.x / Size), y: Math.floor(w.y / Size) }; };
    return <div ref={host} className="board-canvas" data-testid="board" onContextMenu={e => e.preventDefault()} onWheel={event => { event.preventDefault(); const p = screen(event), anchor = world(p), v = view.current; const min = minimumZoom(useEditor.getState().Board.grid, v.width, v.height); const zoom = Math.max(min, Math.min(1.25, v.zoom + (event.deltaY < 0 ? .05 : -.05))); v.zoom = zoom; onZoom?.(zoom); if (zoom === min) {
        const g = useEditor.getState().Board.grid;
        v.x = (g.originX + g.width / 2) * Size;
        v.y = (g.originY + g.height / 2) * Size;
    }
    else {
        v.x = anchor.x - (p.x - v.width / 2) / zoom;
        v.y = anchor.y - (p.y - v.height / 2) / zoom;
    } if (useEditor.getState().PasteAnchor)
        useEditor.getState().paste(cell(p)); requestDraw.current(); }} onPointerDown={event => {
            const p = screen(event), c = cell(p), s = useEditor.getState(), v = view.current;
            host.current!.focus({ preventScroll: true });
            host.current!.setPointerCapture(event.pointerId);
            const base = { start: c, last: c, screen: p, view: { x: v.x, y: v.y } };
            if (event.button === 1) {
                drag.current = { ...base, kind: 'pan' };
                return;
            }
            if (s.Simulating) {
                if (event.button === 0)
                    onLatch(c);
                return;
            }
            if (event.button === 2) {
                if (s.PasteAnchor || drag.current) {
                    s.cancel();
                    drag.current = null;
                    return;
                }
                if (event.shiftKey && s.Selection) {
                    const selected = s.Selection.cells.map(k => s.Tiles.get(k)!).filter(Boolean);
                    const family = (id: string) => id.startsWith('trace') ? 'trace' : id.startsWith('bus') ? 'bus' : id;
                    if (selected.length && selected.every(t => family(t.toolId) === family(selected[0].toolId)) && ['trace', 'bus', 'mesh', 'clock', 'latch'].includes(family(selected[0].toolId))) {
                        onSettings(event.clientX, event.clientY);
                        return;
                    }
                }
                s.begin();
                s.paint([c], true);
                drag.current = { ...base, kind: 'delete' };
                return;
            }
            if (event.button !== 0)
                return;
            if (s.PasteAnchor) {
                s.confirmPaste();
                return;
            }
            const g = s.Board.grid, w = world(p), corners = [[g.originX, g.originY], [g.originX + g.width, g.originY], [g.originX, g.originY + g.height], [g.originX + g.width, g.originY + g.height]];
            const corner = corners.findIndex(([x, y]) => Math.hypot(w.x - x * Size, w.y - y * Size) * v.zoom <= 18);
            if (corner >= 0) {
                s.begin();
                drag.current = { ...base, kind: 'resize', corner, grid: { ...g } };
                return;
            }
            if (event.shiftKey) {
                drag.current = { ...base, kind: 'select' };
                return;
            }
            if (s.Selection && contains(s.Selection.bounds, c)) {
                drag.current = { ...base, kind: 'move' };
                return;
            }
            s.select(null);
            s.begin();
            s.paint([c]);
            drag.current = { ...base, kind: 'paint' };
        }} onPointerMove={event => {
            const p = screen(event), c = cell(p), s = useEditor.getState(), d = drag.current;
            hover.current = c;
            onCursor(c);
            if (!d) {
                if (s.PasteAnchor)
                    s.paste(c);
                requestDraw.current();
                return;
            }
            if (d.kind === 'pan') {
                view.current.x = d.view.x + (d.screen.x - p.x) / view.current.zoom;
                view.current.y = d.view.y + (d.screen.y - p.y) / view.current.zoom;
                if (s.PasteAnchor)
                    s.paste(cell(p));
            }
            else if (d.kind === 'paint' || d.kind === 'delete')
                s.paint(lineCells(d.last, c), d.kind === 'delete');
            else if (d.kind === 'move')
                s.movePreview({ x: c.x - d.start.x, y: c.y - d.start.y });
            else if (d.kind === 'resize') {
                const g = d.grid!, corner = d.corner!, w = world(p);
                let left = g.originX, right = left + g.width, top = g.originY, bottom = top + g.height;
                if (corner % 2 === 0)
                    left = Math.min(Math.round(w.x / Size), right - 4);
                else
                    right = Math.max(Math.round(w.x / Size), left + 4);
                if (corner < 2)
                    top = Math.min(Math.round(w.y / Size), bottom - 4);
                else
                    bottom = Math.max(Math.round(w.y / Size), top + 4);
                s.resize({ originX: left, originY: top, width: right - left, height: bottom - top });
            }
            d.last = c;
            requestDraw.current();
        }} onPointerUp={event => { const d = drag.current; if (!d)
        return; const s = useEditor.getState(), c = cell(screen(event)); if (d.kind === 'select')
        s.select({ originX: Math.min(c.x, d.start.x), originY: Math.min(c.y, d.start.y), width: Math.abs(c.x - d.start.x) + 1, height: Math.abs(c.y - d.start.y) + 1 });
    else if (d.kind === 'move')
        s.confirmMove({ x: c.x - d.start.x, y: c.y - d.start.y });
    else if (d.kind !== 'pan')
        s.commit(); drag.current = null; requestDraw.current(); }} onPointerLeave={() => { hover.current = null; requestDraw.current(); }} onPointerCancel={() => { useEditor.getState().cancel(); drag.current = null; requestDraw.current(); }} onKeyDown={event => { if (event.key === 'Escape') {
        drag.current = null;
        useEditor.getState().cancel();
        requestDraw.current();
    } }} tabIndex={0}/>;
}
