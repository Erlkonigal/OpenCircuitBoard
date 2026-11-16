import { useEditor } from './EditorStore';
import { cellKey, lineCells, type Grid, type Point } from './Model';
import { selectionContains } from './Selection';
import type { EditorCommand } from './EditorShortcuts';
import { CellSize } from './TileGeometry';
import { SplitPath } from './SplitPath';
export interface CanvasView {
    x: number;
    y: number;
    zoom: number;
    width: number;
    height: number;
}
interface Adapter {
    View: CanvasView;
    world: (point: Point) => Point;
    cell: (point: Point) => Point;
    redraw: () => void;
    cursor: (point: Point) => void;
    latch: (point: Point) => void;
}
interface PointerInput {
    button: number;
    shiftKey: boolean;
}
interface BaseGesture {
    Start: Point;
    Last: Point;
    Screen: Point;
}
type Gesture = BaseGesture & ({
    Kind: 'paint' | 'pendingMove' | 'move' | 'rectanglePaint';
} | {
    Kind: 'marquee';
    Add: boolean;
    Dragged: boolean;
    Toggle?: number;
} | {
    Kind: 'split';
    Path: SplitPath;
} | {
    Kind: 'resize';
    Corner: number;
    Grid: Grid;
} | {
    Kind: 'pan';
    Camera: Point;
    Button: number;
});
const boundsBetween = (a: Point, b: Point): Grid => ({ originX: Math.min(a.x, b.x), originY: Math.min(a.y, b.y), width: Math.abs(a.x - b.x) + 1, height: Math.abs(a.y - b.y) + 1 });
/** Owns mouse gesture transitions. Document commands and camera changes are explicit effects. */
export class EditorInput {
    private Adapter?: Adapter;
    private Gesture: Gesture | null = null;
    private Space = false;
    Hover: Point | null = null;
    Vertex: Point | null = null;
    connect(adapter: Adapter) {
        this.Adapter = adapter;
        this.Gesture = null;
        this.Space = false;
        this.Hover = null;
        this.Vertex = null;
        return () => {
            if (this.Adapter === adapter) {
                this.Adapter = undefined;
                this.Gesture = null;
                this.Space = false;
            }
        };
    }
    private currentGesture() {
        if (this.Gesture && useEditor.getState().Gesture !== this.Gesture.Kind)
            this.Gesture = null;
        return this.Gesture;
    }
    private vertex(screen: Point) {
        const world = this.Adapter!.world(screen), grid = useEditor.getState().Board.grid;
        return { x: Math.max(grid.originX, Math.min(grid.originX + grid.width, Math.round(world.x / CellSize))),
            y: Math.max(grid.originY, Math.min(grid.originY + grid.height, Math.round(world.y / CellSize))) };
    }
    private start(gesture: Gesture) { this.Gesture = gesture; useEditor.setState({ Gesture: gesture.Kind }); }
    space(held: boolean) { this.Space = held; this.Adapter?.redraw(); }
    get cursor() {
        const s = useEditor.getState(), g = this.currentGesture();
        if (g?.Kind === 'pan')
            return 'grabbing';
        if (this.Space)
            return 'grab';
        if (g?.Kind === 'move')
            return s.PreviewValid ? 'grabbing' : 'not-allowed';
        if (s.Preview)
            return s.PreviewValid ? 'copy' : 'not-allowed';
        if (s.EditTool === 'draw' || s.EditTool === 'split' || g?.Kind === 'marquee')
            return 'crosshair';
        return 'default';
    }
    cancel() {
        const g = this.currentGesture();
        if (g?.Kind === 'pan' && this.Adapter) {
            this.Adapter.View.x = g.Camera.x;
            this.Adapter.View.y = g.Camera.y;
        }
        useEditor.getState().cancelInteraction();
        this.Gesture = null;
        this.Adapter?.redraw();
    }
    down(event: PointerInput, screen: Point) {
        const a = this.Adapter;
        if (!a)
            return;
        const s = useEditor.getState(), cell = a.cell(screen), base = { Start: cell, Last: cell, Screen: screen };
        this.Hover = cell;
        this.Vertex = this.vertex(screen);
        if (event.button === 2) {
            this.cancel();
            return;
        }
        if (this.currentGesture())
            return;
        if (event.button === 1 || (event.button === 0 && this.Space)) {
            this.start({ ...base, Kind: 'pan', Camera: { x: a.View.x, y: a.View.y }, Button: event.button });
            a.redraw();
            return;
        }
        if (event.button !== 0)
            return;
        if (s.Simulating) {
            a.latch(cell);
            return;
        }
        if (s.Preview?.Kind === 'paste') {
            s.paste(cell);
            s.confirmPaste();
            a.redraw();
            return;
        }
        if (s.EditTool === 'merge') {
            s.pickComponent(cell);
            return;
        }
        if (s.EditTool === 'split') {
            s.begin();
            const path = new SplitPath(this.Vertex);
            this.start({ ...base, Kind: 'split', Path: path });
            useEditor.setState({ SplitPath: path, SplitNotice: '' });
            a.redraw();
            return;
        }
        if (event.shiftKey && s.EditTool === 'pointer') {
            s.begin();
            this.start({ ...base, Kind: 'marquee', Add: true, Dragged: false, Toggle: s.Tiles.get(cellKey(cell))?.componentId });
            return;
        }
        if (s.EditTool === 'draw') {
            s.begin();
            if (event.shiftKey) {
                s.previewRectangle(cell, cell);
                this.start({ ...base, Kind: 'rectanglePaint' });
            }
            else {
                s.paint([cell]);
                this.start({ ...base, Kind: 'paint' });
            }
            return;
        }
        const world = a.world(screen), g = s.Board.grid;
        const corners = [[g.originX, g.originY], [g.originX + g.width, g.originY], [g.originX, g.originY + g.height], [g.originX + g.width, g.originY + g.height]];
        const corner = corners.findIndex(([x, y]) => Math.hypot(world.x - x * CellSize, world.y - y * CellSize) * a.View.zoom <= 10);
        if (corner >= 0) {
            s.begin();
            this.start({ ...base, Kind: 'resize', Corner: corner, Grid: { ...g } });
            return;
        }
        const id = s.Tiles.get(cellKey(cell))?.componentId;
        s.begin();
        if (selectionContains(s, cell))
            this.start({ ...base, Kind: 'pendingMove' });
        else
            this.start({ ...base, Kind: 'marquee', Add: false, Dragged: false, Toggle: id });
    }
    move(screen: Point) {
        const a = this.Adapter;
        if (!a)
            return;
        let g = this.currentGesture();
        const s = useEditor.getState(), cell = a.cell(screen);
        this.Hover = cell;
        this.Vertex = this.vertex(screen);
        a.cursor(cell);
        if (!g) {
            if (s.Preview?.Kind === 'paste')
                s.paste(cell);
            a.redraw();
            return;
        }
        switch (g.Kind) {
            case 'pan':
                a.View.x = g.Camera.x + (g.Screen.x - screen.x) / a.View.zoom;
                a.View.y = g.Camera.y + (g.Screen.y - screen.y) / a.View.zoom;
                if (s.Preview?.Kind === 'paste')
                    s.paste(a.cell(screen));
                break;
            case 'paint':
                s.paint(lineCells(g.Last, cell));
                break;
            case 'rectanglePaint':
                s.previewRectangle(g.Start, cell);
                break;
            case 'pendingMove':
                if (Math.hypot(screen.x - g.Screen.x, screen.y - g.Screen.y) < 4)
                    break;
                g = { ...g, Kind: 'move' };
                this.start(g);
                s.movePreview({ x: cell.x - g.Start.x, y: cell.y - g.Start.y });
                break;
            case 'move':
                s.movePreview({ x: cell.x - g.Start.x, y: cell.y - g.Start.y });
                break;
            case 'split':
                g.Path.append(this.Vertex);
                break;
            case 'marquee':
                g.Dragged ||= Math.hypot(screen.x - g.Screen.x, screen.y - g.Screen.y) >= 4;
                if (g.Dragged)
                    useEditor.setState({ Marquee: { Bounds: boundsBetween(g.Start, cell), Add: g.Add } });
                break;
            case 'resize': {
                const original = g.Grid, corner = g.Corner, w = a.world(screen);
                let left = original.originX, right = left + original.width, top = original.originY, bottom = top + original.height;
                if (corner % 2 === 0)
                    left = Math.min(Math.round(w.x / CellSize), right - 4);
                else
                    right = Math.max(Math.round(w.x / CellSize), left + 4);
                if (corner < 2)
                    top = Math.min(Math.round(w.y / CellSize), bottom - 4);
                else
                    bottom = Math.max(Math.round(w.y / CellSize), top + 4);
                s.resize({ originX: left, originY: top, width: right - left, height: bottom - top });
                break;
            }
        }
        g.Last = cell;
        a.redraw();
    }
    up(button: number, screen: Point) {
        const a = this.Adapter, g = this.currentGesture();
        if (!a || !g || button !== (g.Kind === 'pan' ? g.Button : 0))
            return;
        const s = useEditor.getState(), cell = a.cell(screen);
        if (g.Kind === 'rectanglePaint')
            s.paintRectangle(g.Start, cell);
        if (g.Kind === 'move')
            s.confirmMove({ x: cell.x - g.Start.x, y: cell.y - g.Start.y });
        if (g.Kind === 'split') {
            g.Path.append(this.vertex(screen));
            s.splitAlong(g.Path);
        }
        if (g.Kind === 'marquee') {
            g.Dragged ||= Math.hypot(screen.x - g.Screen.x, screen.y - g.Screen.y) >= 4;
            if (!g.Dragged) {
                const ids = s.Selection?.ids ?? [], id = g.Toggle;
                if (g.Add) {
                    if (id) s.selectComponents(ids.includes(id) ? ids.filter(n => n !== id) : [...ids, id]);
                }
                else s.selectComponents(id ? [id] : []);
            }
            else
                s.selectRegionComponents(boundsBetween(g.Start, cell), g.Add ? 'add' : 'replace');
            useEditor.setState({ EditTool: 'pointer' });
        }
        if (g.Kind !== 'pan')
            useEditor.getState().commit();
        this.Gesture = null;
        useEditor.setState({ Gesture: 'idle', Marquee: null });
        a.redraw();
    }
    leave() { this.Hover = null; this.Vertex = null; this.Adapter?.redraw(); }
    execute(command: EditorCommand, point: Point) {
        const s = useEditor.getState();
        if (command === 'cancel') {
            this.cancel();
            return;
        }
        if (command === 'undo') {
            s.undo();
            this.currentGesture();
            return;
        }
        if (command === 'redo') {
            s.redo();
            return;
        }
        if (s.Simulating)
            return;
        if (command === 'pointer' || command === 'draw') {
            s.selectTool(command);
            this.Gesture = null;
            return;
        }
        if (s.Gesture !== 'idle' || s.Active)
            return;
        if (s.Preview && command !== 'paste')
            return;
        switch (command) {
            case 'merge':
                if (s.EditTool === 'merge')
                    s.confirmMerge();
                else
                    s.selectTool('merge');
                break;
            case 'split':
                if (s.EditTool !== 'split')
                    s.selectTool('split');
                break;
            case 'delete':
                s.deleteSelection();
                break;
            case 'copy':
                s.copy();
                break;
            case 'cut':
                s.copy(true);
                break;
            case 'paste':
                s.paste(point);
                break;
            case 'selectAll':
                s.selectTool('pointer');
                useEditor.getState().selectAll();
                break;
            case 'clearSelection':
                s.selectTool('pointer');
                useEditor.getState().selectComponents([]);
                break;
        }
    }
}
export const editorInput = new EditorInput();
