import { test, expect, type Page } from '../BrowserTest';
import { buildPath } from '../Paths';
async function settle(page: Page) {
    await page.evaluate(() => new Promise<void>(resolve => requestAnimationFrame(() => requestAnimationFrame(() => resolve()))));
}
async function pixels(page: Page, points: number[][]) {
    await settle(page);
    return page.locator('canvas[aria-label="Circuit board"]').evaluate((element, points) => {
        const canvas = element as HTMLCanvasElement, gl = canvas.getContext('webgl2')!;
        const scale = canvas.width / canvas.getBoundingClientRect().width;
        return points.map(([x, y]) => {
            const pixel = new Uint8Array(4);
            gl.readPixels(Math.floor(canvas.width / 2 + x * scale), canvas.height - 1 - Math.floor(canvas.height / 2 + y * scale), 1, 1, gl.RGBA, gl.UNSIGNED_BYTE, pixel);
            return [...pixel];
        });
    }, points);
}
for (const lod of ['detail', 'color', 'aggregate'] as const) for (const isOn of [true, false]) {
    test(`${lod} whole-surface highlights preserve holes, neighbors and chunk seams on ${isOn ? 'bright' : 'dark'} cyan`, async ({ page }) => {
        const extent = lod === 'detail' ? 40 : lod === 'color' ? 256 : 2048;
        const size = lod === 'detail' ? 8 : lod === 'color' ? 48 : 256;
        await page.addInitScript(({ extent, size, isOn }) => {
            (window as unknown as { __TAURI_INTERNALS__: unknown }).__TAURI_INTERNALS__ = { invoke: async (command: string) => {
                if (command === 'recentProjects') return ['Highlight.ocb'];
                if (command !== 'openProject') throw Error(command);
                const tiles = [], half = size / 2, quarter = size / 4;
                for (let y = -half; y < half; y++) for (let x = -half; x < half + quarter; x++) {
                    if (x >= -quarter && x < quarter && y >= -quarter && y < quarter) continue;
                    tiles.push({ x, y, toolId: 'traceCyan', componentId: x < half ? 1 : 2, isOn });
                }
                return { board: { selectedTool: 'traceCyan', clockHoldTicks: 1, latchInitialState: true,
                    grid: { originX: -extent / 2, originY: -extent / 2, width: extent, height: extent }, tiles }, blueprints: [] };
            } };
        }, { extent, size, isOn });
        await page.goto('/'); await expect(page.getByTestId('board')).toHaveAttribute('data-render-ready', 'true');
        await page.locator('.project-switcher').click(); await page.getByRole('menuitem', { name: 'Highlight.ocb', exact: true }).click();
        const board = page.getByTestId('board'), box = (await board.boundingBox())!;
        const px = lod === 'detail' ? 32 : Math.min(box.width, box.height) / extent;
        const center = { x: box.x + box.width / 2, y: box.y + box.height / 2 };
        if (lod !== 'detail') await page.getByRole('button', { name: 'Fit board in view', exact: true }).click();
        await expect(board).toHaveAttribute('data-lod', lod);
        const half = size / 2, quarter = size / 4, middle = (half + quarter) / 2;
        const points = [[-middle * px, 0], [0, 0], [(half + quarter * .75) * px, 0], [-half * px + 1.5, 0],
            [0, -middle * px], [-half * px - 3, 0]];
        for (const mode of ['2D', '2.5D']) {
            await page.getByText(mode, { exact: true }).click(); await board.focus(); await page.keyboard.press('Control+d'); await page.mouse.move(100, 25);
            await expect(board).toHaveAttribute('data-color-ready', 'true');
            const before = await pixels(page, points);
            await page.mouse.move(center.x - middle * px, center.y);
            await expect(board).toHaveAttribute('data-highlight-cells', String(size * size * .75));
            const hovered = await pixels(page, points);
            expect(hovered[0]).not.toEqual(before[0]); expect(hovered[1]).toEqual(before[1]); expect(hovered[2]).toEqual(before[2]);
            expect(hovered[3]).not.toEqual(before[3]); expect(hovered[4]).toEqual(hovered[0]);
            await page.screenshot({ path: buildPath(`Highlight${lod}${mode === '2D' ? 'Flat' : 'Depth'}${isOn ? 'Bright' : 'Dark'}HoverCapture.png`) });
            await page.mouse.click(center.x - middle * px, center.y); await page.mouse.move(100, 25);
            await expect(board).toHaveAttribute('data-selection-cells', String(size * size * .75));
            const selected = await pixels(page, points);
            expect(selected[0]).not.toEqual(before[0]); expect(selected[1]).toEqual(before[1]); expect(selected[2]).toEqual(before[2]);
            expect(selected[3]).not.toEqual(hovered[3]); expect(selected[5]).toEqual(before[5]);
            expect(selected[0]).not.toEqual(hovered[0]);
            for (let channel = 0; channel < 3; channel++) expect(Math.abs(selected[0][channel] - before[0][channel])).toBeLessThanOrEqual(80);
            expect(Number(await board.getAttribute('data-highlight-objects'))).toBeLessThan(200);
            await page.screenshot({ path: buildPath(`Highlight${lod}${mode === '2D' ? 'Flat' : 'Depth'}${isOn ? 'Bright' : 'Dark'}SelectedCapture.png`) });
            await page.keyboard.down('Shift'); await page.mouse.move(center.x - half * px - 12, center.y - half * px - 12);
            await page.mouse.down(); await page.mouse.move(center.x + half * px + 8, center.y + half * px + 8, { steps: 3 });
            await expect(board).toHaveAttribute('data-gesture', 'marquee'); await settle(page);
            await page.screenshot({ path: buildPath(`Highlight${lod}${mode === '2D' ? 'Flat' : 'Depth'}${isOn ? 'Bright' : 'Dark'}MarqueeCapture.png`) });
            await page.mouse.up(); await page.keyboard.up('Shift');
            await expect(board).not.toHaveAttribute('data-render-error');
        }
    });
}

