import { useEffect, useRef } from 'react';
import { Application, Container, Graphics, Rectangle, TilingSprite, type Texture } from 'pixi.js';
import { TileRenderer } from './TileRenderer';
import { CellSize as Size } from './TileGeometry';
import { useEditor } from './EditorStore';
import { cellKey, contains, ToolIds, type Grid, type Point } from './Model';
import { tileColor } from './ColorPyramid';
import { editorInput } from './EditorInput';
import { selectionCount } from './Selection';
import { ComponentHighlight, drawMarquee } from './ComponentHighlight';
export interface CameraCommand {
    action: 'none' | 'in' | 'out' | 'fit';
    sequence: number;
}
interface Props {
    onZoom?: (zoom: number) => void;
    cameraCommand?: CameraCommand;
    onLatch: (point: Point) => void;
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
export function BoardCanvas({ onLatch, onCursor, onZoom, cameraCommand }: Props) {
    const host = useRef<HTMLDivElement>(null), view = useRef<View>({ x: 0, y: 0, zoom: .5, width: 736, height: 658 });
    const callbacks=useRef({onLatch,onCursor,onZoom});callbacks.current={onLatch,onCursor,onZoom};
    const requestDraw = useRef<() => void>(() => {});
    const worldPoint=(p:Point)=>{const v=view.current;return {x:v.x+(p.x-v.width/2)/v.zoom,y:v.y+(p.y-v.height/2)/v.zoom};};
    const cellPoint=(p:Point)=>{const w=worldPoint(p);return {x:Math.floor(w.x/Size),y:Math.floor(w.y/Size)};};
    useEffect(() => {
        const element = host.current!;
        let disposed = false;
        const app = new Application();
        let unsubscribe = () => { };
        let observer: ResizeObserver | undefined;
        let frame = 0;
        let tileRenderer: TileRenderer | undefined;
        let patternTexture: Texture | undefined;
        let highlight: ComponentHighlight | undefined;
        const disconnect=editorInput.connect({View:view.current,world:worldPoint,cell:cellPoint,
            redraw:()=>requestDraw.current(),cursor:p=>callbacks.current.onCursor(p),latch:p=>callbacks.current.onLatch(p)});
        void (async () => {
            await app.init({ background: '#0c1219', antialias: true, resolution: window.devicePixelRatio || 1, autoDensity: true, autoStart: false, preference: 'webgl', preserveDrawingBuffer: true });
            if (disposed) {
                app.destroy(true);
                return;
            }
            element.appendChild(app.canvas);
            app.canvas.setAttribute('aria-label', 'Circuit board');
            const world = new Container(), board = new Graphics(), overlay = new Graphics();
            tileRenderer = new TileRenderer(app.renderer, () => requestDraw.current());
            highlight = new ComponentHighlight();
            app.stage.addChild(world);
            const motif = new Graphics().poly([0, 64, 96, 8, 192, 64, 192, 176, 96, 232, 0, 176]).stroke({ color: '#304638', alpha: .15, width: 2 });
            patternTexture = app.renderer.generateTexture({ target: motif, frame: new Rectangle(0, 0, 256, 256), resolution: 1 });
            motif.destroy();
            const pattern = new TilingSprite({ texture: patternTexture, width: 256, height: 256 });
            world.addChild(board, pattern, tileRenderer.Layer, highlight.Layer, overlay);
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
                board.clear(); board.position.set(g.originX * Size, g.originY * Size);
                board.roundRect(0, 0, g.width * Size, g.height * Size, Size).fill('#101a23');
                pattern.visible = v.zoom * Size >= 12;
                if (pattern.visible) {
                    pattern.position.set(g.originX * Size, g.originY * Size);
                    pattern.width = g.width * Size; pattern.height = g.height * Size;
                    pattern.tilePosition.set(-(g.originX * Size % 256), -(g.originY * Size % 256));
                }
                board.roundRect(0, 0, g.width * Size, g.height * Size, Size).stroke({ color: '#31483f', width: 1.5 / v.zoom });
                const ids=[...new Set([...(s.Selection?.ids??[]),...s.MergeIds])];
                const hover=editorInput.Hover,hovered=hover?s.Tiles.get(cellKey(hover))?.componentId:undefined;
                const hoverIds=hovered&&!ids.includes(hovered)&&!s.Preview&&s.Gesture!=='rectanglePaint'&&s.EditTool!=='split'?[hovered]:[];
                const highlighted=[...ids,...hoverIds];
                tileRenderer!.draw({ occupied: s.Tiles, preview: s.Preview, previewValid: s.PreviewValid, highlighted,
                    simulating: s.Simulating, runtime: s.RuntimeGrid, mode: s.RenderMode }, v);
                highlight!.draw(s.Tiles,s.Components,highlighted,v);
                element.style.cursor=editorInput.cursor;
                element.dataset.highlightComponents=[...ids,...hoverIds].join(',');
                element.dataset.highlightCells=String([...ids,...hoverIds].reduce((count,id)=>count+s.Components.count(id),0));
                element.dataset.highlightObjects=String(highlight!.Count);
                element.dataset.mergeCount=String(s.MergeIds.length);
                element.dataset.componentCount=String(s.Components.size);
                element.dataset.selectionKind=s.Selection?.kind??'none';
                element.dataset.selectionCells=String(selectionCount(s));
                element.dataset.gesture=s.Gesture;
                element.dataset.splitEdges=String(s.SplitPath?.Edges.size??0);
                element.dataset.editTool = s.EditTool;
                element.dataset.lod = tileRenderer!.Lod;
                element.dataset.renderObjects = String(tileRenderer!.Count);
                element.dataset.colorReady = String(tileRenderer!.Ready);
                overlay.clear(); overlay.position.set(v.x, v.y);
                const rectangle = (bounds: Grid, color: string, fill = false) => { overlay.rect(bounds.originX * Size - v.x, bounds.originY * Size - v.y, bounds.width * Size, bounds.height * Size); if (fill)
                    overlay.fill({ color, alpha: .04 }); overlay.stroke({ color, width: 2 / v.zoom }); };
                if(s.EditTool==='draw'&&hover&&!hovered&&!s.Simulating&&!s.Preview&&s.Gesture!=='rectanglePaint'&&contains(g,hover))
                    overlay.rect(hover.x*Size-v.x,hover.y*Size-v.y,Size,Size).fill({color:'#f0f8ff',alpha:.10});
                if(s.Preview)rectangle(s.Preview.Bounds,s.PreviewValid?'#69e6a6':'#ff657e',true);
                if(s.RectanglePaint) {
                    const p=s.RectanglePaint,b=p.Bounds,[r,g,bColor]=tileColor({...p.Material,...p.Anchor,componentId:0});
                    overlay.rect(b.originX*Size-v.x,b.originY*Size-v.y,b.width*Size,b.height*Size).fill({color:(r<<16)|(g<<8)|bColor,alpha:.5});
                }
                element.dataset.rectangleCells=String(s.RectanglePaint?s.RectanglePaint.Bounds.width*s.RectanglePaint.Bounds.height:0);
                if(s.Marquee)drawMarquee(overlay,s.Marquee.Bounds,v);
                if(s.EditTool==='split'&&!s.Simulating) {
                    if(s.SplitPath?.Edges.size) {
                        for(const edge of s.SplitPath.Edges.values())overlay.moveTo(edge.Start.x*Size-v.x,edge.Start.y*Size-v.y).lineTo(edge.End.x*Size-v.x,edge.End.y*Size-v.y);
                        overlay.stroke({color:'#f2c94c',width:2/v.zoom});
                    }
                    const vertex=editorInput.Vertex;
                    if(vertex)overlay.circle(vertex.x*Size-v.x,vertex.y*Size-v.y,3/v.zoom).fill('#f2c94c');
                }
                if (!s.Simulating) {
                    for (const [x, y] of [[g.originX, g.originY], [g.originX + g.width, g.originY], [g.originX, g.originY + g.height], [g.originX + g.width, g.originY + g.height]])
                        overlay.circle(x * Size - v.x, y * Size - v.y, 5 / v.zoom).fill('#7093b6').stroke({ color: '#111720', width: 2 / v.zoom });
                }
                app.render();
                callbacks.current.onZoom?.(v.zoom);
            };
            requestDraw.current = () => { if (!frame) frame = requestAnimationFrame(() => {
                try { draw(); }
                catch (error) {
                    frame = 0;
                    if (element.dataset.renderError !== String(error)) { element.dataset.renderError = String(error); useEditor.getState().log(String(error)); }
                }
            }); };
            unsubscribe = useEditor.subscribe((next, previous) => {
                if (next.Tiles !== previous.Tiles || next.Preview !== previous.Preview || next.RenderMode !== previous.RenderMode || next.RuntimeGrid !== previous.RuntimeGrid)
                    element.dataset.colorReady = 'false';
                requestDraw.current();
            });
            observer = new ResizeObserver(() => { const r = element.getBoundingClientRect(); view.current.width = r.width; view.current.height = r.height; app.renderer.resize(r.width, r.height); requestDraw.current(); });
            observer.observe(element);
            // Resolve shared SVG textures once, then reuse generated faces for all cells.
            const ids = ToolIds.slice(1);
            await tileRenderer.loadIcons(ids);
            if (disposed)
                return;
            element.dataset.renderReady = 'true';
            requestDraw.current();
        })().catch(error => { element.dataset.renderError = String(error); useEditor.getState().log(String(error)); });
        return () => { disposed = true; disconnect(); unsubscribe(); observer?.disconnect(); cancelAnimationFrame(frame); requestDraw.current = () => { }; highlight?.destroy(); tileRenderer?.destroy(); if (app.renderer)
            app.destroy(true, { children: true }); patternTexture?.destroy(true); };
    }, []);
    useEffect(() => { if (!cameraCommand || cameraCommand.action === 'none')
        return; const v = view.current, g = useEditor.getState().Board.grid, min = minimumZoom(g, v.width, v.height); if (cameraCommand.action === 'fit') {
        v.zoom = min;
        v.x = (g.originX + g.width / 2) * Size;
        v.y = (g.originY + g.height / 2) * Size;
    }
    else {
        v.zoom = Math.max(min, Math.min(1.25, v.zoom * (cameraCommand.action === 'in' ? 1.1 : 1 / 1.1)));
    } onZoom?.(v.zoom); requestDraw.current(); }, [cameraCommand]);
    const screen = (event: {
        clientX: number;
        clientY: number;
    }) => { const r = host.current!.getBoundingClientRect(); return { x: event.clientX - r.left, y: event.clientY - r.top }; };
    return <div ref={host} className="board-canvas" data-testid="board" tabIndex={0}
        onContextMenu={event=>event.preventDefault()}
        onWheel={event=>{
            event.preventDefault();if(useEditor.getState().Gesture!=='idle')return;
            const p=screen(event),anchor=worldPoint(p),v=view.current,g=useEditor.getState().Board.grid;
            const min=minimumZoom(g,v.width,v.height),zoom=Math.max(min,Math.min(1.25,v.zoom*(event.deltaY<0?1.1:1/1.1)));
            v.zoom=zoom;callbacks.current.onZoom?.(zoom);
            if(zoom===min){v.x=(g.originX+g.width/2)*Size;v.y=(g.originY+g.height/2)*Size;}
            else {v.x=anchor.x-(p.x-v.width/2)/zoom;v.y=anchor.y-(p.y-v.height/2)/zoom;}
            if(useEditor.getState().PasteAnchor)useEditor.getState().paste(cellPoint(p));requestDraw.current();
        }}
        onPointerDown={event=>{if(event.button===2)return;host.current!.focus({preventScroll:true});host.current!.setPointerCapture(event.pointerId);editorInput.down(event,screen(event));}}
        onMouseDown={event=>{event.preventDefault();if(event.button===2){host.current!.focus({preventScroll:true});editorInput.down(event,screen(event));}}}
        onPointerMove={event=>editorInput.move(screen(event))}
        onPointerUp={event=>{editorInput.up(event.button,screen(event));if(host.current?.hasPointerCapture(event.pointerId))host.current.releasePointerCapture(event.pointerId);}}
        onPointerLeave={()=>editorInput.leave()}
        onPointerCancel={()=>editorInput.cancel()}
    />;
}
