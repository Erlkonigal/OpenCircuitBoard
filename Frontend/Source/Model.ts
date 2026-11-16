import { validateComponents } from './ComponentTopology';
export interface Point {
    x: number;
    y: number;
}
export interface Grid {
    originX: number;
    originY: number;
    width: number;
    height: number;
}
export interface Tile extends Point {
    toolId: string;
    componentId: number;
    isOn: boolean;
    clockHoldTicks?: number;
}
export interface Board {
    selectedTool: string;
    clockHoldTicks: number;
    latchInitialState: boolean;
    grid: Grid;
    tiles: Tile[];
}
export interface Selection { kind: 'components'; ids: number[] }
export type EditorTool = 'pointer' | 'draw' | 'merge' | 'split';
export interface ClipboardItem {
    width: number;
    height: number;
    tiles: Tile[];
}
export interface Blueprint extends ClipboardItem {
    id: string;
    name: string;
}
export interface ProjectDocument {
    board: Board;
    blueprints: Blueprint[];
}
export type RenderMode = '2d' | '2.5d';
export interface Ink {
    id: string;
    title: string;
    category: string;
    color: string;
    icon: string;
    variants?: string[];
}
export const ToolIds = ['empty', 'trace', 'traceRed', 'traceGreen', 'traceBlue', 'traceCyan', 'traceMagenta', 'bus', 'busRed', 'busGreen', 'busYellow', 'busCyan', 'busMagenta', 'cross', 'read', 'write', 'buffer', 'and', 'or', 'xor', 'not', 'nand', 'nor', 'xnor', 'latch', 'clock', 'led'];
// Explicit kinds keep the retired slot 14 unavailable without renumbering other inks.
export const ToolKinds: Record<string, number> = Object.fromEntries(ToolIds.map((id, index) => [id, index < 14 ? index : index + 1]));
export const hasGlyph = (id: string) => paletteId(id) !== 'trace';
const Icons = import.meta.glob('../Assets/Inks/*.svg', { eager: true, query: '?url', import: 'default' }) as Record<string, string>;
// Base surfaces reserve brightness for the shared highlight (weighted RGB <= 160).
const Colors: Record<string, string> = { cross: '#88a2c8', bus: '#2378f4', read: '#f04f68', write: '#4ca8ef', trace: '#b5a527', buffer: '#44bf75', and: '#c29c58', or: '#45b7c1', xor: '#a977ed', not: '#ef5b78', nand: '#e99532', nor: '#3cb9c5', xnor: '#bf58ee', latch: '#37c377', clock: '#f05b70', led: '#9ba0a7' };
const VariantColors: Record<string, string> = { Red: '#ff4d4d', Green: '#58bc54', Blue: '#2378f4', Cyan: '#45b7c1', Magenta: '#c66af6', Yellow: '#b5a527' };
export const paletteId = (id: string) => id.startsWith('trace') ? 'trace' : id.startsWith('bus') ? 'bus' : id;
export function iconUrl(id: string, on = true) { const name = id === 'latch' ? (on ? 'LatchOn' : 'LatchOff') : id[0].toUpperCase() + id.slice(1); return Icons[`../Assets/Inks/${name}.svg`]; }
export const Inks: Ink[] = ['cross', 'bus', 'read', 'write', 'trace', 'buffer', 'and', 'or', 'xor', 'not', 'nand', 'nor', 'xnor', 'latch', 'clock', 'led'].map(id => ({ id, title: id[0].toUpperCase() + id.slice(1), category: ['cross', 'bus'].includes(id) ? 'Space Optimization' : ['read', 'write', 'trace'].includes(id) ? 'Trace' : ['latch', 'clock', 'led'].includes(id) ? 'General Components' : 'Gates', color: Colors[id], icon: iconUrl(id), variants: id === 'trace' ? ToolIds.slice(1, 7) : id === 'bus' ? ToolIds.slice(7, 13) : undefined }));
export function inkColor(id: string) { const suffix = id.slice(paletteId(id).length); return VariantColors[suffix] ?? Colors[id] ?? '#a0a0a0'; }
export const cellKey = (point: Point) => `${point.x},${point.y}`;
export const parseKey = (key: string): Point => { const [x, y] = key.split(',').map(Number); return { x, y }; };
export const contains = (grid: Grid, point: Point) => point.x >= grid.originX && point.y >= grid.originY && point.x < grid.originX + grid.width && point.y < grid.originY + grid.height;
export const newBoard = (): Board => ({ selectedTool: 'or', clockHoldTicks: 1, latchInitialState: true, grid: { originX: -20, originY: -14, width: 40, height: 28 }, tiles: [] });
export function lineCells(start: Point, end: Point) { const result: Point[] = []; let { x, y } = start; const dx = Math.abs(end.x - x), dy = -Math.abs(end.y - y), sx = x < end.x ? 1 : -1, sy = y < end.y ? 1 : -1; let error = dx + dy; while (true) {
    result.push({ x, y });
    if (x === end.x && y === end.y)
        break;
    const twice = error * 2;
    if (twice >= dy) {
        error += dy;
        x += sx;
    }
    if (twice <= dx) {
        error += dx;
        y += sy;
    }
} return result; }
export function validateBoard(value: unknown): Board {
    const board = value as Board;
    if (!board || !Array.isArray(board.tiles)) throw Error('ProjectBoardInvalid');
    const defaults = newBoard(), g = { ...defaults.grid, ...board.grid };
    const result: Board = { selectedTool: board.selectedTool ?? defaults.selectedTool, clockHoldTicks: board.clockHoldTicks ?? 1,
        latchInitialState: board.latchInitialState ?? true, grid: g, tiles: [] };
    if (![g.originX, g.originY, g.width, g.height].every(Number.isInteger) || g.originX < -2147483648 || g.originY < -2147483648
        || g.originX + g.width > 2147483647 || g.originY + g.height > 2147483647 || g.width < 4 || g.height < 4
        || !ToolIds.slice(1).includes(result.selectedTool) || !Number.isInteger(result.clockHoldTicks) || result.clockHoldTicks < 1 || result.clockHoldTicks > 2147483647)
        throw Error('ProjectBoardInvalid');
    const cells = new Set<string>();
    result.tiles = board.tiles.map(tile => {
        if (!tile || !Number.isInteger(tile.x) || !Number.isInteger(tile.y) || cells.has(cellKey(tile)) || !contains(g, tile)
            || !ToolIds.slice(1).includes(tile.toolId)) throw Error('ProjectBoardInvalid');
        cells.add(cellKey(tile));
        const normalized: Tile = { x: tile.x, y: tile.y, toolId: tile.toolId, componentId: tile.componentId, isOn: tile.isOn ?? (tile.toolId === 'latch' ? result.latchInitialState : true) };
        if (tile.toolId === 'clock') {
            normalized.clockHoldTicks = tile.clockHoldTicks ?? result.clockHoldTicks;
            if (!Number.isInteger(normalized.clockHoldTicks) || normalized.clockHoldTicks < 1 || normalized.clockHoldTicks > 2147483647) throw Error('ProjectBoardInvalid');
        }
        return normalized;
    });
    validateComponents(result.tiles, 'ProjectBoardInvalid');
    return result;
}
export function validateProject(value: unknown): ProjectDocument {
    const project = value as ProjectDocument, board = validateBoard(project?.board);
    if (project.blueprints !== undefined && !Array.isArray(project.blueprints)) throw Error('ProjectBlueprintInvalid');
    const ids = new Set<string>();
    const blueprints = (project.blueprints ?? []).map(blueprint => {
        if (!blueprint || typeof blueprint.id !== 'string' || !blueprint.id.trim() || ids.has(blueprint.id)
            || typeof blueprint.name !== 'string' || !blueprint.name.trim()
            || ![blueprint.width, blueprint.height].every(n => Number.isInteger(n) && n > 0 && n <= 2147483647) || !Array.isArray(blueprint.tiles))
            throw Error('ProjectBlueprintInvalid');
        ids.add(blueprint.id);
        if (!blueprint.tiles.length) throw Error('ProjectBlueprintInvalid');
        const cells = new Set<string>();
        const tiles = blueprint.tiles.map(tile => {
            if (!tile || !Number.isInteger(tile.x) || !Number.isInteger(tile.y) || tile.x < 0 || tile.y < 0
                || tile.x >= blueprint.width || tile.y >= blueprint.height || cells.has(cellKey(tile))
                || !ToolIds.slice(1).includes(tile.toolId) || typeof tile.isOn !== 'boolean'
                || (tile.toolId === 'clock' && (!Number.isInteger(tile.clockHoldTicks) || tile.clockHoldTicks! < 1 || tile.clockHoldTicks! > 2147483647)))
                throw Error('ProjectBlueprintInvalid');
            cells.add(cellKey(tile));
            return { x: tile.x, y: tile.y, toolId: tile.toolId, componentId: tile.componentId, isOn: tile.isOn, ...(tile.toolId === 'clock' ? { clockHoldTicks: tile.clockHoldTicks } : {}) };
        });
        validateComponents(tiles, 'ProjectBlueprintInvalid');
        return { id: blueprint.id, name: blueprint.name.trim(), width: blueprint.width, height: blueprint.height, tiles };
    });
    return { board, blueprints };
}
