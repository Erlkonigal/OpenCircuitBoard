import { create } from 'zustand';
import { inkSettings, isDirectional, validateInkSettings, type InkSettings, cellKey, contains, ToolIds, newBoard, validateBoard, validateProject, type EditorTool, type Board, type Blueprint, type ClipboardItem, type Grid, type Point, type ProjectDocument, type RenderMode, type Selection, type Tile } from './Model';
import { CellStore, inkSource, type CellChange } from './CellStore';
import { ComponentIndex } from './ComponentIndex';
import { compatibleComponents, connectedRegions, snapshotTiles } from './ComponentTopology';
import { selectionSource, selectionIds } from './Selection';
import { loadRenderMode, saveRenderMode } from './Preferences';
import { SplitPath } from './SplitPath';
interface Document {
    tiles: CellStore;
    grid: Grid;
    selection: Selection | null;
    blueprints: Blueprint[];
}
interface Command {
    changes: CellChange[];
    beforeGrid: Grid;
    afterGrid: Grid;
    beforeSelection: Selection | null;
    afterSelection: Selection | null;
    beforeBlueprints: Blueprint[];
    afterBlueprints: Blueprint[];
}
export interface RuntimeGrid {
    width: number;
    height: number;
    originX: number;
    originY: number;
    states: Uint8Array;
    dirtyChunks?: readonly Point[] | null;
    chunkVersions?: Uint32Array;
    generation?: number;
}
export interface PlacementPreview {
    Source: CellStore;
    Offset: Point;
    Bounds: Grid;
    Kind: 'paste' | 'move';
}
export interface RectanglePaintPreview {
    Bounds: Grid;
    Anchor: Point;
    Material: Pick<Tile, 'toolId' | 'isOn' | 'clockHoldTicks' | 'direction' | 'crossMask'>;
}
interface State {
    DrawSettings: InkSettings;
    rotate: (steps: number) => void;
    Board: Board;
    Tiles: CellStore;
    Components: ComponentIndex;
    Ids: {
        Next: number;
    };
    Stroke: {
        Tile: Tile;
        FromExisting: boolean;
        Targets: Set<number>;
    } | null;
    EditTool: EditorTool;
    Gesture: 'idle' | 'pendingMove' | 'marquee' | 'move' | 'paint' | 'resize' | 'pan' | 'split' | 'rectanglePaint';
    RectanglePaint: RectanglePaintPreview | null;
    Marquee: {
        Bounds: Grid;
        Add: boolean;
    } | null;
    SplitPath: SplitPath | null;
    SplitNotice: string;
    ToolSelection: Selection | null;
    MergeIds: number[];
    MergeError: string;
    Blueprints: Blueprint[];
    RenderMode: RenderMode;
    Selection: Selection | null;
    Clipboard: ClipboardItem[];
    ClipboardIndex: number;
    ClipboardOrigin: 'copy' | 'blueprint';
    Undo: Command[];
    Redo: Command[];
    Active: Document | null;
    Preview: PlacementPreview | null;
    PreviewValid: boolean;
    PasteAnchor: Point | null;
    LeftDock: string;
    RightDock: string;
    LeftOpen: boolean;
    RightOpen: boolean;
    LeftWidth: number;
    RightWidth: number;
    Events: string[];
    Path: string;
    Recent: string[];
    Revision: number;
    Simulating: boolean;
    Runtime: Map<string, boolean>;
    RuntimeGrid: RuntimeGrid | null;
    load: (project: Board | ProjectDocument, path?: string) => void;
    export: () => Board;
    exportProject: () => ProjectDocument;
    setRenderMode: (mode: RenderMode) => void;
    createBlueprint: (name: string, fromClipboard?: boolean) => boolean;
    renameBlueprint: (id: string, name: string) => void;
    deleteBlueprint: (id: string) => void;
    useBlueprint: (id: string) => void;
    selectTool: (id: string) => void;
    pickComponent: (point: Point) => void;
    confirmMerge: () => boolean;
    mergeSelection: () => boolean;
    splitAlong: (path: SplitPath) => boolean;
    begin: () => void;
    paint: (points: Iterable<Point>, remove?: boolean) => void;
    previewRectangle: (start: Point, end: Point) => void;
    paintRectangle: (start: Point, end: Point) => void;
    commit: () => void;
    cancel: () => void;
    undo: () => void;
    redo: () => void;
    selectComponents: (ids: number[]) => void;
    selectRegionComponents: (bounds: Grid, mode?: 'replace' | 'add') => void;
    selectAll: () => void;
    cancelInteraction: () => void;
    movePreview: (offset: Point) => void;
    confirmMove: (offset: Point) => boolean;
    copy: (cut?: boolean) => boolean;
    paste: (anchor: Point) => void;
    confirmPaste: () => boolean;
    deleteSelection: () => void;
    resize: (grid: Grid) => boolean;
    configure: (patch: Partial<Tile>, selection?: boolean) => void;
    activateDock: (side: 'left' | 'right', id: string) => void;
    log: (text: string) => void;
    setRuntime: (states: Map<string, boolean>) => void;
}
const EmptyPreview = { RectanglePaint: null, Preview: null, PreviewValid: false, PasteAnchor: null };
const EmptyMerge = { MergeIds: [] as number[], MergeError: '' };
const EmptySplit = { SplitPath: null, SplitNotice: '' };
function allocate(s: State) {
    if (s.Ids.Next > 2147483647)
        throw Error('ComponentIdLimit');
    return s.Ids.Next++;
}
function setTiles(s: State, tiles: CellStore) { s.Components.sync(tiles); return { Tiles: tiles, Revision: s.Revision + 1 }; }
function selectionItem(s: State): ClipboardItem | null {
    if (!s.Selection)
        return null;
    const source = selectionSource(s), b = source.Bounds;
    if (!b)
        return null;
    return { width: b.width, height: b.height, tiles: snapshotTiles([...source.values()]).map(t => ({ ...t, x: t.x - b.originX, y: t.y - b.originY })) };
}
function previewValid(s: State, source: CellStore, offset: Point, excluded?: CellStore) {
    const b = source.Bounds, g = s.Board.grid;
    return !!b && contains(g, { x: b.originX + offset.x, y: b.originY + offset.y })
        && contains(g, { x: b.originX + offset.x + b.width - 1, y: b.originY + offset.y + b.height - 1 }) && !source.overlaps(s.Tiles, offset, excluded);
}
function* translated(source: CellStore, offset: Point): IterableIterator<readonly [string, Tile]> {
    for (const t of source.values()) {
        const tile = { ...t, x: t.x + offset.x, y: t.y + offset.y };
        yield [cellKey(tile), tile];
    }
}
export const useEditor = create<State>((set, get) => ({
    Board: newBoard(), Tiles: new CellStore(), Components: new ComponentIndex(), Ids: { Next: 1 }, Stroke: null,
    DrawSettings: {}, EditTool: 'pointer', Gesture: 'idle', Marquee: null, ToolSelection: null, ...EmptyMerge, ...EmptySplit, Blueprints: [], RenderMode: loadRenderMode(), Selection: null,
    Clipboard: [], ClipboardIndex: -1, ClipboardOrigin: 'copy', Undo: [], Redo: [], Active: null, ...EmptyPreview,
    LeftDock: 'circuitEditor', RightDock: 'eventLog', LeftOpen: true, RightOpen: true, LeftWidth: 272, RightWidth: 272,
    Events: [], Path: '', Recent: [], Revision: 0, Simulating: false, Runtime: new Map(), RuntimeGrid: null,
    load: (data, path = '') => {
        const project = 'board' in data ? validateProject(data) : { board: validateBoard(data), blueprints: [] };
        const tiles = CellStore.from(project.board.tiles);
        let next = 1;
        for (const tile of project.board.tiles)
            next = Math.max(next, tile.componentId + 1);
        set({ Board: { ...project.board, tiles: [] }, Tiles: tiles, Components: new ComponentIndex(tiles), Ids: { Next: next }, Stroke: null,
            DrawSettings: {}, EditTool: 'pointer', Gesture: 'idle', Marquee: null, ToolSelection: null, ...EmptyMerge, ...EmptySplit, Blueprints: project.blueprints, Selection: null, Clipboard: [], ClipboardIndex: -1, ClipboardOrigin: 'copy',
            Undo: [], Redo: [], Active: null, ...EmptyPreview, Path: path, Runtime: new Map(), RuntimeGrid: null, Revision: get().Revision + 1 });
    },
    export: () => { const s = get(); return { ...s.Board, grid: { ...s.Board.grid }, tiles: [...s.Tiles.values()].sort((a, b) => a.y - b.y || a.x - b.x) }; },
    exportProject: () => ({ board: get().export(), blueprints: get().Blueprints }),
    setRenderMode: mode => { saveRenderMode(mode); set({ RenderMode: mode }); },
    createBlueprint: (name, fromClipboard = false) => {
        const s = get(), item = fromClipboard ? s.Clipboard[s.ClipboardIndex] : selectionItem(s);
        if (s.Simulating || !name.trim() || !item?.tiles.length)
            return false;
        s.begin();
        set({ Blueprints: [...s.Blueprints, { id: crypto.randomUUID(), name: name.trim(), width: item.width, height: item.height, tiles: snapshotTiles(item.tiles) }] });
        get().commit();
        return true;
    },
    renameBlueprint: (id, name) => {
        const s = get();
        if (s.Simulating || !name.trim() || !s.Blueprints.some(b => b.id === id && b.name !== name.trim()))
            return;
        s.begin();
        set({ Blueprints: s.Blueprints.map(b => b.id === id ? { ...b, name: name.trim() } : b) });
        get().commit();
    },
    deleteBlueprint: id => {
        const s = get();
        if (s.Simulating || !s.Blueprints.some(b => b.id === id))
            return;
        s.begin();
        set({ Blueprints: s.Blueprints.filter(b => b.id !== id) });
        get().commit();
    },
    useBlueprint: id => {
        const s = get(), b = s.Blueprints.find(b => b.id === id);
        if (!b || s.Simulating)
            return;
        set({ Clipboard: [{ width: b.width, height: b.height, tiles: b.tiles }, ...s.Clipboard].slice(0, 4), ClipboardIndex: 0, ClipboardOrigin: 'blueprint', ...EmptyPreview });
    },
    selectTool: id => {
        if (get().Simulating)
            return;
        const previous = get();
        const restore = previous.EditTool === 'merge' || previous.EditTool === 'split' ? previous.ToolSelection : previous.Selection;
        previous.cancel();
        const s = get();
        if (id === 'merge' || id === 'split') {
            set({ EditTool: id, ToolSelection: restore, Selection: id === 'split' ? restore : null, RightOpen: true });
            return;
        }
        if (id === 'pointer') {
            set({ EditTool: 'pointer', Selection: restore });
            return;
        }
        const tool = id === 'draw' ? s.Board.selectedTool : id;
        if (!ToolIds.slice(1).includes(tool))
            throw Error('ProjectBoardInvalid');
        set({ EditTool: 'draw', Selection: null, Board: { ...s.Board, selectedTool: tool } });
    },
    pickComponent: point => {
        const s = get();
        if (s.Simulating || s.EditTool !== 'merge')
            return;
        const id = s.Tiles.get(cellKey(point))?.componentId;
        if (!id)
            return;
        if (s.MergeIds.includes(id)) {
            const ids = s.MergeIds.filter(n => n !== id);
            if (!s.Components.connected(ids)) {
                set({ MergeError: 'Keep the selected regions connected.' });
                return;
            }
            set({ MergeIds: ids, MergeError: '' });
            return;
        }
        if (!s.Components.canJoin(s.MergeIds, id)) {
            set({ MergeError: 'Choose an adjacent component with the same ink and settings.' });
            return;
        }
        set({ MergeIds: [...s.MergeIds, id], MergeError: '' });
    },
    confirmMerge: () => {
        const s = get();
        if (s.Simulating || s.Active || s.Gesture !== 'idle' || !s.Components.canMerge(s.MergeIds))
            return false;
        s.begin();
        const componentId = allocate(s), changes: [string, Tile][] = [];
        for (const id of s.MergeIds)
            for (const tile of s.Components.members(id))
                changes.push([cellKey(tile), { ...tile, componentId }]);
        set({ ...setTiles(s, s.Tiles.update(changes)), ...EmptyMerge, EditTool: 'pointer', ToolSelection: null, Selection: { kind: 'components', ids: [componentId] } });
        get().commit();
        return true;
    },
    mergeSelection: () => {
        const s = get(), ids = selectionIds(s);
        if (s.Simulating || s.EditTool !== 'pointer' || s.Active || s.Preview || s.Gesture !== 'idle' || !s.Components.canMerge(ids))
            return false;
        set({ MergeIds: ids });
        return get().confirmMerge();
    },
    splitAlong: path => {
        const s = get();
        if (s.Simulating || s.EditTool !== 'split')
            return false;
        if (!path.Edges.size) {
            set({ ...EmptySplit });
            get().commit();
            return false;
        }
        const ids = new Set<number>(), blocked = new Set(path.Edges.keys());
        for (const { Cells: [a, b] } of path.Edges.values()) {
            const first = s.Tiles.get(cellKey(a)), second = s.Tiles.get(cellKey(b));
            if (first && first.componentId === second?.componentId)
                ids.add(first.componentId);
        }
        const changes: [string, Tile][] = [], selected: number[] = [];
        for (const id of ids) {
            const regions = connectedRegions(s.Components.members(id), blocked);
            if (regions.length < 2)
                continue;
            selected.push(id);
            for (const region of regions.slice(1)) {
                const componentId = allocate(s);
                selected.push(componentId);
                for (const tile of region)
                    changes.push([cellKey(tile), { ...tile, componentId }]);
            }
        }
        if (!changes.length) {
            set({ SplitPath: null, SplitNotice: 'The line did not cut through a component.' });
            get().commit();
            return false;
        }
        s.begin();
        const selection: Selection = { kind: 'components', ids: selected };
        set({ ...setTiles(s, s.Tiles.update(changes)), ...EmptySplit, Selection: selection, ToolSelection: selection });
        get().commit();
        return true;
    },
    begin: () => {
        const s = get();
        if (!s.Simulating && !s.Active)
            set({ Active: { tiles: s.Tiles, grid: s.Board.grid, selection: s.Selection, blueprints: s.Blueprints }, Stroke: null });
    },
    paint: (points, remove = false) => {
        let s = get();
        if (s.Simulating)
            return;
        s.begin();
        s = get();
        const changes = new Map<string, Tile | undefined>();
        let stroke = s.Stroke;
        for (const point of points) {
            if (!contains(s.Board.grid, point))
                continue;
            if (!remove && !stroke) {
                const existing = s.Tiles.get(cellKey(point)), id = s.Board.selectedTool, fromExisting = existing?.toolId === id;
                const tile = fromExisting ? existing : { ...inkSettings(id,s.DrawSettings), ...point, toolId: id, componentId: allocate(s), isOn: id === 'button' ? s.Board.buttonInitialState : true, ...(id === 'clock' ? { clockHoldTicks: s.Board.clockHoldTicks } : {}) };
                stroke = { Tile: tile, FromExisting: fromExisting, Targets: new Set() };
                set({ Stroke: stroke });
                s = get();
            }
            const key = cellKey(point), before = s.Tiles.get(key);
            if (remove) {
                if (before)
                    changes.set(key, undefined);
            }
            else if (stroke!.FromExisting && before && before.componentId !== stroke!.Tile.componentId && compatibleComponents(stroke!.Tile, before)) {
                // Keep the target whole until it is connected to the stroke, including targets reached later in this frame.
                stroke!.Targets.add(before.componentId);
            }
            else {
                const tile = { ...stroke!.Tile, ...point };
                if (JSON.stringify(before) !== JSON.stringify(tile))
                    changes.set(key, tile);
            }
        }
        if (changes.size) {
            set(setTiles(s, s.Tiles.update(changes)));
            s = get();
        }
        if (!remove && stroke?.FromExisting && stroke.Targets.size) {
            const joined = new Set([stroke.Tile.componentId]);
            for (const id of joined)
                for (const other of s.Components.neighbors(id))
                    if (stroke.Targets.has(other))
                        joined.add(other);
            if (s.Components.canMerge([...joined])) {
                const merged: [string, Tile][] = [];
                for (const id of joined)
                    if (id !== stroke.Tile.componentId) {
                        for (const tile of s.Components.members(id))
                            merged.push([cellKey(tile), { ...tile, componentId: stroke.Tile.componentId }]);
                        stroke.Targets.delete(id);
                    }
                set(setTiles(s, s.Tiles.update(merged)));
            }
        }
    },
    previewRectangle: (start, end) => {
        const s = get();
        if (s.Simulating || s.EditTool !== 'draw') return;
        s.begin();
        const g = s.Board.grid, left = Math.max(g.originX, Math.min(start.x, end.x)), top = Math.max(g.originY, Math.min(start.y, end.y));
        const right = Math.min(g.originX + g.width - 1, Math.max(start.x, end.x)), bottom = Math.min(g.originY + g.height - 1, Math.max(start.y, end.y));
        if (left > right || top > bottom) { set({ RectanglePaint: null }); return; }
        const anchor = { x: Math.max(left, Math.min(right, start.x)), y: Math.max(top, Math.min(bottom, start.y)) };
        const existing = s.Tiles.get(cellKey(anchor)), id = s.Board.selectedTool;
        const material = existing?.toolId === id ? existing : { ...inkSettings(id,s.DrawSettings), toolId: id, isOn: id === 'button' ? s.Board.buttonInitialState : true, ...(id === 'clock' ? { clockHoldTicks: s.Board.clockHoldTicks } : {}) };
        set({ RectanglePaint: { Bounds: { originX: left, originY: top, width: right - left + 1, height: bottom - top + 1 }, Anchor: anchor, Material: material } });
    },
    paintRectangle: (start, end) => {
        get().previewRectangle(start, end);
        const s = get(), p = s.RectanglePaint;
        if (s.Simulating || s.EditTool !== 'draw' || !p) return;
        const b = p.Bounds, dx = start.x <= end.x ? 1 : -1, dy = start.y <= end.y ? 1 : -1;
        // Iterate from the actual anchor; reversing a drag must not change inheritance.
        s.paint((function* () {
            for (let row = 0; row < b.height; row++)
                for (let column = 0; column < b.width; column++)
                    yield { x: p.Anchor.x + column * dx, y: p.Anchor.y + row * dy };
        })());
        set({ RectanglePaint: null });
    },
    commit: () => {
        let s = get();
        const before = s.Active;
        if (!before)
            return;
        const firstChanges = [...s.Tiles.changes(before.tiles)], ids = new Set<number>();
        for (const c of firstChanges) {
            if (c.before)
                ids.add(c.before.componentId);
            if (c.after)
                ids.add(c.after.componentId);
        }
        const normalized = s.Components.normalize(s.Tiles, ids, () => allocate(s));
        if (normalized !== s.Tiles) {
            set(setTiles(s, normalized));
            s = get();
        }
        const changes = [...s.Tiles.changes(before.tiles)];
        let selection = s.Selection;
        if (selection) {
            const ids = selection.ids.filter(id => s.Components.count(id));
            selection = ids.length ? { ...selection, ids } : null;
        }
        const command = { changes, beforeGrid: before.grid, afterGrid: s.Board.grid, beforeSelection: before.selection, afterSelection: selection, beforeBlueprints: before.blueprints, afterBlueprints: s.Blueprints };
        set({ Active: null, Stroke: null, RectanglePaint: null, Selection: selection, ...((changes.length || JSON.stringify(before.grid) !== JSON.stringify(s.Board.grid) || before.blueprints !== s.Blueprints) ? { Undo: [...s.Undo, command], Redo: [] } : {}) });
    },
    cancel: () => {
        const s = get(), selection = s.EditTool === 'merge' || s.EditTool === 'split' ? s.ToolSelection : s.Active ? s.Active.selection : s.Selection;
        set({ ...EmptyPreview, ...EmptyMerge, ...EmptySplit, EditTool: 'pointer', ToolSelection: null, Gesture: 'idle', Marquee: null, Active: null, Stroke: null, Selection: selection,
            ...(s.Active ? { ...setTiles(s, s.Active.tiles), Board: { ...s.Board, grid: s.Active.grid }, Blueprints: s.Active.blueprints } : {}) });
    },
    cancelInteraction: () => {
        const s = get(), clear = s.EditTool === 'pointer' && s.Gesture === 'idle' && !s.Preview && !s.Active;
        s.cancel();
        if (clear)
            set({ Selection: null });
    },
    undo: () => {
        const s = get();
        if (s.Simulating)
            return;
        if (s.EditTool === 'split' && s.SplitPath) {
            const selection = s.Active?.selection ?? s.Selection;
            set({ Active: null, Stroke: null, Gesture: 'idle', ...EmptySplit, Selection: selection, ToolSelection: selection });
            return;
        }
        if (s.Active || s.Preview || s.Gesture !== 'idle' || s.EditTool === 'merge') {
            s.cancel();
            return;
        }
        const c = s.Undo.at(-1);
        if (!c)
            return;
        set({ ...setTiles(s, s.Tiles.update(c.changes.map(c => [c.key, c.before]))), ...EmptySplit, EditTool: s.EditTool === 'split' ? 'split' : 'pointer', ToolSelection: s.EditTool === 'split' ? c.beforeSelection : null,
            Board: { ...s.Board, grid: c.beforeGrid }, Selection: c.beforeSelection, Blueprints: c.beforeBlueprints, Undo: s.Undo.slice(0, -1), Redo: [...s.Redo, c] });
    },
    redo: () => {
        const s = get();
        if (s.Simulating || s.Active || s.Preview || s.Gesture !== 'idle' || s.EditTool === 'merge')
            return;
        const c = s.Redo.at(-1);
        if (!c)
            return;
        set({ ...setTiles(s, s.Tiles.update(c.changes.map(c => [c.key, c.after]))), ...EmptySplit, EditTool: s.EditTool === 'split' ? 'split' : 'pointer', ToolSelection: s.EditTool === 'split' ? c.afterSelection : null,
            Board: { ...s.Board, grid: c.afterGrid }, Selection: c.afterSelection, Blueprints: c.afterBlueprints, Redo: s.Redo.slice(0, -1), Undo: [...s.Undo, c] });
    },
    selectComponents: ids => { const s = get(), valid = [...new Set(ids)].filter(id => s.Components.count(id)); set({ Selection: valid.length ? { kind: 'components', ids: valid } : null, RightOpen: valid.length ? true : s.RightOpen }); },
    selectRegionComponents: (bounds, mode = 'replace') => {
        const s = get(), ids = new Set(mode === 'add' ? selectionIds(s) : []);
        for (const tile of s.Tiles.query(bounds))
            ids.add(tile.componentId);
        s.selectComponents([...ids]);
    },
    selectAll: () => {
        const s = get();
        if (!s.Simulating)
            s.selectComponents([...s.Components.ids()]);
    },
    movePreview: offset => {
        const s = get();
        if (!s.Selection || s.Simulating)
            return;
        const source = s.Preview?.Kind === 'move' ? s.Preview.Source : selectionSource(s), b = source.Bounds!;
        set({ Preview: { Source: source, Offset: offset, Kind: 'move', Bounds: { ...b, originX: b.originX + offset.x, originY: b.originY + offset.y } }, PreviewValid: previewValid(s, source, offset, source), PasteAnchor: null });
    },
    confirmMove: offset => {
        const s = get();
        s.movePreview(offset);
        const next = get(), p = next.Preview;
        if (!next.Selection || !p || !next.PreviewValid || s.Simulating) {
            set(EmptyPreview);
            return false;
        }
        if (!offset.x && !offset.y) {
            set(EmptyPreview);
            return true;
        }
        s.begin();
        const changes = new Map<string, Tile | undefined>();
        for (const tile of p.Source.values())
            changes.set(cellKey(tile), undefined);
        for (const [key, tile] of translated(p.Source, offset))
            changes.set(key, tile);
        set({ ...setTiles(s, s.Tiles.update(changes)), ...EmptyPreview });
        get().commit();
        return true;
    },
    copy: (cut = false) => {
        const s = get();
        if (s.Simulating || s.Active || s.Preview || s.EditTool === 'merge' || s.EditTool === 'split')
            return false;
        const item = selectionItem(s);
        if (!item)
            return false;
        set({ Clipboard: [item, ...s.Clipboard].slice(0, 4), ClipboardIndex: 0, ClipboardOrigin: 'copy' });
        if (s.LeftDock !== 'clipboard' && s.RightDock !== 'clipboard')
            s.activateDock('left', 'clipboard');
        if (cut)
            get().deleteSelection();
        return true;
    },
    paste: anchor => {
        const s = get(), item = s.Clipboard[s.ClipboardIndex];
        if (!item || s.Simulating)
            return;
        if (s.Active || s.EditTool === 'merge' || s.EditTool === 'split')
            s.cancel();
        const source = inkSource(item);
        set({ EditTool: 'pointer', ToolSelection: null, Gesture: 'idle', ...EmptyMerge, ...EmptySplit, Preview: { Source: source, Offset: anchor, Kind: 'paste', Bounds: { originX: anchor.x, originY: anchor.y, width: item.width, height: item.height } }, PasteAnchor: anchor, PreviewValid: previewValid(s, source, anchor) });
    },
    confirmPaste: () => {
        const s = get(), p = s.Preview;
        if (!p || p.Kind !== 'paste' || !previewValid(s, p.Source, p.Offset) || s.Simulating)
            return false;
        s.begin();
        const ids = new Map<number, number>(), changes: [string, Tile][] = [];
        for (const [key, t] of translated(p.Source, p.Offset)) {
            let componentId = ids.get(t.componentId);
            if (!componentId) {
                componentId = allocate(s);
                ids.set(t.componentId, componentId);
            }
            changes.push([key, { ...t, componentId }]);
        }
        set({ ...setTiles(s, s.Tiles.update(changes)), EditTool: 'pointer', Selection: { kind: 'components', ids: [...ids.values()] }, ...EmptyPreview });
        get().commit();
        return true;
    },
    deleteSelection: () => {
        const s = get();
        if (!s.Selection || s.Simulating || s.Active || s.Preview || s.Gesture !== 'idle' || s.EditTool === 'merge' || s.EditTool === 'split')
            return;
        const source = selectionSource(s);
        s.begin();
        set({ ...setTiles(s, s.Tiles.update((function* () {
                for (const key of source.keys())
                    yield [key, undefined] as const;
            })())), Selection: null, EditTool: 'pointer' });
        get().commit();
    },
    resize: grid => {
        const s = get(), b = s.Tiles.Bounds;
        if (s.Simulating || grid.width < 4 || grid.height < 4 || ![grid.width, grid.height, grid.originX, grid.originY].every(Number.isInteger) || grid.originX < -2147483648 || grid.originY < -2147483648 || grid.originX + grid.width > 2147483647 || grid.originY + grid.height > 2147483647 || (b && (!contains(grid, { x: b.originX, y: b.originY }) || !contains(grid, { x: b.originX + b.width - 1, y: b.originY + b.height - 1 }))))
            return false;
        s.begin();
        set({ Board: { ...s.Board, grid }, Revision: s.Revision + 1 });
        return true;
    },
    rotate: steps => {
        const s = get(); if(s.Simulating || s.Active || s.Preview) return;
        if(s.Selection) {
            s.begin(); const changes: [string,Tile][] = [];
            for(const id of selectionIds(s)) for(const tile of s.Components.members(id)) if(isDirectional(tile.toolId)) changes.push([cellKey(tile),{...tile,direction:((tile.direction??0)+steps+4)%4}]);
            set(setTiles(s,s.Tiles.update(changes))); get().commit();
        } else set({DrawSettings:{...s.DrawSettings,direction:((s.DrawSettings.direction??0)+steps+4)%4}});
    },
    configure: (patch, selection = false) => {
        const s = get();
        if (s.Simulating)
            return;
        if (patch.clockHoldTicks !== undefined && (!Number.isInteger(patch.clockHoldTicks) || patch.clockHoldTicks < 1 || patch.clockHoldTicks > 2147483647))
            return;
        try { for (const tile of selection && s.Selection ? selectionIds(s).map(id=>s.Components.sample(id)!) : [{toolId:s.Board.selectedTool,...inkSettings(s.Board.selectedTool,s.DrawSettings)} as Tile]) validateInkSettings({...tile,...patch}, 'InvalidSettings'); } catch { return; }
        if (selection && s.Selection?.kind === 'components') {
            s.begin();
            const ids = selectionIds(s), changes: [string, Tile][] = [];
            for (const id of ids)
                for (const t of s.Components.members(id))
                    changes.push([cellKey(t), { ...t, ...patch, componentId: id }]);
            set(setTiles(s, s.Tiles.update(changes)));
            get().commit();
        }
        else if (!selection)
            set({ DrawSettings: {...s.DrawSettings,...Object.fromEntries(Object.entries(patch).filter(([key])=>['direction','crossMask'].includes(key)))}, Board: { ...s.Board, ...(patch.clockHoldTicks ? { clockHoldTicks: patch.clockHoldTicks } : {}), ...(patch.isOn !== undefined ? { buttonInitialState: patch.isOn } : {}), ...(patch.toolId ? { selectedTool: patch.toolId } : {}) } });
    },
    activateDock: (side, id) => { const s = get(), a = side === 'left' ? 'LeftDock' : 'RightDock', b = side === 'left' ? 'RightDock' : 'LeftDock'; set({ [a]: id, ...(s[b] === id ? { [b]: s[a] } : {}) }); },
    log: text => set(s => ({ Events: [...s.Events.slice(-999), `${new Date().toLocaleTimeString()}  ${text}`] })), setRuntime: states => set({ Runtime: states }),
}));
