import { invoke } from '@tauri-apps/api/core';
import { open, save } from '@tauri-apps/plugin-dialog';
import { useEditor } from './EditorStore';
import { ToolKinds, validateBoard, type Board, type ProjectDocument } from './Model';
export const isDesktop = () => !!(window as Window & {
    __TAURI_INTERNALS__?: unknown;
}).__TAURI_INTERNALS__;
export interface Frame {
    session: number;
    sequence: number;
    tick: number;
    width: number;
    height: number;
    originX: number;
    originY: number;
    full: boolean;
    running: boolean;
    tps: number;
    capacity: number;
    first: number;
    last: number;
    data: Uint8Array | Int32Array;
}
export function decodeFrame(buffer: ArrayBuffer): Frame {
    const d = new DataView(buffer), header = 80;
    if (buffer.byteLength < header || d.getUint32(0, true) !== 0x4f434246 || d.getUint32(4, true) !== 2)
        throw Error('SimulationFrameInvalid');
    const full = d.getUint32(40, true) !== 0, width = d.getUint32(24, true), height = d.getUint32(28, true), count = width * height, payload = buffer.byteLength - header;
    const integer64 = (offset: number) => d.getUint32(offset, true) + d.getUint32(offset + 4, true) * 4294967296;
    if (!width || !height || count > 1048576 || (full && payload !== count) || (!full && payload % 8 !== 0) || ![integer64(16), integer64(56), integer64(64)].every(Number.isSafeInteger))
        throw Error('SimulationFrameInvalid');
    const data = full ? new Uint8Array(buffer, header) : new Int32Array(buffer, header);
    if (full) {
        if (data.some(value => value > 1))
            throw Error('SimulationFrameInvalid');
    }
    else {
        for (let i = 0; i < data.length; i += 2)
            if (data[i] < 0 || data[i] >= count || (data[i + 1] !== 0 && data[i + 1] !== 1))
                throw Error('SimulationFrameInvalid');
    }
    return { session: d.getUint32(8, true), sequence: d.getUint32(12, true), tick: integer64(16), width, height, originX: d.getInt32(32, true), originY: d.getInt32(36, true), full, running: d.getUint32(44, true) !== 0, tps: d.getFloat64(48, true), capacity: d.getFloat64(72, true), first: integer64(56), last: integer64(64), data };
}
export function encodeBoard(board: Board) { board = validateBoard(board); const tiles = board.tiles; let minX = tiles[0]?.x ?? board.grid.originX, minY = tiles[0]?.y ?? board.grid.originY, maxX = minX, maxY = minY; for (const tile of tiles) {
    minX = Math.min(minX, tile.x);
    minY = Math.min(minY, tile.y);
    maxX = Math.max(maxX, tile.x);
    maxY = Math.max(maxY, tile.y);
} const width = maxX - minX + 1, height = maxY - minY + 1, count = width * height; if (count > 1048576)
    throw Error('SimulationGridTooLarge'); const bytes = new Uint8Array(24 + count * 16), data = new DataView(bytes.buffer); [0x4f434249, 2, width, height, minX, minY].forEach((v, i) => data.setInt32(i * 4, v, true)); for (let i = 0; i < count; i++) {
    data.setInt32(24 + (count * 2 + i) * 4, 1, true);
} for (const t of tiles) {
    const cell = (t.y - minY) * width + t.x - minX;
    [ToolKinds[t.toolId], Number(t.isOn), t.clockHoldTicks ?? board.clockHoldTicks].forEach((v, i) => data.setInt32(24 + (count * i + cell) * 4, v, true));
}
for (const edge of board.isolationEdges ?? []) {
    const x = edge.x - minX - Number(edge.axis === 'vertical'), y = edge.y - minY - Number(edge.axis === 'horizontal');
    const bit = edge.axis === 'vertical' ? 1 : 2;
    if (x >= 0 && y >= 0 && x < width && y < height && ((bit === 1 && x + 1 < width) || (bit === 2 && y + 1 < height))) {
        const offset = 24 + (count * 3 + y * width + x) * 4;
        data.setInt32(offset, data.getInt32(offset, true) | bit, true);
    }
}
return bytes; }
export async function compile(board: Board) { if (!isDesktop())
    throw Error('Simulation requires the Tauri desktop app. Start it with make run.'); return decodeFrame(await invoke<ArrayBuffer>('compileGrid', encodeBoard(board))); }
export async function simulation(action: string, session: number, value = 0) { const bytes = await invoke<ArrayBuffer>('simulationCommand', { action, session, value }); return action === 'release' ? null : decodeFrame(bytes); }
let runtimeGeneration = 0;
export function applyFrame(frame: Frame) {
    if (frame.full) {
        const chunksWide = Math.floor((frame.originX + frame.width - 1) / 64) - Math.floor(frame.originX / 64) + 1;
        const chunksHigh = Math.floor((frame.originY + frame.height - 1) / 64) - Math.floor(frame.originY / 64) + 1;
        useEditor.setState({ RuntimeGrid: { width: frame.width, height: frame.height, originX: frame.originX, originY: frame.originY, states: frame.data as Uint8Array, dirtyChunks: null, chunkVersions: new Uint32Array(chunksWide * chunksHigh).fill(1), generation: ++runtimeGeneration } });
        return;
    }
    const grid = useEditor.getState().RuntimeGrid;
    if (!grid || grid.width !== frame.width || grid.height !== frame.height || grid.originX !== frame.originX || grid.originY !== frame.originY)
        throw Error('SimulationFrameInvalid');
    const dirty = new Map<string, { x: number; y: number }>();
    for (let i = 0; i < frame.data.length; i += 2) {
        const index = frame.data[i];
        grid.states[index] = frame.data[i + 1];
        const x = Math.floor((grid.originX + index % grid.width) / 64), y = Math.floor((grid.originY + Math.floor(index / grid.width)) / 64);
        dirty.set(`${x},${y}`, { x, y });
    }
    const versions = grid.chunkVersions?.slice();
    const cx = Math.floor(grid.originX / 64), cy = Math.floor(grid.originY / 64), wide = Math.floor((grid.originX + grid.width - 1) / 64) - cx + 1;
    if (versions) for (const point of dirty.values()) versions[(point.y - cy) * wide + point.x - cx]++;
    useEditor.setState({ RuntimeGrid: { ...grid, dirtyChunks: [...dirty.values()], chunkVersions: versions } });
}
export async function chooseOpen(path?: string) { if (!isDesktop())
    throw Error('Open projects in the Tauri desktop app.'); path ??= (await open({ multiple: false, filters: [{ name: 'OpenCircuitBoard', extensions: ['ocb'] }] })) ?? undefined; if (!path)
    return; const board = await invoke<ProjectDocument>('openProject', { path }); useEditor.getState().load(board, path); useEditor.getState().log(`Opened ${path}`); await refreshRecent(); }
export async function chooseSave(as = false) { if (!isDesktop())
    throw Error('Save projects in the Tauri desktop app.'); const s = useEditor.getState(); const path = as || !s.Path ? await save({ defaultPath: s.Path || 'Untitled.ocb', filters: [{ name: 'OpenCircuitBoard', extensions: ['ocb'] }] }) : s.Path; if (!path)
    return; const saved = await invoke<string>('saveProject', { path, project: s.exportProject() }); useEditor.setState({ Path: saved }); s.log(`Saved ${saved}`); await refreshRecent(); }
export async function refreshRecent() { if (isDesktop())
    useEditor.setState({ Recent: await invoke<string[]>('recentProjects') }); }
