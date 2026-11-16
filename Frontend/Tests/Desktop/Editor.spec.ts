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
    it('advances at 1-4 TPS and keeps measured throughput visible between ticks', async () => {
        await $('.command-trigger').click();
        await $('input[aria-label="Search commands"]').setValue('new circuit');
        await $('.command-options button').click();
        await $('button[aria-label="Clock"]').click();
        await $('[data-testid="board"]').click();
        const tickSelector = '.simulation-summary .metric-grid > div:nth-child(1) strong';
        const throughputSelector = '.simulation-summary .metric-grid > div:nth-child(2) strong';
        for (const rate of [1, 2, 3, 4]) {
            await $('input[aria-label="Ticks per second"]').setValue(String(rate));
            await browser.keys('Tab');
            await $('button=Run circuit').click();
            await browser.waitUntil(async () => Number(await $(tickSelector).getText()) >= 2 &&
                await $(throughputSelector).getText() === `${rate} TPS`,
                { timeout: 6000, interval: 100, timeoutMsg: `${rate} TPS did not advance with measured throughput` });
            const readings = await browser.execute(async (selector: string) => {
                const values: string[] = [];
                for (let sample = 0; sample < 6; sample++) {
                    values.push(document.querySelector(selector)!.textContent!.trim());
                    await new Promise(resolve => setTimeout(resolve, 100));
                }
                return values;
            }, throughputSelector);
            expect(readings).toEqual(Array(6).fill(`${rate} TPS`));
            await browser.saveScreenshot(buildPath(`DesktopLowSpeed${rate}Capture.png`));
            await $('button[aria-label="Pause simulation"]').click();
            await $('button=Back to design').click();
        }
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
    it('isolates adjacent latch lanes through drawn boundaries and native simulation', async () => {
        await $('.command-trigger').click(); await $('input[aria-label="Search commands"]').setValue('new circuit'); await $('.command-options button').click();
        const center = await browser.execute(() => { const r = document.querySelector('[data-testid="board"]')!.getBoundingClientRect(); return {x:r.x+r.width/2,y:r.y+r.height/2}; });
        for (const [index, tool] of ['Latch','Read','Trace','Write','Buffer'].entries()) {
            await $(`button[aria-label="${tool}"]`).click();
            if (tool === 'Latch') await $('label=Off').click();
            for (const row of [0,1]) await browser.action('pointer').move({x:Math.round(center.x+index*32+12),y:Math.round(center.y+row*32+12)}).down().up().perform();
        }
        await $('button[aria-label="Isolation"]').click();
        await browser.action('pointer').move({x:Math.round(center.x+1),y:Math.round(center.y+32)}).down().move({x:Math.round(center.x+159),y:Math.round(center.y+32),duration:300}).up().perform();
        await expect($('.workspace-status')).toHaveText(expect.stringContaining('5 edges'));
        const pixels = () => browser.execute(() => {
            const canvas=document.querySelector('canvas[aria-label="Circuit board"]') as HTMLCanvasElement, gl=canvas.getContext('webgl2')!;
            const scale=canvas.width/canvas.getBoundingClientRect().width;
            return [0,1].flatMap(row => [0,4].map(column => { const p=new Uint8Array(4); gl.readPixels(Math.floor(canvas.width/2+(column*32+3)*scale),canvas.height-1-Math.floor(canvas.height/2+(row*32+3)*scale),1,1,gl.RGBA,gl.UNSIGNED_BYTE,p); return [...p]; }));
        });
        await $('button=Run circuit').click(); await $('button[aria-label="Pause simulation"]').click();
        const before=await pixels();
        await browser.action('pointer').move({x:Math.round(center.x+12),y:Math.round(center.y+12)}).down().up().perform();
        await $('button[aria-label="Next tick"]').click();
        await browser.waitUntil(async()=>JSON.stringify((await pixels())[0])!==JSON.stringify(before[0]));
        const after=await pixels(); expect(after[2]).toEqual(before[2]); expect(after[3]).toEqual(before[3]); expect(after[1]).not.toEqual(before[1]);
        await browser.saveScreenshot(buildPath('DesktopIsolationCapture.png'));
        await $('button=Back to design').click();
        await $('button[aria-label="Isolation"]').click();
        await browser.action('pointer').move({x:Math.round(center.x+1),y:Math.round(center.y+32)}).down({button:2}).move({x:Math.round(center.x+159),y:Math.round(center.y+32),duration:300}).up({button:2}).perform();
        await expect($('.workspace-status')).not.toHaveText(expect.stringContaining('edges'));
        await $('button=Run circuit').click(); await $('button[aria-label="Pause simulation"]').click();
        const joined=await pixels();
        await browser.action('pointer').move({x:Math.round(center.x+12),y:Math.round(center.y+12)}).down().up().perform();
        await $('button[aria-label="Next tick"]').click();
        await browser.waitUntil(async()=>JSON.stringify((await pixels())[2])!==JSON.stringify(joined[2]));
        await $('button=Back to design').click();
    });
    it('round-trips v2 archives through real native IPC', async () => {
        const file = buildPath('DesktopProject.ocb');
        const board = { isolationEdges: [{ x: 0, y: 1, axis: 'vertical' }], selectedTool: 'clock', clockHoldTicks: 3, latchInitialState: false, grid: { originX: -20, originY: -14, width: 40, height: 28 }, tiles: [{ x: -2, y: 1, toolId: 'clock', isOn: true, clockHoldTicks: 3 }, { x: 0, y: 1, toolId: 'latch', isOn: false }] };
        const result = await browser.execute(async (file: string, project: typeof board) => {
            try {
                const invoke = (window as unknown as Window & {
                    __TAURI_INTERNALS__: {
                        invoke: (command: string, args: unknown) => Promise<unknown>;
                    };
                }).__TAURI_INTERNALS__.invoke;
                await invoke('saveProject', { path: file, project: { board: project, blueprints: [{ id: 'clock', name: 'Clock', width: 1, height: 1, isolationEdges: [], tiles: [{ x: 0, y: 0, toolId: 'clock', isOn: true, clockHoldTicks: 3 }] }] } });
                return await invoke('openProject', { path: file });
            }
            catch (error) {
                return { error: String(error) };
            }
        }, file, board);
        expect(result).toEqual({ board, blueprints: [{ id: 'clock', name: 'Clock', width: 1, height: 1, isolationEdges: [], tiles: [{ x: 0, y: 0, toolId: 'clock', isOn: true, clockHoldTicks: 3 }] }] });
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

    it('remembers the display mode after reopening the native webview', async () => {
        await $('label=2D').click();
        await browser.refresh();
        await browser.waitUntil(async () => await $('[data-testid="board"]').getAttribute('data-render-ready') === 'true');
        expect(await browser.execute(() => (document.querySelector('input[value="2d"]') as HTMLInputElement).checked)).toBe(true);
        await browser.saveScreenshot(buildPath('DesktopFlatCapture.png'));
        await $('label=2.5D').click();
    });
    it('updates aggregate color textures from native runtime frames and restores editable colors', async () => {
        const file = buildPath('DesktopLodProject.ocb');
        const result = await browser.execute(async (file: string) => {
            const tiles: { x: number; y: number; toolId: string; isOn: boolean; clockHoldTicks: number }[] = [];
            for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++) tiles.push({ x, y, toolId: 'clock', isOn: true, clockHoldTicks: 1 });
            const invoke = (window as unknown as { __TAURI_INTERNALS__: { invoke: (command: string, args: unknown) => Promise<unknown> } }).__TAURI_INTERNALS__.invoke;
            return invoke('saveProject', { path: file, project: { board: { selectedTool: 'clock', clockHoldTicks: 1, latchInitialState: true,
                grid: { originX: -512, originY: -512, width: 1024, height: 1024 }, tiles },
                blueprints: [{ id: 'clocks', name: 'Clock array', width: 64, height: 64, tiles }] } });
        }, file);
        expect(result).toBe(file);
        await browser.refresh();
        await $('.project-switcher').click();
        await $('button=DesktopLodProject.ocb').click();
        await expect($('.workspace-status')).toHaveText(expect.stringContaining('4,096 cells'));
        await $('button[aria-label="Fit board in view"]').click();
        await browser.waitUntil(async () => await $('[data-testid="board"]').getAttribute('data-color-ready') === 'true');
        await expect($('[data-testid="board"]')).toHaveAttribute('data-lod', 'aggregate');
        const pixel = () => browser.execute(() => {
            const canvas = document.querySelector('canvas[aria-label="Circuit board"]') as HTMLCanvasElement;
            const gl = canvas.getContext('webgl2') || canvas.getContext('webgl'); if (!gl) throw Error('No WebGL');
            const scale = canvas.width / canvas.getBoundingClientRect().width, data = new Uint8Array(4);
            gl.readPixels(Math.floor(canvas.width / 2 + 10 * scale), canvas.height - 1 - Math.floor(canvas.height / 2 + 10 * scale), 1, 1, gl.RGBA, gl.UNSIGNED_BYTE, data);
            return [...data];
        });
        const design = await pixel();
        await $('button=Run circuit').click(); await $('button[aria-label="Pause simulation"]').click();
        await $('button[aria-label="Reset simulation"]').click();
        await browser.waitUntil(async () => await $('[data-testid="board"]').getAttribute('data-color-ready') === 'true');
        const initial = await pixel();
        await $('button[aria-label="Next tick"]').click();
        await browser.waitUntil(async () => JSON.stringify(await pixel()) !== JSON.stringify(initial));
        await browser.saveScreenshot(buildPath('DesktopLodSimulationCapture.png'));
        await $('button=Back to design').click();
        await browser.waitUntil(async () => JSON.stringify(await pixel()) === JSON.stringify(design));
        await browser.saveScreenshot(buildPath('DesktopLodDesignCapture.png'));
    });

});
