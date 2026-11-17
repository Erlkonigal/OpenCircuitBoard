import { browser, $, expect } from '@wdio/globals';
import path from 'node:path';
import { buildPath, WorkspaceRoot } from '../Paths';

// Runs against the real Tauri binary and its simulation worker.
describe('Boolean Switch memory', () => {
    it('resolves a fixed zero through a delayed bidirectional switch without X or Z', async () => {
        const result = await browser.execute(async () => {
            const invoke = (window as unknown as { __TAURI_INTERNALS__: { invoke: (command: string, args: unknown) => Promise<ArrayBuffer> } }).__TAURI_INTERNALS__.invoke;
            const width = 3, height = 3, count = width * height;
            const bytes = new Uint8Array(24 + count * 32), data = new DataView(bytes.buffer);
            [0x4f434249, 4, width, height, -1, 0].forEach((v, i) => data.setInt32(i * 4, v, true));
            const arrays = Array.from({ length: 8 }, (_, i) => new Int32Array(bytes.buffer, 24 + count * i * 4, count));
            arrays[2].fill(1); arrays[5].fill(-1);
            // left fixed 0, center Switch, right default 1, bottom control Trace and up-facing Latch.
            for (const [cell, kind, id] of [[0, 1, 1], [1, 30, 2], [2, 2, 3], [4, 4, 4], [7, 25, 5]]) {
                arrays[0][cell] = kind; arrays[3][cell] = id;
            }
            arrays[5][0] = 0; arrays[6][2] = 1; arrays[4][7] = 3;
            let frame = await invoke('compileGrid', bytes);
            const session = new DataView(frame).getUint32(8, true);
            const read = (buffer: ArrayBuffer) => {
                if ([...new Uint8Array(buffer, 80)].some(v => v > 1)) throw Error('Non-boolean runtime signal');
                return new Uint8Array(buffer, 80)[2];
            };
            const values = [read(frame)];
            for (const [action, value] of [['toggle', 7], ['step', 1], ['toggle', 7], ['step', 1], ['seek', 0], ['step', 1], ['reset', 0]] as const) {
                frame = await invoke('simulationCommand', { action, session, value }); values.push(read(frame));
            }
            const channels = JSON.parse(new TextDecoder().decode(await invoke('inspectCell', { session, cell: 2 })));
            await invoke('simulationCommand', { action: 'release', session, value: 0 });
            return { values, channels };
        });
        expect(result.values).toEqual([1, 1, 0, 0, 1, 1, 0, 1]);
        expect(result.channels).toEqual([1]);
    });

    it('keeps Latch output independent of adjacent clock signals and preserves manual toggles', async () => {
        const values = await browser.execute(async () => {
            const invoke = (window as unknown as { __TAURI_INTERNALS__: { invoke: (command: string, args: unknown) => Promise<ArrayBuffer> } }).__TAURI_INTERNALS__.invoke;
            const count = 4, bytes = new Uint8Array(24 + count * 32), data = new DataView(bytes.buffer);
            [0x4f434249, 4, 4, 1, 0, 0].forEach((v, i) => data.setInt32(i * 4, v, true));
            const arrays = Array.from({ length: 8 }, (_, i) => new Int32Array(bytes.buffer, 24 + count * i * 4, count));
            arrays[0].set([26, 1, 25, 2]); arrays[2].fill(1); arrays[3].set([1, 2, 3, 4]); arrays[5].fill(-1);
            let frame = await invoke('compileGrid', bytes);
            const session = new DataView(frame).getUint32(8, true), values = [new Uint8Array(frame, 80)[3]];
            for (const [action, value] of [['step', 2], ['toggle', 2], ['step', 7], ['reset', 0]] as const) {
                frame = await invoke('simulationCommand', { action, session, value });
                values.push(new Uint8Array(frame, 80)[3]);
            }
            await invoke('simulationCommand', { action: 'release', session, value: 0 });
            return values;
        });
        expect(values).toEqual([0, 0, 1, 1, 0]);
    });

    it('writes, reads, resets and restores the committed RAM through the shared eight bit lines', async () => {
        const file = path.join(WorkspaceRoot, 'Frontend/Assets/Examples/Ram16x8.ocb');
        const result = await browser.execute(async (file: string) => {
            type Tile = { x: number; y: number; toolId: string; componentId: number; isOn: boolean; direction?: number; clockHoldTicks?: number; fixedDrive?: boolean; defaultValue?: boolean; crossMask?: number };
            const invoke = (window as unknown as { __TAURI_INTERNALS__: { invoke: <T>(command: string, args: unknown) => Promise<T> } }).__TAURI_INTERNALS__.invoke;
            const project = await invoke<{ board: { tiles: Tile[]; clockHoldTicks: number } }>('openProject', { path: file });
            const tiles = project.board.tiles;
            let minX = tiles[0].x, minY = tiles[0].y, maxX = minX, maxY = minY;
            for (const tile of tiles) {
                minX = Math.min(minX, tile.x); minY = Math.min(minY, tile.y);
                maxX = Math.max(maxX, tile.x); maxY = Math.max(maxY, tile.y);
            }
            const width = maxX - minX + 1, height = maxY - minY + 1, count = width * height;
            const bytes = new Uint8Array(24 + count * 32), data = new DataView(bytes.buffer);
            [0x4f434249, 4, width, height, minX, minY].forEach((v, i) => data.setInt32(i * 4, v, true));
            const arrays = Array.from({ length: 8 }, (_, i) => new Int32Array(bytes.buffer, 24 + count * i * 4, count));
            arrays[2].fill(1); arrays[5].fill(-1);
            const kinds: Record<string, number> = { trace: 1, traceRed: 2, traceGreen: 3, traceBlue: 4, traceCyan: 5, traceMagenta: 6, bus: 7, cross: 13, buffer: 17, and: 18, or: 19, xor: 20, not: 21, nand: 22, nor: 23, xnor: 24, latch: 25, clock: 26, led: 27, traceOrange: 28, traceWhite: 29, switch: 30 };
            const cell = (t: Tile) => (t.y - minY) * width + t.x - minX;
            const controls = new Map<number, number>();
            for (const t of tiles) {
                const c = cell(t);
                [kinds[t.toolId], Number(t.isOn), t.clockHoldTicks ?? 1, t.componentId, t.direction ?? 0, t.fixedDrive === undefined ? -1 : Number(t.fixedDrive), Number(t.defaultValue ?? false), t.crossMask ?? 0].forEach((v, i) => { arrays[i][c] = v; });
                if (t.toolId === 'latch' || t.toolId === 'led') controls.set(t.componentId - 1, c);
            }
            let frame = await invoke<ArrayBuffer>('compileGrid', bytes);
            const session = new DataView(frame).getUint32(8, true);
            const command = async (action: string, value: number) => { frame = await invoke<ArrayBuffer>('simulationCommand', { action, session, value }); };
            const settle = () => command('step', 8);
            const set = async (signal: number, on: boolean) => {
                const c = controls.get(signal)!;
                if (new Uint8Array(frame, 80)[c] !== Number(on)) await command('toggle', c);
            };
            const address = async (value: number) => { for (let bit = 0; bit < 4; bit++) await set(8 + bit, !!(value & (1 << bit))); };
            const input = async (value: number) => { for (let bit = 0; bit < 8; bit++) await set(16 + bit, !!(value & (1 << bit))); };
            const read = () => Array.from({ length: 8 }, (_, bit) => new Uint8Array(frame, 80)[controls.get(60_000 + bit)!] << bit).reduce((a, b) => a | b, 0);
            await settle(); await set(14, false); await settle();
            const patterns = [[0, 0xa5], [7, 0x3c], [15, 0x81]];
            for (const [a, value] of patterns) {
                await address(a); await input(value); await set(15, true); await settle();
                await set(13, true); await settle(); await set(13, false); await settle();
                await set(15, false); await settle();
            }
            const reads: number[] = [];
            for (const [a] of patterns) {
                await address(a); await settle(); await set(12, true); await settle(); reads.push(read());
                await set(12, false); await settle();
            }
            const snapshotTick = new DataView(frame).getUint32(16, true);
            // Toggle edits replace the current tick; move forward to preserve this checkpoint.
            await command('step', 1);
            await set(14, true); await settle(); await set(14, false); await settle();
            await set(12, true); await settle(); const cleared = read();
            await command('seek', snapshotTick); await set(12, true); await settle(); const restored = read();
            const boolean = [...new Uint8Array(frame, 80)].every(v => v <= 1);
            await invoke('simulationCommand', { action: 'release', session, value: 0 });
            return { reads, cleared, restored, boolean };
        }, file);
        expect(result).toEqual({ reads: [0xa5, 0x3c, 0x81], cleared: 0, restored: 0x81, boolean: true });
        await browser.refresh();
        await browser.waitUntil(async () => await $('[data-testid="board"]').getAttribute('data-render-ready') === 'true');
        await $('.project-switcher').click(); await $('button=Ram16x8.ocb').click();
        await expect($('.project-switcher')).toHaveText(expect.stringContaining('Ram16x8.ocb'));
        await expect($('.workspace-status')).toHaveText(expect.stringContaining('98,916 cells'));
        await $('button[aria-label="Fit board in view"]').click();
        await browser.waitUntil(async () => await $('[data-testid="board"]').getAttribute('data-color-ready') === 'true');
        await $('button=Run circuit').click(); await $('button[aria-label="Pause simulation"]').click();
        await expect($('.workspace-status')).toHaveText(expect.stringContaining('98,916 cells'));
        await browser.waitUntil(async () => Number(await $('[data-testid="board"]').getAttribute('data-render-objects')) > 0 &&
            await $('[data-testid="board"]').getAttribute('data-color-ready') === 'true');
        await browser.saveScreenshot(buildPath('DesktopRamSharedBusCapture.png'));
        await $('button=Back to design').click();
        await expect($('.error-toast')).not.toExist();
    });
});
