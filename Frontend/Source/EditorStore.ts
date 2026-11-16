import { create } from 'zustand';
import { cellKey, contains, ToolIds, newBoard, validateBoard, validateProject, type EditorTool, type Board, type Blueprint, type ClipboardItem, type Grid, type Point, type ProjectDocument, type RenderMode, type Selection, type Tile } from './Model';
import { CellStore, inkSource, type CellChange } from './CellStore';
import { ComponentIndex } from './ComponentIndex';
import { connectedRegions, snapshotTiles } from './ComponentTopology';
import { selectionSource, selectionIds } from './Selection';
import { loadRenderMode, saveRenderMode } from './Preferences';
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
interface State {
    Board: Board;
    Tiles: CellStore;
    Components: ComponentIndex;
    Ids: {
        Next: number;
    };
    Stroke: Tile | null;
    EditTool: EditorTool;
    Gesture: 'idle' | 'pendingMove' | 'marquee' | 'move' | 'paint' | 'resize' | 'pan';
    Marquee: {
        Bounds: Grid;
        Local: boolean;
    } | null;
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
    splitSelection: () => boolean;
    begin: () => void;
    paint: (points: Point[], remove?: boolean) => void;
    commit: () => void;
    cancel: () => void;
    undo: () => void;
    redo: () => void;
    select: (bounds: Grid | null) => void;
    selectComponents: (ids: number[]) => void;
    selectRegionComponents: (bounds: Grid) => void;
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
const EmptyPreview = { Preview: null, PreviewValid: false, PasteAnchor: null };
const EmptyMerge = { MergeIds: [] as number[], MergeError: '' };
function allocate(s: State) { if (s.Ids.Next > 2147483647)
    throw Error('ComponentIdLimit'); return s.Ids.Next++; }
function setTiles(s: State, tiles: CellStore) { s.Components.sync(tiles); return { Tiles: tiles, Revision: s.Revision + 1 }; }
function selectionItem(s: State): ClipboardItem | null {
    if (!s.Selection)
        return null;
    const source = selectionSource(s), b = s.Selection.kind === 'region' ? s.Selection.bounds : source.Bounds;
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
    EditTool: 'pointer', Gesture: 'idle', Marquee: null, ToolSelection: null, ...EmptyMerge, Blueprints: [], RenderMode: loadRenderMode(), Selection: null,
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
            EditTool: 'pointer', Gesture: 'idle', Marquee: null, ToolSelection: null, ...EmptyMerge, Blueprints: project.blueprints, Selection: null, Clipboard: [], ClipboardIndex: -1, ClipboardOrigin: 'copy',
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
            set({ EditTool: id, ToolSelection: restore, Selection: id === 'split' && restore?.kind === 'region' ? restore : null, RightOpen: true });
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
        if (s.Simulating || s.MergeIds.length < 2 || !s.Components.connected(s.MergeIds))
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
    splitSelection: () => {
        const s = get();
        if (s.Simulating || s.Selection?.kind !== 'region')
            return false;
        const groups = new Map<number, Tile[]>(), changes: [string, Tile][] = [];
        for (const tile of selectionSource(s).values()) {
            let group = groups.get(tile.componentId);
            if (!group) {
                group = [];
                groups.set(tile.componentId, group);
            }
            group.push(tile);
        }
        for (const [id, selected] of groups) {
            if (selected.length === s.Components.count(id))
                continue;
            for (const region of connectedRegions(selected)) {
                const componentId = allocate(s);
                for (const tile of region)
                    changes.push([cellKey(tile), { ...tile, componentId }]);
            }
        }
        if (!changes.length)
            return false;
        s.begin();
        set({ ...setTiles(s, s.Tiles.update(changes)), EditTool: 'pointer', ToolSelection: null, Selection: { kind: 'components', ids: [...new Set(changes.map(([, tile]) => tile.componentId))] } });
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
        if (!remove && !s.Stroke) {
            const point = points.find(p => contains(s.Board.grid, p));
            if (!point)
                return;
            const existing = s.Tiles.get(cellKey(point)), id = s.Board.selectedTool;
            const stroke = existing?.toolId === id ? existing : { ...point, toolId: id, componentId: allocate(s), isOn: id === 'latch' ? s.Board.latchInitialState : true, ...(id === 'clock' ? { clockHoldTicks: s.Board.clockHoldTicks } : {}) };
            set({ Stroke: stroke });
            s = get();
        }
        for (const point of points) {
            if (!contains(s.Board.grid, point))
                continue;
            const key = cellKey(point), before = s.Tiles.get(key);
            if (remove) {
                if (before)
                    changes.set(key, undefined);
            }
            else {
                const tile = { ...s.Stroke!, ...point };
                if (JSON.stringify(before) !== JSON.stringify(tile))
                    changes.set(key, tile);
            }
        }
        if (changes.size)
            set(setTiles(s, s.Tiles.update(changes)));
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
        if (selection?.kind === 'region') {
            const cells = [...s.Tiles.query(selection.bounds)].map(cellKey);
            selection = cells.length ? { ...selection, cells } : null;
        }
        else if (selection) {
            const ids = selection.ids.filter(id => s.Components.count(id));
            selection = ids.length ? { ...selection, ids } : null;
        }
        const command = { changes, beforeGrid: before.grid, afterGrid: s.Board.grid, beforeSelection: before.selection, afterSelection: selection, beforeBlueprints: before.blueprints, afterBlueprints: s.Blueprints };
        set({ Active: null, Stroke: null, Selection: selection, ...((changes.length || JSON.stringify(before.grid) !== JSON.stringify(s.Board.grid) || before.blueprints !== s.Blueprints) ? { Undo: [...s.Undo, command], Redo: [] } : {}) });
    },
    cancel: () => {
        const s = get(), selection = s.EditTool === 'merge' || s.EditTool === 'split' ? s.ToolSelection : s.Active ? s.Active.selection : s.Selection;
        set({ ...EmptyPreview, ...EmptyMerge, EditTool: 'pointer', ToolSelection: null, Gesture: 'idle', Marquee: null, Active: null, Stroke: null, Selection: selection,
            ...(s.Active ? { ...setTiles(s, s.Active.tiles), Board: { ...s.Board, grid: s.Active.grid }, Blueprints: s.Active.blueprints } : {}) });
    },
    cancelInteraction: () => { const s = get(), clear = s.EditTool === 'pointer' && s.Gesture === 'idle' && !s.Preview && !s.Active; s.cancel(); if (clear)
        set({ Selection: null }); },
    undo: () => {
        const s = get();
        if (s.Simulating)
            return;
        if (s.Active || s.Preview || s.Gesture !== 'idle' || s.EditTool === 'merge' || s.EditTool === 'split') {
            s.cancel();
            return;
        }
        const c = s.Undo.at(-1);
        if (!c)
            return;
        set({ ...setTiles(s, s.Tiles.update(c.changes.map(c => [c.key, c.before]))), EditTool: 'pointer', Board: { ...s.Board, grid: c.beforeGrid }, Selection: c.beforeSelection, Blueprints: c.beforeBlueprints, Undo: s.Undo.slice(0, -1), Redo: [...s.Redo, c] });
    },
    redo: () => {
        const s = get();
        if (s.Simulating || s.Active || s.Preview || s.Gesture !== 'idle' || s.EditTool === 'merge' || s.EditTool === 'split')
            return;
        const c = s.Redo.at(-1);
        if (!c)
            return;
        set({ ...setTiles(s, s.Tiles.update(c.changes.map(c => [c.key, c.after]))), EditTool: 'pointer', Board: { ...s.Board, grid: c.afterGrid }, Selection: c.afterSelection, Blueprints: c.afterBlueprints, Redo: s.Redo.slice(0, -1), Undo: [...s.Undo, c] });
    },
    select: bounds => { const s = get(), cells = bounds ? [...s.Tiles.query(bounds)].map(cellKey) : []; set({ Selection: bounds && cells.length ? { kind: 'region', bounds, cells } : null }); },
    selectComponents: ids => { const s = get(), valid = [...new Set(ids)].filter(id => s.Components.count(id)); set({ Selection: valid.length ? { kind: 'components', ids: valid } : null, RightOpen: valid.length ? true : s.RightOpen }); },
    selectRegionComponents: bounds => { const s = get(); s.selectComponents([...new Set([...s.Tiles.query(bounds)].map(t => t.componentId))]); },
    selectAll: () => { const s = get(); if (!s.Simulating)
        s.selectComponents([...s.Components.ids()]); },
    movePreview: offset => {
        const s = get();
        if (!s.Selection || s.Simulating)
            return;
        const source = s.Preview?.Kind === 'move' ? s.Preview.Source : selectionSource(s), b = s.Selection.kind === 'region' ? s.Selection.bounds : source.Bounds!;
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
        const changes = new Map<string, Tile | undefined>(), groups = new Map<number, Tile[]>();
        for (const tile of p.Source.values()) {
            changes.set(cellKey(tile), undefined);
            let group = groups.get(tile.componentId);
            if (!group) {
                group = [];
                groups.set(tile.componentId, group);
            }
            group.push(tile);
        }
        const cells: string[] = [];
        for (const [id, tiles] of groups)
            for (const region of connectedRegions(tiles)) {
                const componentId = tiles.length === s.Components.count(id) ? id : allocate(s);
                for (const t of region) {
                    const tile = { ...t, x: t.x + offset.x, y: t.y + offset.y, componentId }, key = cellKey(tile);
                    changes.set(key, tile);
                    cells.push(key);
                }
            }
        set({ ...setTiles(s, s.Tiles.update(changes)), Selection: s.Selection?.kind === 'components' ? s.Selection : { kind: 'region', bounds: p.Bounds, cells }, ...EmptyPreview });
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
        set({ EditTool: 'pointer', ToolSelection: null, Gesture: 'idle', ...EmptyMerge, Preview: { Source: source, Offset: anchor, Kind: 'paste', Bounds: { originX: anchor.x, originY: anchor.y, width: item.width, height: item.height } }, PasteAnchor: anchor, PreviewValid: previewValid(s, source, anchor) });
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
        set({ ...setTiles(s, s.Tiles.update((function* () { for (const key of source.keys())
                yield [key, undefined] as const; })())), Selection: null, EditTool: 'pointer' });
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
    configure: (patch, selection = false) => {
        const s = get();
        if (s.Simulating)
            return;
        if (patch.clockHoldTicks !== undefined && (!Number.isInteger(patch.clockHoldTicks) || patch.clockHoldTicks < 1 || patch.clockHoldTicks > 2147483647))
            return;
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
            set({ Board: { ...s.Board, ...(patch.clockHoldTicks ? { clockHoldTicks: patch.clockHoldTicks } : {}), ...(patch.isOn !== undefined ? { latchInitialState: patch.isOn } : {}), ...(patch.toolId ? { selectedTool: patch.toolId } : {}) } });
    },
    activateDock: (side, id) => { const s = get(), a = side === 'left' ? 'LeftDock' : 'RightDock', b = side === 'left' ? 'RightDock' : 'LeftDock'; set({ [a]: id, ...(s[b] === id ? { [b]: s[a] } : {}) }); },
    log: text => set(s => ({ Events: [...s.Events.slice(-999), `${new Date().toLocaleTimeString()}  ${text}`] })), setRuntime: states => set({ Runtime: states }),
}));
