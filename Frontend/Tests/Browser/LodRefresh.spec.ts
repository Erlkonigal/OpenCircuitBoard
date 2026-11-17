import { test, expect } from '../BrowserTest';
import { writeFile } from 'node:fs/promises';
import { buildPath } from '../Paths';

for (const mode of ['2D', '2.5D']) for (const lod of ['detail', 'color', 'aggregate']) test(`${mode} ${lod} runtime colors keep up with repeated changes across a dense board`, async ({ page }) => {
    await page.addInitScript(() => {
        const width = 512, height = 256;
        const fixture = { pendingState: 0, reportedState: 0, sequence: 0, tick: 0, running: false };
        (window as unknown as { LodFixture: typeof fixture }).LodFixture = fixture;
        const changed = new Set<number>();
        for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++) changed.add((y + 128) * width + x + 256);
        for (let y = -128; y < 128; y += 64) for (let x = -256; x < 256; x += 64) changed.add((y + 128) * width + x + 256);
        const encode = (full: boolean) => {
            const delta = fixture.pendingState !== fixture.reportedState;
            const bytes = new ArrayBuffer(80 + (full ? width * height : delta ? changed.size * 8 : 0)), data = new DataView(bytes);
            for (const [offset, value] of [[0, 0x4f434246], [4, 2], [8, 1], [12, ++fixture.sequence], [16, fixture.tick], [24, width], [28, height], [40, Number(full)], [44, Number(fixture.running)]]) data.setUint32(offset, value, true);
            data.setInt32(32, -256, true); data.setInt32(36, -128, true); data.setFloat64(48, 120, true); data.setUint32(64, fixture.tick, true); data.setFloat64(72, 10000, true);
            if (full) { for (const index of changed) data.setUint8(80 + index, fixture.pendingState); }
            else if (delta) { let offset = 80; for (const index of changed) { data.setInt32(offset, index, true); data.setInt32(offset + 4, fixture.pendingState, true); offset += 8; } }
            fixture.reportedState = fixture.pendingState; return bytes;
        };
        (window as unknown as { __TAURI_INTERNALS__: unknown }).__TAURI_INTERNALS__ = { invoke: async (command: string, args?: { action?: string }) => {
            if (command === 'recentProjects') return ['LodRuntime.ocb'];
            if (command === 'openProject') {
                const tiles = [];
                for (let y = -128; y < 128; y++) for (let x = -256; x < 256; x++) tiles.push({ x, y, toolId: 'traceGreen', componentId: 1 + Math.floor((x + 256) / 64) + Math.floor((y + 128) / 64) * 8, isOn: true });
                return { board: { circuitModel: 'booleanSwitch', selectedTool: 'traceGreen', clockHoldTicks: 1, latchInitialState: true, grid: { originX: -512, originY: -512, width: 1024, height: 1024 }, tiles }, blueprints: [] };
            }
            if (command === 'compileGrid') return encode(true);
            if (command !== 'simulationCommand') throw Error(command);
            if (args?.action === 'release') return new ArrayBuffer(0);
            if (args?.action === 'run') fixture.running = true;
            if (args?.action === 'pause') fixture.running = false;
            if (args?.action === 'poll') fixture.tick++;
            return encode(args?.action !== 'poll');
        } };
    });
    await page.goto('/'); await expect(page.getByTestId('board')).toHaveAttribute('data-render-ready', 'true');
    await page.locator('.project-switcher').click(); await page.getByRole('menuitem', { name: 'LodRuntime.ocb', exact: true }).click();
    await page.getByText(mode, { exact: true }).click();
    if (lod === 'color') await page.getByTestId('board').evaluate(element => {
        const box = element.getBoundingClientRect();
        for (let i = 0; i < 18; i++) element.dispatchEvent(new WheelEvent('wheel', { bubbles: true, cancelable: true, clientX: box.x + box.width / 2, clientY: box.y + box.height / 2, deltaY: 100 }));
    });
    if (lod === 'aggregate') await page.getByRole('button', { name: 'Fit board in view' }).click();
    await expect(page.getByTestId('board')).toHaveAttribute('data-lod', lod);
    await page.getByRole('button', { name: 'Run circuit', exact: true }).click(); await page.mouse.move(100, 25);
    await expect(page.getByTestId('board')).toHaveAttribute('data-color-ready', 'true', { timeout: 30000 });
    const metrics = await page.evaluate(async () => {
        const fixture = (window as unknown as { LodFixture: { pendingState: number } }).LodFixture;
        const canvas = document.querySelector('canvas[aria-label="Circuit board"]') as HTMLCanvasElement, gl = canvas.getContext('webgl2')!;
        const scale = canvas.width / canvas.getBoundingClientRect().width;
        const on = () => { const color = new Uint8Array(4); gl.readPixels(Math.floor(canvas.width / 2 + 8 * scale), canvas.height - 1 - Math.floor(canvas.height / 2 + 8 * scale), 1, 1, gl.RGBA, gl.UNSIGNED_BYTE, color); return color[1] > 130; };
        const transitions: { frames: number; ms: number }[] = [];
        for (let transition = 0; transition < 11; transition++) {
            fixture.pendingState = 1 - fixture.pendingState;
            const start = performance.now(); let frames = 0;
            do { await new Promise(requestAnimationFrame); frames++; } while (on() !== !!fixture.pendingState && frames < 12);
            transitions.push({ frames, ms: performance.now() - start });
        }
        return transitions;
    });
    await writeFile(buildPath(`LodRefresh-${mode}-${lod}.json`), JSON.stringify(metrics, null, 2));
    const frames = metrics.map(value => value.frames).sort((a, b) => a - b);
    expect(frames[Math.floor(frames.length / 2)]).toBeLessThanOrEqual(lod === 'detail' ? 2 : 3);
    expect(frames.at(-1)).toBeLessThan(12);
    await page.screenshot({ path: buildPath(`LodRefresh-${mode}-${lod}Capture.png`) });
    await page.getByRole('button', { name: 'Back to design', exact: true }).click();
    await expect(page.getByTestId('board')).toHaveAttribute('data-color-ready', 'true');
});
