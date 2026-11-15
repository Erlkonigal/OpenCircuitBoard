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
    isOn: boolean;
    clockHoldTicks?: number;
    meshId?: number;
}
export interface Board {
    selectedTool: string;
    clockHoldTicks: number;
    meshId: number;
    latchInitialState: boolean;
    grid: Grid;
    tiles: Tile[];
}
export interface Selection {
    bounds: Grid;
    cells: string[];
}
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
export const ToolIds = ['empty', 'trace', 'traceRed', 'traceGreen', 'traceBlue', 'traceCyan', 'traceMagenta', 'bus', 'busRed', 'busGreen', 'busYellow', 'busCyan', 'busMagenta', 'cross', 'mesh', 'read', 'write', 'buffer', 'and', 'or', 'xor', 'not', 'nand', 'nor', 'xnor', 'latch', 'clock', 'led'];
const Icons = import.meta.glob('../Assets/Inks/*.svg', { eager: true, query: '?url', import: 'default' }) as Record<string, string>;
const colors: Record<string, string> = { cross: '#8da8cf', mesh: '#91a66c', bus: '#2378f4', read: '#f04f68', write: '#4ca8ef', trace: '#f4df35', buffer: '#55ed91', and: '#f3c46e', or: '#55dfeb', xor: '#a977ed', not: '#ef5b78', nand: '#f59d35', nor: '#46d8e5', xnor: '#bf58ee', latch: '#43ec90', clock: '#f05b70', led: '#e6edf8' };
export const paletteId = (id: string) => id.startsWith('trace') ? 'trace' : id.startsWith('bus') ? 'bus' : id;
export function iconUrl(id: string, on = true) { const name = id === 'latch' ? (on ? 'LatchOn' : 'LatchOff') : id[0].toUpperCase() + id.slice(1); return Icons[`../Assets/Inks/${name}.svg`]; }
export const Inks: Ink[] = ['cross', 'mesh', 'bus', 'read', 'write', 'trace', 'buffer', 'and', 'or', 'xor', 'not', 'nand', 'nor', 'xnor', 'latch', 'clock', 'led'].map(id => ({ id, title: id[0].toUpperCase() + id.slice(1), category: ['cross', 'mesh', 'bus'].includes(id) ? 'Space Optimization' : ['read', 'write', 'trace'].includes(id) ? 'Trace' : ['latch', 'clock', 'led'].includes(id) ? 'General Components' : 'Gates', color: colors[id], icon: iconUrl(id), variants: id === 'trace' ? ToolIds.slice(1, 7) : id === 'bus' ? ToolIds.slice(7, 13) : undefined }));
export function inkColor(id: string) { const suffix = id.slice(paletteId(id).length); return ({ Red: '#ff4d4d', Green: '#71f06b', Blue: '#2378f4', Cyan: '#55dfeb', Magenta: '#c66af6', Yellow: '#f4df35' } as Record<string, string>)[suffix] ?? colors[id] ?? '#ffffff'; }
export const cellKey = (point: Point) => `${point.x},${point.y}`;
export const parseKey = (key: string): Point => { const [x, y] = key.split(',').map(Number); return { x, y }; };
export const contains = (grid: Grid, point: Point) => point.x >= grid.originX && point.y >= grid.originY && point.x < grid.originX + grid.width && point.y < grid.originY + grid.height;
export const newBoard = (): Board => ({ selectedTool: 'or', clockHoldTicks: 1, meshId: 1, latchInitialState: true, grid: { originX: -20, originY: -14, width: 40, height: 28 }, tiles: [] });
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
    if (!board || !Array.isArray(board.tiles))
        throw Error('ProjectBoardInvalid');
    const result = { ...newBoard(), ...board, grid: { ...newBoard().grid, ...board.grid } };
    const g = result.grid;
    if (![g.originX, g.originY, g.width, g.height].every(Number.isInteger) || g.originX < -2147483648 || g.originY < -2147483648 || g.originX + g.width > 2147483647 || g.originY + g.height > 2147483647 || g.width < 4 || g.height < 4 || !ToolIds.slice(1).includes(result.selectedTool) || ![result.clockHoldTicks, result.meshId].every(n => Number.isInteger(n) && n > 0 && n <= 2147483647))
        throw Error('ProjectBoardInvalid');
    const cells = new Set<string>();
    result.tiles = result.tiles.map(tile => { const key = cellKey(tile); if (cells.has(key) || !Number.isInteger(tile.x) || !Number.isInteger(tile.y) || !contains(g, tile) || !ToolIds.slice(1).includes(tile.toolId))
        throw Error('ProjectBoardInvalid'); cells.add(key); const value = { ...tile, isOn: tile.isOn ?? (tile.toolId === 'latch' ? result.latchInitialState : tile.toolId !== 'mesh') }; for (const field of ['clockHoldTicks', 'meshId'] as const) {
        if ((tile.toolId === 'clock' && field === 'clockHoldTicks') || (tile.toolId === 'mesh' && field === 'meshId')) {
            value[field] ??= result[field];
            if (!Number.isInteger(value[field]) || value[field]! < 1 || value[field]! > 2147483647)
                throw Error('ProjectBoardInvalid');
        }
    } return value; });
    return result;
}

export function validateProject(value: unknown): ProjectDocument {
    const project = value as ProjectDocument;
    const board = validateBoard(project?.board);
    if (project.blueprints !== undefined && !Array.isArray(project.blueprints))
        throw Error('ProjectBlueprintInvalid');
    const ids = new Set<string>();
    const blueprints = (project.blueprints ?? []).map(blueprint => {
        if (!blueprint || typeof blueprint.id !== 'string' || !blueprint.id.trim() || ids.has(blueprint.id)
            || typeof blueprint.name !== 'string' || !blueprint.name.trim()
            || ![blueprint.width, blueprint.height].every(n => Number.isInteger(n) && n > 0 && n <= 2147483647)
            || !Array.isArray(blueprint.tiles) || !blueprint.tiles.length)
            throw Error('ProjectBlueprintInvalid');
        ids.add(blueprint.id);
        const cells = new Set<string>();
        const tiles = blueprint.tiles.map(tile => {
            if (!tile || !Number.isInteger(tile.x) || !Number.isInteger(tile.y) || tile.x < 0 || tile.y < 0
                || tile.x >= blueprint.width || tile.y >= blueprint.height || cells.has(cellKey(tile))
                || !ToolIds.slice(1).includes(tile.toolId) || typeof tile.isOn !== 'boolean'
                || (tile.toolId === 'clock' && (!Number.isInteger(tile.clockHoldTicks) || tile.clockHoldTicks! < 1 || tile.clockHoldTicks! > 2147483647))
                || (tile.toolId === 'mesh' && (!Number.isInteger(tile.meshId) || tile.meshId! < 1 || tile.meshId! > 2147483647)))
                throw Error('ProjectBlueprintInvalid');
            cells.add(cellKey(tile));
            return { ...tile };
        });
        return { id: blueprint.id, name: blueprint.name.trim(), width: blueprint.width, height: blueprint.height, tiles };
    });
    return { board, blueprints };
}
