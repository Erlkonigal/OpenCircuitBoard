import { create } from 'zustand';
import { cellKey, contains, newBoard, parseKey, validateBoard, type Board, type ClipboardItem, type Grid, type Point, type Selection, type Tile } from './Model';
interface Document {
    tiles: Map<string, Tile>;
    grid: Grid;
    selection: Selection | null;
}
interface Change {
    key: string;
    before?: Tile;
    after?: Tile;
}
interface Command {
    changes: Change[];
    beforeGrid: Grid;
    afterGrid: Grid;
    beforeSelection: Selection | null;
    afterSelection: Selection | null;
}
export interface RuntimeGrid {
    width: number;
    height: number;
    originX: number;
    originY: number;
    states: Uint8Array;
}
interface State {
    Board: Board;
    Tiles: Map<string, Tile>;
    Selection: Selection | null;
    Clipboard: ClipboardItem[];
    ClipboardIndex: number;
    Undo: Command[];
    Redo: Command[];
    Active: Document | null;
    Preview: Tile[];
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
    load: (board: Board, path?: string) => void;
    export: () => Board;
    selectTool: (id: string) => void;
    begin: () => void;
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
const snapshot = (s: State): Document => ({ tiles: new Map(s.Tiles), grid: { ...s.Board.grid }, selection: s.Selection });
const tileEqual = (a?: Tile, b?: Tile) => JSON.stringify(a) === JSON.stringify(b);
const EmptyPreview = { Preview: [] as Tile[], PreviewValid: false, PasteAnchor: null };
export const useEditor = create<State>((set, get) => ({
    Board: newBoard(), Tiles: new Map(), Selection: null, Clipboard: [], ClipboardIndex: -1, Undo: [], Redo: [], Active: null, ...EmptyPreview,
    LeftDock: 'circuitEditor', RightDock: 'eventLog', LeftOpen: true, RightOpen: true, LeftWidth: 272, RightWidth: 272,
    Events: [], Path: '', Recent: [], Revision: 0, Simulating: false, Runtime: new Map(), RuntimeGrid: null,
    load: (data, path = '') => { const board = validateBoard(data); set({ Board: board, Tiles: new Map(board.tiles.map(t => [cellKey(t), t])), Selection: null, Clipboard: [], ClipboardIndex: -1, Undo: [], Redo: [], Active: null, ...EmptyPreview, Path: path, Runtime: new Map(), RuntimeGrid: null, Revision: get().Revision + 1 }); },
    export: () => { const s = get(); return { ...s.Board, grid: { ...s.Board.grid }, tiles: [...s.Tiles.values()].sort((a, b) => a.y - b.y || a.x - b.x) }; },
    selectTool: id => set(s => ({ Board: { ...s.Board, selectedTool: id } })),
    begin: () => { if (!get().Simulating && !get().Active)
        set({ Active: snapshot(get()) }); },
    paint: (points, remove = false) => { const s = get(); if (s.Simulating)
        return; if (!s.Active)
        s.begin(); const tiles = new Map(get().Tiles); for (const point of points) {
        if (!contains(s.Board.grid, point))
            continue;
        const key = cellKey(point);
        if (remove)
            tiles.delete(key);
        else if (!tiles.has(key)) {
            const id = s.Board.selectedTool;
            tiles.set(key, { ...point, toolId: id, isOn: id === 'mesh' ? false : id === 'latch' ? s.Board.latchInitialState : true, ...(id === 'clock' ? { clockHoldTicks: s.Board.clockHoldTicks } : {}), ...(id === 'mesh' ? { meshId: s.Board.meshId } : {}) });
        }
    } set({ Tiles: tiles, Revision: get().Revision + 1 }); },
    commit: () => { const s = get(), before = s.Active; if (!before)
        return; const changes: Change[] = []; for (const key of new Set([...before.tiles.keys(), ...s.Tiles.keys()]))
        if (!tileEqual(before.tiles.get(key), s.Tiles.get(key)))
            changes.push({ key, before: before.tiles.get(key), after: s.Tiles.get(key) }); const command = { changes, beforeGrid: before.grid, afterGrid: s.Board.grid, beforeSelection: before.selection, afterSelection: s.Selection }; set({ Active: null, ...((changes.length || JSON.stringify(before.grid) !== JSON.stringify(s.Board.grid)) ? { Undo: [...s.Undo, command], Redo: [] } : {}) }); },
    cancel: () => { const s = get(); set({ ...EmptyPreview, Active: null, ...(s.Active ? { Tiles: s.Active.tiles, Board: { ...s.Board, grid: s.Active.grid }, Selection: s.Active.selection, Revision: s.Revision + 1 } : {}) }); },
    undo: () => { get().cancel(); const s = get(), command = s.Undo.at(-1); if (!command || s.Simulating)
        return; const tiles = new Map(s.Tiles); for (const c of command.changes)
        if (c.before)
            tiles.set(c.key, c.before);
        else
            tiles.delete(c.key); set({ Tiles: tiles, Board: { ...s.Board, grid: command.beforeGrid }, Selection: command.beforeSelection, Undo: s.Undo.slice(0, -1), Redo: [...s.Redo, command], Revision: s.Revision + 1 }); },
    redo: () => { get().cancel(); const s = get(), command = s.Redo.at(-1); if (!command || s.Simulating)
        return; const tiles = new Map(s.Tiles); for (const c of command.changes)
        if (c.after)
            tiles.set(c.key, c.after);
        else
            tiles.delete(c.key); set({ Tiles: tiles, Board: { ...s.Board, grid: command.afterGrid }, Selection: command.afterSelection, Redo: s.Redo.slice(0, -1), Undo: [...s.Undo, command], Revision: s.Revision + 1 }); },
    select: bounds => { const s = get(); const cells = bounds ? [...s.Tiles.keys()].filter(key => contains(bounds, parseKey(key))) : []; set({ Selection: bounds && cells.length ? { bounds, cells } : null }); },
    movePreview: offset => { const s = get(); if (!s.Selection)
        return; const selected = new Set(s.Selection.cells); const preview = s.Selection.cells.map(key => s.Tiles.get(key)!).filter(Boolean).map(t => ({ ...t, x: t.x + offset.x, y: t.y + offset.y })); set({ Preview: preview, PreviewValid: preview.length > 0 && preview.every(t => contains(s.Board.grid, t) && (!s.Tiles.has(cellKey(t)) || selected.has(cellKey(t)))) }); },
    confirmMove: offset => { const s = get(); s.movePreview(offset); const next = get(); if (!next.Selection || !next.PreviewValid) {
        set(EmptyPreview);
        return false;
    } s.begin(); const tiles = new Map(s.Tiles); for (const key of next.Selection.cells)
        tiles.delete(key); for (const t of next.Preview)
        tiles.set(cellKey(t), t); const b = next.Selection.bounds; set({ Tiles: tiles, Selection: { bounds: { ...b, originX: b.originX + offset.x, originY: b.originY + offset.y }, cells: next.Preview.map(cellKey) }, ...EmptyPreview, Revision: s.Revision + 1 }); get().commit(); return true; },
    copy: (cut = false) => { const s = get(); if (!s.Selection || s.Simulating)
        return false; const b = s.Selection.bounds; const item = { width: b.width, height: b.height, tiles: s.Selection.cells.map(key => s.Tiles.get(key)!).filter(Boolean).map(t => ({ ...t, x: t.x - b.originX, y: t.y - b.originY })) }; set({ Clipboard: [item, ...s.Clipboard].slice(0, 4), ClipboardIndex: 0 }); if (s.LeftDock !== 'clipboard' && s.RightDock !== 'clipboard')
        s.activateDock('left', 'clipboard'); if (cut)
        get().deleteSelection(); return true; },
    paste: anchor => { const s = get(), item = s.Clipboard[s.ClipboardIndex]; if (!item || s.Simulating)
        return; const preview = item.tiles.map(t => ({ ...t, x: anchor.x + t.x, y: anchor.y + t.y })); set({ Preview: preview, PasteAnchor: anchor, PreviewValid: preview.length > 0 && preview.every(t => contains(s.Board.grid, t) && !s.Tiles.has(cellKey(t))) }); },
    confirmPaste: () => { const s = get(), item = s.Clipboard[s.ClipboardIndex]; if (!s.PreviewValid || !s.PasteAnchor || !item)
        return false; s.begin(); const tiles = new Map(s.Tiles); for (const t of s.Preview)
        tiles.set(cellKey(t), t); set({ Tiles: tiles, Selection: { bounds: { originX: s.PasteAnchor.x, originY: s.PasteAnchor.y, width: item.width, height: item.height }, cells: s.Preview.map(cellKey) }, ...EmptyPreview, Revision: s.Revision + 1 }); get().commit(); return true; },
    deleteSelection: () => { const s = get(); if (!s.Selection || s.Simulating)
        return; s.begin(); const tiles = new Map(s.Tiles); for (const key of s.Selection.cells)
        tiles.delete(key); set({ Tiles: tiles, Selection: null, Revision: s.Revision + 1 }); get().commit(); },
    resize: grid => { const s = get(); if (s.Simulating || grid.width < 4 || grid.height < 4 || ![grid.width, grid.height, grid.originX, grid.originY].every(Number.isInteger) || [...s.Tiles.values()].some(t => !contains(grid, t)))
        return false; if (!s.Active)
        s.begin(); set({ Board: { ...s.Board, grid }, Revision: s.Revision + 1 }); return true; },
    configure: (patch, selection = false) => { const s = get(); for (const field of ['clockHoldTicks', 'meshId'] as const)
        if (patch[field] !== undefined && (!Number.isInteger(patch[field]) || patch[field]! < 1 || patch[field]! > 2147483647))
            return; if (selection && s.Selection) {
        s.begin();
        const tiles = new Map(s.Tiles);
        for (const key of s.Selection.cells) {
            const t = tiles.get(key)!;
            tiles.set(key, { ...t, ...patch });
        }
        set({ Tiles: tiles, Revision: s.Revision + 1 });
        get().commit();
    }
    else
        set({ Board: { ...s.Board, ...(patch.clockHoldTicks ? { clockHoldTicks: patch.clockHoldTicks } : {}), ...(patch.meshId ? { meshId: patch.meshId } : {}), ...(patch.isOn !== undefined ? { latchInitialState: patch.isOn } : {}), ...(patch.toolId ? { selectedTool: patch.toolId } : {}) } }); },
    activateDock: (side, id) => { const s = get(); const a = side === 'left' ? 'LeftDock' : 'RightDock', b = side === 'left' ? 'RightDock' : 'LeftDock'; set({ [a]: id, ...(s[b] === id ? { [b]: s[a] } : {}) }); },
    log: text => set(s => ({ Events: [...s.Events.slice(-999), `${new Date().toLocaleTimeString()}  ${text}`] })),
    setRuntime: states => set({ Runtime: states }),
}));