test('whole-surface emphasis stays visible across the ink palette including nearly white LEDs', async ({ page }) => {
    const inks = ['trace', 'traceRed', 'traceGreen', 'traceBlue', 'traceCyan', 'traceMagenta', 'led'];
    await page.addInitScript(inks => {
        (window as unknown as { __TAURI_INTERNALS__: unknown }).__TAURI_INTERNALS__ = { invoke: async (command: string) => {
            if (command === 'recentProjects') return ['Palette.ocb'];
            if (command !== 'openProject') throw Error(command);
            return { board: { selectedTool: 'led', clockHoldTicks: 1, latchInitialState: true,
                grid: { originX: -20, originY: -14, width: 40, height: 28 },
                tiles: inks.map((toolId, i) => ({ x: i - 3, y: 0, componentId: i + 1, toolId, isOn: true })) }, blueprints: [] };
        } };
    }, inks);
    await page.goto('/'); await expect(page.getByTestId('board')).toHaveAttribute('data-render-ready', 'true');
    await page.locator('.project-switcher').click(); await page.getByRole('menuitem', { name: 'Palette.ocb', exact: true }).click();
    const board = page.getByTestId('board'), box = (await board.boundingBox())!;
    const center = { x: box.x + box.width / 2, y: box.y + box.height / 2 };
    const points = inks.map((_, i) => [(i - 3) * 32 + 4, 4]);
    for (const mode of ['2D', '2.5D']) {
        await page.getByText(mode, { exact: true }).click(); await board.focus(); await page.keyboard.press('Control+d'); await page.mouse.move(100, 25);
        const before = await pixels(page, points);
        for (let i = 0; i < inks.length; i++) {
            await page.mouse.move(center.x + points[i][0], center.y + points[i][1]); await settle(page);
            const hovered = await pixels(page, points);
            expect(Math.max(...hovered[i].slice(0, 3).map((value, channel) => Math.abs(value - before[i][channel])))).toBeGreaterThan(10);
            for (let other = 0; other < inks.length; other++) if (i !== other) expect(hovered[other]).toEqual(before[other]);
        }
        await page.screenshot({ path: buildPath(`HighlightPalette${mode === '2D' ? 'Flat' : 'Depth'}HoverCapture.png`) });
        await board.focus(); await page.keyboard.press('Control+a'); await page.mouse.move(100, 25);
        const selected = await pixels(page, points);
        for (let i = 0; i < inks.length; i++)
            expect(Math.max(...selected[i].slice(0, 3).map((value, channel) => Math.abs(value - before[i][channel])))).toBeGreaterThan(20);
        await page.screenshot({ path: buildPath(`HighlightPalette${mode === '2D' ? 'Flat' : 'Depth'}SelectedCapture.png`) });
    }
});