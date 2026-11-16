import { test, expect } from '../BrowserTest';
import { buildPath } from '../Paths';
test('an immediately available runtime delta reaches the canvas within two display frames', async ({ page }) => {
    await page.addInitScript(() => {
        const fixture = { pendingState: 0, reportedState: 0, sequence: 0, tick: 0, running: false };
        (window as unknown as { SimulationFixture: typeof fixture }).SimulationFixture = fixture;
        const encode = (full: boolean) => {
            const changed = fixture.pendingState !== fixture.reportedState;
            const bytes = new ArrayBuffer(80 + (full ? 1 : changed ? 8 : 0)), data = new DataView(bytes);
            for (const [offset, value] of [[0, 0x4f434246], [4, 2], [8, 1], [12, ++fixture.sequence], [16, fixture.tick],
                [24, 1], [28, 1], [40, Number(full)], [44, Number(fixture.running)]]) data.setUint32(offset, value, true);
            data.setFloat64(48, 120, true); data.setUint32(64, fixture.tick, true); data.setFloat64(72, 10000, true);
            if (full) data.setUint8(80, fixture.pendingState);
            else if (changed) { data.setInt32(80, 0, true); data.setInt32(84, fixture.pendingState, true); }
            fixture.reportedState = fixture.pendingState;
            return bytes;
        };
        (window as unknown as { __TAURI_INTERNALS__: unknown }).__TAURI_INTERNALS__ = { invoke: async (command: string, args?: { action?: string }) => {
            if (command === 'recentProjects') return ['Runtime.ocb'];
            if (command === 'openProject') return { board: { selectedTool: 'latch', clockHoldTicks: 1, latchInitialState: false,
                grid: { originX: -20, originY: -14, width: 40, height: 28 }, tiles: [{ x: 0, y: 0, toolId: 'latch', componentId: 1, isOn: false }] }, blueprints: [] };
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
    await page.locator('.project-switcher').click(); await page.getByRole('menuitem', { name: 'Runtime.ocb', exact: true }).click();
    await page.getByRole('button', { name: 'Run circuit', exact: true }).click();
    await expect(page.getByRole('button', { name: 'Pause simulation', exact: true })).toBeEnabled(); await page.mouse.move(100, 25);
    const frames = await page.evaluate(async () => {
        const fixture = (window as unknown as { SimulationFixture: { pendingState: number } }).SimulationFixture;
        const canvas = document.querySelector('canvas[aria-label="Circuit board"]') as HTMLCanvasElement, gl = canvas.getContext('webgl2')!;
        const scale = canvas.width / canvas.getBoundingClientRect().width;
        const pixel = () => {
            const data = new Uint8Array(4);
            gl.readPixels(Math.floor(canvas.width / 2 + 8 * scale), canvas.height - 1 - Math.floor(canvas.height / 2 + 8 * scale), 1, 1, gl.RGBA, gl.UNSIGNED_BYTE, data);
            return [...data].join(',');
        };
        await new Promise(requestAnimationFrame); await new Promise(requestAnimationFrame);
        const before = pixel(); fixture.pendingState = 1;
        for (let frame = 1; frame <= 2; frame++) {
            await new Promise(requestAnimationFrame);
            if (pixel() !== before) return frame;
        }
        return 0;
    });
    expect(frames).toBeGreaterThan(0); expect(frames).toBeLessThanOrEqual(2);
    await page.screenshot({ path: buildPath('SimulationDisplayRefreshCapture.png') });
    await page.getByRole('button', { name: 'Pause simulation', exact: true }).click();
    await page.getByRole('button', { name: 'Back to design', exact: true }).click();
});
