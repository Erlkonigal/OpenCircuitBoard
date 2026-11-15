import { browser, $, expect } from '@wdio/globals';
import { buildPath } from '../Paths';
describe('Native circuit workspace', () => {
    it('renders the redesigned desktop workspace', async () => {
        await expect($('[data-testid="left-dock"]')).toHaveText(expect.stringContaining('Components'));
        await expect($('[data-testid="right-dock"]')).toHaveText(expect.stringContaining('Inspector'));
        await browser.waitUntil(async () => { const error = await $('[data-testid="board"]').getAttribute('data-render-error'); if (error)
            throw Error(error); return await $('canvas[aria-label="Circuit board"]').isDisplayed(); }, { timeout: 15000, timeoutMsg: 'PixiJS canvas did not initialize' });
        await browser.saveScreenshot(buildPath('DesktopCapture.png'));
    });
    it('compiles a drawn clock, runs, pauses, steps and returns to design', async () => {
        await $('button[aria-label="Clock"]').click();
        await $('[data-testid="board"]').click();
        await $('button=Run circuit').click();
        await expect($('.workspace-status')).toHaveText(expect.stringContaining('Simulating'));
        await $('button[aria-label="Pause simulation"]').click();
        await expect($('.workspace-status')).toHaveText(expect.stringContaining('Paused'));
        const previous = await $('.workspace-status').getText();
        await $('button[aria-label="Next tick"]').click();
        await browser.waitUntil(async () => (await $('.workspace-status').getText()) !== previous);
        await browser.saveScreenshot(buildPath('DesktopSimulationCapture.png'));
        await $('button[aria-label="Previous tick"]').click();
        await expect($('.workspace-status')).toHaveText(previous);
        await $('button[aria-label="Full speed"]').click();
        await $('button[aria-label="Run simulation"]').click();
        await browser.waitUntil(async () => (await $('.workspace-status').getText()) !== previous);
        await browser.saveScreenshot(buildPath('DesktopLoopCapture.png'));
        await $('button[aria-label="Pause simulation"]').click();
        await expect($('.workspace-status')).toHaveText(expect.stringContaining('Paused'));
        await $('button=Back to design').click();
        await expect($('.workspace-status')).toHaveText(expect.stringContaining('Ready'));
    });
    it('updates the rendered latch state through native simulation IPC', async () => {
        await $('.command-trigger').click();
        await $('input[aria-label="Search commands"]').setValue('new circuit');
        await $('.command-options button').click();
        await $('button[aria-label="Latch"]').click();
        await $('[data-testid="board"]').click();
        await $('button=Run circuit').click();
        await expect($('.workspace-status')).toHaveText(expect.stringContaining('Simulating'));
        await $('button[aria-label="Pause simulation"]').click();
        const pixel = () => browser.execute(() => {
            const canvas = document.querySelector('canvas[aria-label="Circuit board"]') as HTMLCanvasElement;
            const rectangle = canvas.getBoundingClientRect();
            const scale = canvas.width / rectangle.width;
            const gl = canvas.getContext('webgl2') || canvas.getContext('webgl');
            if (!gl) throw Error('WebGL context unavailable');
            const data = new Uint8Array(4);
            gl.readPixels(Math.floor((rectangle.width / 2 + 8) * scale), Math.floor((rectangle.height / 2 - 8) * scale), 1, 1, gl.RGBA, gl.UNSIGNED_BYTE, data);
            return [...data];
        });
        const before = JSON.stringify(await pixel());
        await $('[data-testid="board"]').click();
        await browser.waitUntil(async () => JSON.stringify(await pixel()) !== before, { timeoutMsg: 'Latch state did not change on the canvas' });
        await browser.saveScreenshot(buildPath('DesktopLatchCapture.png'));
        await $('button=Back to design').click();
    });
    it('round-trips v2 archives through real native IPC', async () => {
        const file = buildPath('DesktopProject.ocb');
        const board = { selectedTool: 'clock', clockHoldTicks: 3, meshId: 7, latchInitialState: false, grid: { originX: -20, originY: -14, width: 40, height: 28 }, tiles: [{ x: -2, y: 1, toolId: 'clock', isOn: true, clockHoldTicks: 3 }, { x: 0, y: 1, toolId: 'latch', isOn: false }] };
        const result = await browser.execute(async (file: string, project: typeof board) => {
            try {
                const invoke = (window as unknown as Window & {
                    __TAURI_INTERNALS__: {
                        invoke: (command: string, args: unknown) => Promise<unknown>;
                    };
                }).__TAURI_INTERNALS__.invoke;
                await invoke('saveProject', { path: file, board: project });
                return await invoke('openProject', { path: file });
            }
            catch (error) {
                return { error: String(error) };
            }
        }, file, board);
        expect(result).toEqual(board);
    });
    it('renders joined sides and gradients in the real WebView', async () => {
        await $('.command-trigger').click();
        await $('input[aria-label="Search commands"]').setValue('new circuit');
        await $('.command-options button').click();
        await $('button[aria-label="Or"]').click();
        const center = await browser.execute(() => {
            const rectangle = document.querySelector('[data-testid="board"]')!.getBoundingClientRect();
            return { x: rectangle.x + rectangle.width / 2, y: rectangle.y + rectangle.height / 2 };
        });
        for (const [x, y] of [[0, 0], [1, 0], [0, 1], [1, 1]])
            await browser.action('pointer').move({ x: Math.round(center.x + x * 32 + 12), y: Math.round(center.y + y * 32 + 12) }).down().up().perform();
        await browser.action('pointer').move({ x: 100, y: 25 }).perform();
        await expect($('.workspace-status')).toHaveText(expect.stringContaining('4 cells'));
        await browser.execute(() => new Promise<void>(resolve => requestAnimationFrame(() => requestAnimationFrame(() => resolve()))));
        const colors = await browser.execute(() => {
            const canvas = document.querySelector('canvas[aria-label="Circuit board"]') as HTMLCanvasElement;
            const gl = canvas.getContext('webgl2') || canvas.getContext('webgl');
            if (!gl) throw Error('WebGL context unavailable');
            const scale = canvas.width / canvas.getBoundingClientRect().width;
            return [[8, 138], [24, 138], [48, 138], [72, 138], [88, 138], [112, 138], [16, 132], [16, 146]].map(([x, y]) => {
                const data = new Uint8Array(4);
                gl.readPixels(Math.floor(canvas.width / 2 + x * .5 * scale), canvas.height - 1 - Math.floor(canvas.height / 2 + y * .5 * scale), 1, 1, gl.RGBA, gl.UNSIGNED_BYTE, data);
                return [...data].slice(0, 3);
            });
        });
        for (const channel of [0, 1, 2]) {
            const values = colors.slice(0, 6).map(color => color[channel]);
            expect(Math.max(...values) - Math.min(...values)).toBeLessThanOrEqual(3);
        }
        const sum = (color: number[]) => color.reduce((total, value) => total + value, 0);
        expect(sum(colors[6]) - sum(colors[7])).toBeGreaterThan(15);
        await browser.saveScreenshot(buildPath('DesktopJoinedTilesCapture.png'));
    });

});
