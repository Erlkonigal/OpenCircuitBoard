import { create } from 'zustand';
import { cellKey, contains, edgeInGrid, edgeKey, ToolIds, newBoard, validateBoard, validateProject, type Board, type Blueprint, type ClipboardItem, type Grid, type IsolationEdge, type Point, type ProjectDocument, type RenderMode, type Selection, type Tile } from './Model';
import { CellStore, inkSource, type CellChange } from './CellStore';
import { IsolationStore, isolationSource } from './IsolationStore';
import { loadRenderMode, saveRenderMode } from './Preferences';
interface Document {
    tiles: CellStore;
    isolation: IsolationStore;
    grid: Grid;
    selection: Selection | null;
    blueprints: Blueprint[];
}
interface Command {
    changes: CellChange[];
    beforeIsolation: IsolationStore;
    afterIsolation: IsolationStore;
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
    Isolation: IsolationStore;
    Offset: Point;
    Bounds: Grid;
    Kind: 'paste' | 'move';
}
interface State {
    Board: Board;
    Tiles: CellStore;
    Isolation: IsolationStore;
    EditTool: 'ink' | 'isolation';
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
    begin: () => void;
    paintIsolation: (edges: IsolationEdge[], remove?: boolean) => void;
    paint: (points: Point[], remove?: boolean) => void;
    commit: () => void;
    cancel: () => void;
    undo: () => void;
    redo: () => void;
    select: (bounds: Grid | null) => void;
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
const SelectionSources = new WeakMap<Selection, { Tiles: CellStore; Source: CellStore }>();
function selectedSource(s: State): CellStore {
    if (!s.Selection) return new CellStore();
    const cached = SelectionSources.get(s.Selection);
    if (cached?.Tiles === s.Tiles) return cached.Source;
    const source = CellStore.from(s.Tiles.query(s.Selection.bounds));
    SelectionSources.set(s.Selection, { Tiles: s.Tiles, Source: source });
    return source;
}
function selectionItem(s: State): ClipboardItem | null {
    if (!s.Selection) return null;
    const b = s.Selection.bounds;
    return { width: b.width, height: b.height, isolationEdges: [...s.Isolation.query(b)].map(edge => ({ ...edge, x: edge.x - b.originX, y: edge.y - b.originY })), tiles: Array.from(selectedSource(s).values(), t => ({ ...t, x: t.x - b.originX, y: t.y - b.originY })) };
}
function previewValid(s: State, source: CellStore, edges: IsolationStore, offset: Point, excluded?: CellStore): boolean {
    const g = s.Board.grid, b = source.Bounds, e = edges.Bounds;
    return (!b || (contains(g, { x: b.originX + offset.x, y: b.originY + offset.y })
        && contains(g, { x: b.originX + offset.x + b.width - 1, y: b.originY + offset.y + b.height - 1 })))
        && (!e || (e.originX + offset.x >= g.originX && e.originY + offset.y >= g.originY
            && e.originX + offset.x + e.width <= g.originX + g.width && e.originY + offset.y + e.height <= g.originY + g.height))
        && !source.overlaps(s.Tiles, offset, excluded);
}
function translatedEdges(source: IsolationStore, offset: Point): IsolationEdge[] {
    return [...source.values()].map(edge => ({ ...edge, x: edge.x + offset.x, y: edge.y + offset.y }));
}
function* translated(source: CellStore, offset: Point): IterableIterator<readonly [string, Tile]> {
    for (const t of source.values()) {
        const tile = { ...t, x: t.x + offset.x, y: t.y + offset.y };
        yield [cellKey(tile), tile];
    }
}
export const useEditor = create<State>((set, get) => ({
    Board: newBoard(), Tiles: new CellStore(), Isolation: new IsolationStore(), EditTool: 'ink', Blueprints: [], RenderMode: loadRenderMode(), Selection: null,
    Clipboard: [], ClipboardIndex: -1, ClipboardOrigin: 'copy', Undo: [], Redo: [], Active: null, ...EmptyPreview,
    LeftDock: 'circuitEditor', RightDock: 'eventLog', LeftOpen: true, RightOpen: true, LeftWidth: 272, RightWidth: 272,
    Events: [], Path: '', Recent: [], Revision: 0, Simulating: false, Runtime: new Map(), RuntimeGrid: null,
    load: (data, path = '') => {
        const project = 'board' in data ? validateProject(data) : { board: validateBoard(data), blueprints: [] };
        set({ Board: { ...project.board, tiles: [], isolationEdges: [] }, Tiles: CellStore.from(project.board.tiles), Isolation: isolationSource(project.board), EditTool: 'ink', Blueprints: project.blueprints,
            Selection: null, Clipboard: [], ClipboardIndex: -1, ClipboardOrigin: 'copy', Undo: [], Redo: [], Active: null, ...EmptyPreview,
            Path: path, Runtime: new Map(), RuntimeGrid: null, Revision: get().Revision + 1 });
    },
    export: () => { const s = get(); return { ...s.Board, isolationEdges: [...s.Isolation.values()].sort((a, b) => a.y - b.y || a.x - b.x || a.axis.localeCompare(b.axis)), grid: { ...s.Board.grid }, tiles: [...s.Tiles.values()].sort((a, b) => a.y - b.y || a.x - b.x) }; },
    exportProject: () => ({ board: get().export(), blueprints: get().Blueprints }),
    setRenderMode: mode => { saveRenderMode(mode); set({ RenderMode: mode }); },
    createBlueprint: (name, fromClipboard = false) => {
        const s = get(), item = fromClipboard ? s.Clipboard[s.ClipboardIndex] : selectionItem(s);
        if (s.Simulating || !name.trim() || (!item || (!item.tiles.length && !item.isolationEdges?.length))) return false;
        s.begin();
        set({ Blueprints: [...s.Blueprints, { id: crypto.randomUUID(), name: name.trim(), width: item.width, height: item.height, isolationEdges: item.isolationEdges?.map(edge => ({ ...edge })) ?? [], tiles: item.tiles.map(t => ({ ...t })) }] });
        get().commit(); return true;
    },
    renameBlueprint: (id, name) => {
        const s = get(); if (s.Simulating || !name.trim() || !s.Blueprints.some(b => b.id === id && b.name !== name.trim())) return;
        s.begin(); set({ Blueprints: s.Blueprints.map(b => b.id === id ? { ...b, name: name.trim() } : b) }); get().commit();
    },
    deleteBlueprint: id => {
        const s = get(); if (s.Simulating || !s.Blueprints.some(b => b.id === id)) return;
        s.begin(); set({ Blueprints: s.Blueprints.filter(b => b.id !== id) }); get().commit();
    },
    useBlueprint: id => {
        const s = get(), blueprint = s.Blueprints.find(b => b.id === id); if (!blueprint || s.Simulating) return;
        const item = { width: blueprint.width, height: blueprint.height, tiles: blueprint.tiles, isolationEdges: blueprint.isolationEdges };
        set({ Clipboard: [item, ...s.Clipboard].slice(0, 4), ClipboardIndex: 0, ClipboardOrigin: 'blueprint', ...EmptyPreview });
    },
    selectTool: id => {
        if (get().Simulating) return;
        if (id === 'isolation') { set({ EditTool: 'isolation' }); return; }
        if (!ToolIds.slice(1).includes(id)) throw Error('ProjectBoardInvalid');
        set(s => ({ EditTool: 'ink', Board: { ...s.Board, selectedTool: id } }));
    },
    begin: () => { const s = get(); if (!s.Simulating && !s.Active) set({ Active: { tiles: s.Tiles, isolation: s.Isolation, grid: s.Board.grid, selection: s.Selection, blueprints: s.Blueprints } }); },
    paintIsolation: (edges, remove = false) => {
        const s = get(); if (s.Simulating) return; s.begin();
        const next = s.Isolation.update(edges.filter(edge => edgeInGrid(edge, s.Board.grid)), remove);
        if (next !== s.Isolation) set({ Isolation: next, Revision: s.Revision + 1 });
    },
    paint: (points, remove = false) => {
        const s = get(); if (s.Simulating) return; s.begin();
        const changes = new Map<string, Tile | undefined>();
        for (const point of points) {
            if (!contains(s.Board.grid, point)) continue;
            const key = cellKey(point);
            if (remove) { if (s.Tiles.has(key)) changes.set(key, undefined); }
            else if (!s.Tiles.has(key)) {
                const id = s.Board.selectedTool;
                changes.set(key, { ...point, toolId: id, isOn: id === 'latch' ? s.Board.latchInitialState : true,
                    ...(id === 'clock' ? { clockHoldTicks: s.Board.clockHoldTicks } : {}) });
            }
        }
        if (changes.size) set({ Tiles: s.Tiles.update(changes), Revision: s.Revision + 1 });
    },
    commit: () => {
        const s = get(), before = s.Active; if (!before) return;
        const changes = [...s.Tiles.changes(before.tiles)];
        const command = { changes, beforeIsolation: before.isolation, afterIsolation: s.Isolation, beforeGrid: before.grid, afterGrid: s.Board.grid, beforeSelection: before.selection,
            afterSelection: s.Selection, beforeBlueprints: before.blueprints, afterBlueprints: s.Blueprints };
        set({ Active: null, ...((changes.length || before.isolation !== s.Isolation || JSON.stringify(before.grid) !== JSON.stringify(s.Board.grid) || before.blueprints !== s.Blueprints) ? { Undo: [...s.Undo, command], Redo: [] } : {}) });
    },
    cancel: () => { const s = get(); set({ ...EmptyPreview, Active: null, ...(s.Active ? { Tiles: s.Active.tiles, Isolation: s.Active.isolation, Board: { ...s.Board, grid: s.Active.grid }, Selection: s.Active.selection, Blueprints: s.Active.blueprints, Revision: s.Revision + 1 } : {}) }); },
    undo: () => {
        get().cancel(); const s = get(), command = s.Undo.at(-1); if (!command || s.Simulating) return;
        set({ Tiles: s.Tiles.update(command.changes.map(c => [c.key, c.before])), Isolation: command.beforeIsolation, Board: { ...s.Board, grid: command.beforeGrid },
            Selection: command.beforeSelection, Blueprints: command.beforeBlueprints, Undo: s.Undo.slice(0, -1), Redo: [...s.Redo, command], Revision: s.Revision + 1 });
    },
    redo: () => {
        get().cancel(); const s = get(), command = s.Redo.at(-1); if (!command || s.Simulating) return;
        set({ Tiles: s.Tiles.update(command.changes.map(c => [c.key, c.after])), Isolation: command.afterIsolation, Board: { ...s.Board, grid: command.afterGrid },
            Selection: command.afterSelection, Blueprints: command.afterBlueprints, Redo: s.Redo.slice(0, -1), Undo: [...s.Undo, command], Revision: s.Revision + 1 });
    },
    select: bounds => {
        const s = get(), cells = bounds ? Array.from(s.Tiles.query(bounds), cellKey) : [];
        const isolationEdges = bounds ? [...s.Isolation.query(bounds)].map(edgeKey) : [];
        set({ Selection: bounds && (cells.length || isolationEdges.length) ? { bounds, cells, isolationEdges } : null });
    },
    movePreview: offset => {
        const s = get(); if (!s.Selection || s.Simulating) return;
        const isolation = s.Preview?.Kind === 'move' ? s.Preview.Isolation : IsolationStore.from(s.Isolation.query(s.Selection.bounds));
        const source = s.Preview?.Kind === 'move' ? s.Preview.Source : selectedSource(s), b = s.Selection.bounds;
        set({ Preview: { Source: source, Isolation: isolation, Offset: offset, Kind: 'move', Bounds: { ...b, originX: b.originX + offset.x, originY: b.originY + offset.y } },
            PreviewValid: previewValid(s, source, isolation, offset, source), PasteAnchor: null });
    },
    confirmMove: offset => {
        const s = get(); s.movePreview(offset); const next = get(), preview = next.Preview;
        if (!next.Selection || !preview || !next.PreviewValid || s.Simulating) { set(EmptyPreview); return false; }
        s.begin(); const changes = new Map<string, Tile | undefined>();
        for (const key of preview.Source.keys()) changes.set(key, undefined);
        const cells: string[] = []; for (const [key, tile] of translated(preview.Source, offset)) { changes.set(key, tile); cells.push(key); }
        const movedEdges = translatedEdges(preview.Isolation, offset);
        set({ Tiles: s.Tiles.update(changes), Isolation: s.Isolation.update(preview.Isolation.values(), true).update(movedEdges), Selection: { bounds: preview.Bounds, cells, isolationEdges: movedEdges.map(edgeKey) }, ...EmptyPreview, Revision: s.Revision + 1 }); get().commit(); return true;
    },
    copy: (cut = false) => {
        const s = get(); if (s.Simulating) return false; const item = selectionItem(s); if (!item) return false;
        set({ Clipboard: [item, ...s.Clipboard].slice(0, 4), ClipboardIndex: 0, ClipboardOrigin: 'copy' });
        if (s.LeftDock !== 'clipboard' && s.RightDock !== 'clipboard') s.activateDock('left', 'clipboard');
        if (cut) get().deleteSelection(); return true;
    },
    paste: anchor => {
        const s = get(), item = s.Clipboard[s.ClipboardIndex]; if (!item || s.Simulating) return;
        const source = inkSource(item), isolation = isolationSource(item);
        set({ Preview: { Source: source, Isolation: isolation, Offset: anchor, Kind: 'paste', Bounds: { originX: anchor.x, originY: anchor.y, width: item.width, height: item.height } },
            PasteAnchor: anchor, PreviewValid: previewValid(s, source, isolation, anchor) });
    },
    confirmPaste: () => {
        const s = get(), preview = s.Preview;
        if (!preview || preview.Kind !== 'paste' || !previewValid(s, preview.Source, preview.Isolation, preview.Offset) || s.Simulating) return false;
        s.begin(); const changes = [...translated(preview.Source, preview.Offset)];
        const edges = translatedEdges(preview.Isolation, preview.Offset);
        set({ Tiles: s.Tiles.update(changes), Isolation: s.Isolation.update(edges), Selection: { bounds: preview.Bounds, cells: changes.map(([key]) => key), isolationEdges: edges.map(edgeKey) }, ...EmptyPreview, Revision: s.Revision + 1 }); get().commit(); return true;
    },
    deleteSelection: () => {
        const s = get(); if (!s.Selection || s.Simulating) return; s.begin();
        set({ Tiles: s.Tiles.update(s.Selection.cells.map(key => [key, undefined])), Isolation: s.Isolation.update(s.Isolation.query(s.Selection.bounds), true), Selection: null, Revision: s.Revision + 1 }); get().commit();
    },
    resize: grid => {
        const s = get(), b = s.Tiles.Bounds;
        if (s.Simulating || grid.width < 4 || grid.height < 4 || ![grid.width, grid.height, grid.originX, grid.originY].every(Number.isInteger)
            || grid.originX < -2147483648 || grid.originY < -2147483648 || grid.originX + grid.width > 2147483647 || grid.originY + grid.height > 2147483647
            || (s.Isolation.Bounds && (s.Isolation.Bounds.originX < grid.originX || s.Isolation.Bounds.originY < grid.originY || s.Isolation.Bounds.originX + s.Isolation.Bounds.width > grid.originX + grid.width || s.Isolation.Bounds.originY + s.Isolation.Bounds.height > grid.originY + grid.height))
            || (b && (!contains(grid, { x: b.originX, y: b.originY }) || !contains(grid, { x: b.originX + b.width - 1, y: b.originY + b.height - 1 })))) return false;
        s.begin(); set({ Board: { ...s.Board, grid }, Revision: s.Revision + 1 }); return true;
    },
    configure: (patch, selection = false) => {
        const s = get(); if (s.Simulating) return;
        for (const field of ['clockHoldTicks'] as const)
            if (patch[field] !== undefined && (!Number.isInteger(patch[field]) || patch[field]! < 1 || patch[field]! > 2147483647)) return;
        if (selection && s.Selection) {
            s.begin();
            set({ Tiles: s.Tiles.update(s.Selection.cells.map(key => [key, { ...s.Tiles.get(key)!, ...patch }])), Revision: s.Revision + 1 }); get().commit();
        }
        else set({ Board: { ...s.Board, ...(patch.clockHoldTicks ? { clockHoldTicks: patch.clockHoldTicks } : {}),
            ...(patch.isOn !== undefined ? { latchInitialState: patch.isOn } : {}), ...(patch.toolId ? { selectedTool: patch.toolId } : {}) } });
    },
    activateDock: (side, id) => { const s = get(), a = side === 'left' ? 'LeftDock' : 'RightDock', b = side === 'left' ? 'RightDock' : 'LeftDock'; set({ [a]: id, ...(s[b] === id ? { [b]: s[a] } : {}) }); },
    log: text => set(s => ({ Events: [...s.Events.slice(-999), `${new Date().toLocaleTimeString()}  ${text}`] })),
    setRuntime: states => set({ Runtime: states }),
}));
