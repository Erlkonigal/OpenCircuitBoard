import { browser, $, expect } from '@wdio/globals';
import path from 'node:path';
import { WorkspaceRoot, buildPath } from '../Paths';

const Frames = [
    { slot: 0, name: 'H', bits: '1000110001100011111110001100011000100000' },
    { slot: 5, name: 'Comma', bits: '0000000000000000000000000001100010001000' },
    { slot: 6, name: 'Space', bits: '0000000000000000000000000000000000000000' },
    { slot: 7, name: 'W', bits: '1000110001100011010110101110111000100000' },
    { slot: 12, name: 'Exclamation', bits: '0010000100001000010000100000000010000000' },
    { slot: 13, name: 'Loop', bits: '1000110001100011111110001100011000100000' },
];

async function displayBits() {
    return browser.execute(() => {
        const canvas = document.querySelector('canvas[aria-label="Circuit board"]') as HTMLCanvasElement;
        const gl = canvas.getContext('webgl2') || canvas.getContext('webgl');
        if (!gl) throw Error('No native WebGL context');
        const scale = canvas.width / canvas.getBoundingClientRect().width;
        const zoom = .5 / 1.1 ** 18;
        return Array.from({ length: 40 }, (_, pixel) => {
            const x = -22 + pixel % 5 * 10 + 1.5, y = -37 + Math.floor(pixel / 5) * 10 + 1.5;
            const color = new Uint8Array(4);
            gl.readPixels(Math.floor(canvas.width / 2 + x * 64 * zoom * scale),
                canvas.height - 1 - Math.floor(canvas.height / 2 + y * 64 * zoom * scale),
                1, 1, gl.RGBA, gl.UNSIGNED_BYTE, color);
            return color[0] > 100 ? '1' : '0';
        }).join('');
    });
}

describe('Hello World 5x8 example', () => {
    it('opens the committed archive and displays real simulated glyphs', async () => {
        const file = path.join(WorkspaceRoot, 'Frontend/Assets/Examples/HelloWorld5x8.ocb');
        await browser.execute(async (file: string) => {
            const invoke = (window as unknown as { __TAURI_INTERNALS__: { invoke: (command: string, args: unknown) => Promise<unknown> } }).__TAURI_INTERNALS__.invoke;
            await invoke('openProject', { path: file });
        }, file);
        await browser.refresh();
        await browser.waitUntil(async () => await $('[data-testid="board"]').getAttribute('data-render-ready') === 'true');
        await $('.project-switcher').click();
        await $('button=HelloWorld5x8.ocb').click();
        await expect($('.project-switcher')).toHaveText(expect.stringContaining('HelloWorld5x8.ocb'));
        await browser.waitUntil(async () => await $('[data-testid="board"]').getAttribute('data-color-ready') === 'true', { timeout: 30000 });
        await $('label=2D').click();
        await browser.execute(() => {
            const board = document.querySelector('[data-testid="board"]')!, box = board.getBoundingClientRect();
            for (let index = 0; index < 18; index++) board.dispatchEvent(new WheelEvent('wheel', {
                bubbles: true, cancelable: true, clientX: box.x + box.width / 2,
                clientY: box.y + box.height / 2, deltaY: 100,
            }));
        });
        await $('input[aria-label="Ticks per second"]').setValue('16');
        await browser.keys('Tab');
        await $('button=Run circuit').click();
        await $('button[aria-label="Pause simulation"]').click();
        await $('button[aria-label="Reset simulation"]').click();
        await browser.waitUntil(async () => await displayBits() === '0'.repeat(40));
        let tick = 0;
        for (const frame of Frames) {
            const target = 5 + frame.slot * 8;
            while (tick < target) {
                const length = Math.min(16, target - tick);
                await $('input[aria-label="Step length"]').setValue(String(length));
                await browser.keys('Tab');
                await $('button[aria-label="Next tick"]').click();
                tick += length;
                await browser.waitUntil(async () => (await $('.workspace-status').getText()).includes(`Tick ${tick}`));
            }
            await browser.waitUntil(async () => await displayBits() === frame.bits, { timeoutMsg: `Incorrect native LED glyph: ${frame.name}` });
            await browser.saveScreenshot(buildPath(`DesktopHelloWorld${frame.name}Capture.png`));
        }
        await $('button[aria-label="Fit board in view"]').click();
        await expect($('[data-testid="board"]')).toHaveAttribute('data-lod', 'aggregate');
        await browser.waitUntil(async () => await $('[data-testid="board"]').getAttribute('data-color-ready') === 'true', { timeout: 30000 });
        const overview = await browser.execute(() => (document.querySelector('canvas[aria-label="Circuit board"]') as HTMLCanvasElement).toDataURL());
        await $('input[aria-label="Step length"]').setValue('8'); await browser.keys('Tab');
        await $('button[aria-label="Next tick"]').click(); tick += 8;
        await browser.waitUntil(async () => await browser.execute(() => (document.querySelector('canvas[aria-label="Circuit board"]') as HTMLCanvasElement).toDataURL()) !== overview, { timeoutMsg: 'Hello World overview did not refresh after a native step' });
        await browser.saveScreenshot(buildPath('DesktopHelloWorldOverviewCapture.png'));
        await $('button[aria-label="Run simulation"]').click();
        await browser.waitUntil(async () => !(await $('.workspace-status').getText()).includes(`Tick ${tick}`));
        await $('button[aria-label="Pause simulation"]').click();
        const paused = await $('.workspace-status').getText();
        await browser.execute(() => new Promise<void>(resolve => requestAnimationFrame(() => requestAnimationFrame(() => resolve()))));
        expect(await $('.workspace-status').getText()).toBe(paused);
        await $('button=Back to design').click();
        await expect($('.workspace-status')).toHaveText(expect.stringContaining('Ready'));
        await expect($('.error-toast')).not.toExist();
    });
});
