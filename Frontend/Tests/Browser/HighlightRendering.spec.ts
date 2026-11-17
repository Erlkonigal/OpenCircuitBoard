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
                return { board: { circuitModel: 'booleanSwitch', selectedTool: 'traceCyan', clockHoldTicks: 1, buttonInitialState: true,
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
            [0, -middle * px], [-half * px - .375 * px - 3, 0]];
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
            expect(selected[3]).toEqual(hovered[3]); expect(selected[5]).toEqual(before[5]);
            expect(selected[0]).toEqual(hovered[0]);
            await page.mouse.move(center.x - middle * px, center.y);
            expect(await pixels(page, points)).toEqual(selected); // Selection + hover is one pass, including aggregate coverage.
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

const PaletteInks = ['traceOrange', 'traceWhite', 'trace', 'traceRed', 'traceGreen', 'traceBlue', 'traceCyan', 'traceMagenta', 'bus', 'cross', 'switch', 'buffer', 'and', 'or', 'xor', 'not', 'nand', 'nor', 'xnor', 'button', 'clock', 'led'];
const brightness = (pixel: number[]) => pixel[0] * .2126 + pixel[1] * .7152 + pixel[2] * .0722;
for (const isOn of [true, false]) test(`every ink reserves visible highlight headroom on ${isOn ? 'active' : 'inactive'} surfaces`, async ({ page }) => {
    await page.addInitScript(({ inks, isOn }) => {
        (window as unknown as { __TAURI_INTERNALS__: unknown }).__TAURI_INTERNALS__ = { invoke: async (command: string) => {
            if (command === 'recentProjects') return ['Palette.ocb'];
            if (command !== 'openProject') throw Error(command);
            return { board: { circuitModel: 'booleanSwitch', selectedTool: 'led', clockHoldTicks: 1, buttonInitialState: true,
                grid: { originX: -20, originY: -14, width: 40, height: 28 },
                tiles: inks.map((toolId, i) => ({ x: i % 7 - 3, y: Math.floor(i / 7) - 2, componentId: i + 1, toolId, isOn })) }, blueprints: [] };
        } };
    }, { inks: PaletteInks, isOn });
    await page.goto('/'); await expect(page.getByTestId('board')).toHaveAttribute('data-render-ready', 'true');
    await page.locator('.project-switcher').click(); await page.getByRole('menuitem', { name: 'Palette.ocb', exact: true }).click();
    const board = page.getByTestId('board'), box = (await board.boundingBox())!;
    const center = { x: box.x + box.width / 2, y: box.y + box.height / 2 };
    const points = PaletteInks.map((_, i) => [(i % 7 - 3) * 32 + 2, (Math.floor(i / 7) - 2) * 32 + 2]);
    for (const mode of ['2D', '2.5D']) {
        await page.getByText(mode, { exact: true }).click(); await board.focus(); await page.keyboard.press('Control+d'); await page.mouse.move(100, 25);
        await expect(board).toHaveAttribute('data-color-ready', 'true');
        const before = await pixels(page, points), individual: number[][] = [];
        for (let i = 0; i < PaletteInks.length; i++) {
            expect(brightness(before[i])).toBeLessThanOrEqual(160);
            await page.mouse.move(center.x + points[i][0], center.y + points[i][1]);
            await expect(board).toHaveAttribute('data-highlight-components', String(i + 1));
            const hovered = await pixels(page, points);
            expect(brightness(hovered[i]) - brightness(before[i]), PaletteInks[i]).toBeGreaterThanOrEqual(12);
            individual.push(hovered[i]);
            for (let other = 0; other < PaletteInks.length; other++) if (i !== other) expect(hovered[other]).toEqual(before[other]);
        }
        await page.screenshot({ path: buildPath(`HighlightPalette${mode === '2D' ? 'Flat' : 'Depth'}${isOn ? 'Active' : 'Inactive'}HoverCapture.png`) });
        await board.focus(); await page.keyboard.press('Control+a'); await page.mouse.move(100, 25);
        const selected = await pixels(page, points);
        expect(selected).toEqual(individual);
        await page.mouse.move(center.x + points[0][0], center.y + points[0][1]);
        expect(await pixels(page, points)).toEqual(selected);
        await page.screenshot({ path: buildPath(`HighlightPalette${mode === '2D' ? 'Flat' : 'Depth'}${isOn ? 'Active' : 'Inactive'}SelectedCapture.png`) });
    }
});

for (const lod of ['detail', 'color'] as const) for (const isOn of [true, false])
    test(`${lod} highlights both depth faces with correct diagonal occlusion on ${isOn ? 'active' : 'inactive'} ink`, async ({ page }) => {
        const extent = lod === 'detail' ? 40 : 96;
        await page.addInitScript(({ extent, isOn }) => {
            (window as unknown as { __TAURI_INTERNALS__: unknown }).__TAURI_INTERNALS__ = { invoke: async (command: string) => {
                if (command === 'recentProjects') return ['DepthHighlight.ocb']; if (command !== 'openProject') throw Error(command);
                const tiles = [];
                for (let y = -4; y < 4; y++) for (let x = -4; x < 5; x++) {
                    if (x >= -2 && x < 2 && y >= -2 && y < 2) continue;
                    tiles.push({ x, y, toolId: 'traceCyan', componentId: x < 4 ? 1 : 2, isOn });
                }
                tiles.push({ x: -5, y: 4, toolId: 'traceRed', componentId: 3, isOn });
                return { board: { circuitModel: 'booleanSwitch', selectedTool: 'traceCyan', clockHoldTicks: 1, buttonInitialState: true,
                    grid: { originX: -extent / 2, originY: -extent / 2, width: extent, height: extent }, tiles }, blueprints: [] };
            } };
        }, { extent, isOn });
        await page.goto('/'); const board = page.getByTestId('board'); await expect(board).toHaveAttribute('data-render-ready', 'true');
        await page.locator('.project-switcher').click(); await page.getByRole('menuitem', { name: 'DepthHighlight.ocb', exact: true }).click();
        await expect(page.getByRole('menu')).toBeHidden();
        const box = (await board.boundingBox())!, center = { x: box.x + box.width / 2, y: box.y + box.height / 2 };
        const px = lod === 'detail' ? 32 : Math.min(box.width, box.height) / extent;
        if (lod === 'color') await page.getByRole('button', { name: 'Fit board in view', exact: true }).click();
        await expect(board).toHaveAttribute('data-lod', lod);
        // Top, left face, bottom face, hole wall, diagonal occluder, adjacent top, empty exterior, hole center.
        const points = [[-3, 0], [-4.1875, .6875], [-2.6875, 4.1875], [1.8125, .6875], [-4.1875, 4.1875], [4.5, .5], [-4.6, .6875], [0, 0]].map(p => p.map(v => v * px));
        for (const mode of ['2D', '2.5D']) {
            await page.getByText(mode, { exact: true }).click(); await board.focus(); await page.keyboard.press('Control+d'); await page.mouse.move(100, 25);
            await expect(board).toHaveAttribute('data-color-ready', 'true'); const before = await pixels(page, points);
            await page.mouse.move(center.x - 3 * px, center.y); await expect(board).toHaveAttribute('data-highlight-components', '1');
            const hovered = await pixels(page, points);
            expect(hovered[0]).not.toEqual(before[0]);
            for (const i of [1, 2, 3]) {
                if (mode === '2.5D') {
                    expect(brightness(hovered[i]) - brightness(before[i])).toBeGreaterThan(15);
                    expect(brightness(hovered[0]) - brightness(hovered[i])).toBeGreaterThan(5);
                }
                else expect(hovered[i]).toEqual(before[i]);
            }
            for (const i of [4, 5, 6, 7]) expect(hovered[i]).toEqual(before[i]);
            await page.screenshot({ path: buildPath(`HighlightSides${lod}${mode === '2D' ? 'Flat' : 'Depth'}${isOn ? 'Active' : 'Inactive'}HoverCapture.png`) });
            await page.mouse.click(center.x - 3 * px, center.y); await page.mouse.move(100, 25); await expect(board).toHaveAttribute('data-selection-cells', '48');
            expect(await pixels(page, points)).toEqual(hovered);
            await page.mouse.move(center.x - 3 * px, center.y); expect(await pixels(page, points)).toEqual(hovered);
            await expect(board).not.toHaveAttribute('data-render-error');
        }
    });
