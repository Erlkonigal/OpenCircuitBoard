import { test, expect, type Page } from '../BrowserTest';
import { writeFile } from 'node:fs/promises';
import { buildPath } from '../Paths';
async function ready(page: Page) {
    await page.goto('/');
    await expect(page.getByTestId('board')).toHaveAttribute('data-render-ready', 'true');
}
async function center(page: Page) {
    const box = (await page.getByTestId('board').boundingBox())!;
    return { x: box.x + box.width / 2, y: box.y + box.height / 2 };
}
async function settle(page: Page) {
    await page.evaluate(() => new Promise<void>(resolve => requestAnimationFrame(() => requestAnimationFrame(() => resolve()))));
}
async function sample(page: Page, x = 15, y = 14) {
    await settle(page);
    return page.locator('canvas[aria-label="Circuit board"]').evaluate((element, point) => {
        const canvas = element as HTMLCanvasElement, gl = canvas.getContext('webgl2') || canvas.getContext('webgl');
        if (!gl) throw Error('No WebGL context');
        const scale = canvas.width / canvas.getBoundingClientRect().width, data = new Uint8Array(4);
        gl.readPixels(Math.floor(canvas.width / 2 + point.x * scale), canvas.height - 1 - Math.floor(canvas.height / 2 + point.y * scale), 1, 1, gl.RGBA, gl.UNSIGNED_BYTE, data);
        return [...data];
    }, { x, y });
}
async function fixture(page: Page, kind: 'dense' | 'sparse' | 'thumbnail') {
    await page.addInitScript(kind => {
        const win = window as unknown as { __TAURI_INTERNALS__: { invoke: (command: string) => Promise<unknown> } };
        win.__TAURI_INTERNALS__ = { invoke: async command => {
            if (command === 'recentProjects') return ['Fixture.ocb'];
            if (command !== 'openProject') throw Error(`Unexpected test IPC: ${command}`);
            const board = { selectedTool: 'or', clockHoldTicks: 1, latchInitialState: true,
                grid: kind === 'sparse' ? { originX: -1000000, originY: -1000000, width: 2000000, height: 2000000 }
                    : { originX: -512, originY: -512, width: 1024, height: 1024 }, tiles: [] as { x: number; y: number; toolId: string; componentId: number; isOn: boolean }[] };
            if (kind === 'dense') {
                for (let y = -512; y < 512; y++) for (let x = -512; x < 512; x++)
                    board.tiles.push({ x, y, toolId: ['traceRed', 'traceGreen', 'traceBlue'][Math.floor((y + 512) / 32) % 3], componentId: 1 + Math.floor((y + 512) / 32), isOn: true });
            }
            else if (kind === 'sparse') {
                for (let i = -3; i <= 3; i++) for (let j = 0; j < 64; j++) board.tiles.push({ x: i * 300000 + j, y: i * 300000, toolId: 'traceRed', componentId: i + 4, isOn: true });
            }
            const tiles = [] as typeof board.tiles;
            for (let y = 0; y < 256; y++) for (let x = 0; x < 256; x++) if (x % 8 < 4)
                tiles.push({ x, y, toolId: ['traceRed', 'traceBlue'][Math.floor(x / 4) % 2], componentId: 1 + Math.floor(x / 8), isOn: true });
            return { board, blueprints: [{ id: 'large', name: 'Large circuit', width: 256, height: 256, tiles }] };
        } };
    }, kind);
    await ready(page);
    await page.locator('.project-switcher').click();
    await page.getByRole('menuitem', { name: 'Fixture.ocb', exact: true }).click();
    await expect(page.locator('.project-switcher')).toContainText('Fixture.ocb', { timeout: 30000 });
}

test('blueprints save snapshots, stay selected and support repeated ordinary pastes', async ({ page }) => {
    const errors: string[] = []; page.on('pageerror', error => errors.push(error.message));
    await ready(page); const origin = await center(page);
    await page.getByRole('button', { name: 'Clock', exact: true }).click();
    await page.getByRole('textbox', { name: 'Clock hold', exact: true }).fill('9');
    await page.mouse.click(origin.x + 12, origin.y + 12);
    await page.keyboard.down('Shift'); await page.mouse.move(origin.x + 1, origin.y + 1); await page.mouse.down();
    await page.mouse.move(origin.x + 60, origin.y + 30); await page.mouse.up(); await page.keyboard.up('Shift');
    await page.getByRole('button', { name: 'Save blueprint', exact: true }).click();
    await page.getByRole('textbox', { name: 'Blueprint name' }).fill('Pulse');
    await page.getByRole('dialog').getByRole('button', { name: 'Save blueprint', exact: true }).click();
    await expect(page.getByRole('heading', { name: 'Blueprints', exact: true })).toBeVisible();
    await page.getByRole('button', { name: 'Copy blueprint Pulse' }).click();
    await expect(page.getByRole('heading', { name: 'Blueprints', exact: true })).toBeVisible();
    await expect(page.locator('.blueprint-entry canvas')).toHaveAttribute('data-ready', 'true');
    await expect(page.locator('.blueprint-use span')).toContainText('2 x 1 | 1 cells');
    await page.screenshot({ path: buildPath('BlueprintLibraryCapture.png') });
    for (const [x, y, count] of [[3, 1, 2], [6, 3, 3]]) {
        await page.mouse.move(origin.x + x * 32 + 12, origin.y + y * 32 + 12); await page.keyboard.press('Control+v');
        await expect(page.locator('.canvas-context')).toContainText('Click to place');
        await page.mouse.click(origin.x + x * 32 + 12, origin.y + y * 32 + 12);
        await expect(page.locator('.workspace-status')).toContainText(`${count} cells`);
    }
    await expect(page.getByRole('textbox', { name: 'Clock hold', exact: true })).toHaveValue('9');
    await page.getByRole('button', { name: 'Rename blueprint Pulse' }).click();
    await page.getByRole('textbox', { name: 'Blueprint name' }).fill('Pulse pair');
    await page.getByRole('button', { name: 'Rename', exact: true }).click();
    await page.getByRole('button', { name: 'Delete blueprint Pulse pair' }).click();
    await expect(page.locator('.workspace-status')).toContainText('3 cells');
    await page.keyboard.press('Control+z'); await expect(page.getByRole('button', { name: 'Copy blueprint Pulse pair' })).toBeVisible();
    await page.keyboard.press('Control+z'); await expect(page.getByRole('button', { name: 'Copy blueprint Pulse' })).toBeVisible();
    await page.keyboard.press('Control+z'); await expect(page.locator('.workspace-status')).toContainText('2 cells');
    expect(errors).toEqual([]);
});

test('2D switches all previews and persists after reload while preserving a paste', async ({ page }) => {
    await ready(page); const origin = await center(page);
    await page.getByRole('button', { name: 'Or', exact: true }).click(); await page.mouse.click(origin.x + 12, origin.y + 12);
    await page.keyboard.down('Shift'); await page.mouse.move(origin.x + 1, origin.y + 1); await page.mouse.down();
    await page.mouse.move(origin.x + 30, origin.y + 30); await page.mouse.up(); await page.keyboard.up('Shift');
    await page.keyboard.press('Control+c');
    await expect(page.locator('.clipboard-thumbnail')).toHaveAttribute('data-ready', 'true');
    const firstPreview = await page.locator('.clipboard-thumbnail').evaluate(element => (element as HTMLCanvasElement).toDataURL());
    await page.mouse.move(origin.x + 110, origin.y + 12); await page.keyboard.press('Control+v');
    await page.getByText('2D', { exact: true }).click();
    await expect(page.locator('.canvas-context')).toContainText('Click to place');
    await expect(page.locator('.workspace-status')).toContainText('1 cells');
    await expect(page.locator('.clipboard-thumbnail')).toHaveAttribute('data-ready', 'true');
    expect(await page.locator('.clipboard-thumbnail').evaluate(element => (element as HTMLCanvasElement).toDataURL())).not.toBe(firstPreview);
    await page.screenshot({ path: buildPath('FlatPreviewCapture.png') });
    await page.reload(); await expect(page.getByRole('radio', { name: '2D', exact: true })).toBeChecked();
});

test('million-cell overview uses bounded aggregate objects and updates after editing', async ({ page }) => {
    test.setTimeout(120000);
    const errors: string[] = []; page.on('pageerror', error => errors.push(error.message));
    const start = Date.now(); await fixture(page, 'dense');
    await page.getByRole('button', { name: 'Fit board in view' }).click();
    await expect(page.getByTestId('board')).toHaveAttribute('data-lod', 'aggregate');
    await expect(page.getByTestId('board')).toHaveAttribute('data-color-ready', 'true', { timeout: 45000 });
    await expect(page.locator('.workspace-status')).toContainText('1,048,576 cells');
    const objects = Number(await page.getByTestId('board').getAttribute('data-render-objects'));
    expect(objects).toBeLessThan(200); expect(objects).toBeGreaterThan(0);
    const color = await sample(page); expect(Math.max(...color.slice(0, 3))).toBeGreaterThan(100);
    await page.screenshot({ path: buildPath('MillionCellOverviewCapture.png') });
    const origin = await center(page);
    const frames = await page.evaluate(async () => {
        const pointerMoveFrameMs: number[] = [], board = document.querySelector('[data-testid="board"]')!, rectangle = board.getBoundingClientRect();
        for (let i = 0; i < 20; i++) {
            const start = performance.now();
            board.dispatchEvent(new PointerEvent('pointermove', { bubbles: true, clientX: rectangle.x + rectangle.width / 2 + i, clientY: rectangle.y + rectangle.height / 2 }));
            await new Promise(requestAnimationFrame); pointerMoveFrameMs.push(performance.now() - start);
        }
        const mainThreadHeapBytes = (performance as unknown as { memory?: { usedJSHeapSize: number } }).memory?.usedJSHeapSize;
        return { pointerMoveFrameMs, mainThreadHeapBytes };
    });
    await expect(page.getByTestId('board')).toHaveAttribute('data-highlight-cells','32768');
    expect(Number(await page.getByTestId('board').getAttribute('data-highlight-objects'))).toBeLessThan(200);
    await writeFile(buildPath('RenderingMetrics.json'), JSON.stringify({ loadAndOverviewMs: Date.now() - start, objects, ...frames }, null, 2));
    await page.mouse.move(origin.x + 30, origin.y + 20); await page.mouse.down({ button: 'middle' });
    await page.mouse.move(origin.x - 60, origin.y + 40, { steps: 10 }); await page.mouse.up({ button: 'middle' });
    await expect(page.getByTestId('board')).toHaveAttribute('data-color-ready', 'true');
    await page.getByRole('button', { name: 'Fit board in view' }).click();
    await page.mouse.click(origin.x+12,origin.y+12);
    await expect(page.getByTestId('board')).toHaveAttribute('data-selection-cells','32768');
    expect(Number(await page.getByTestId('board').getAttribute('data-highlight-objects'))).toBeLessThan(200);
    await page.mouse.click(origin.x+12,origin.y+12,{button:'right'});
    await expect(page.locator('.workspace-status')).toContainText('1,048,576 cells');
    await page.keyboard.down('Shift');await page.mouse.click(origin.x+12,origin.y+12);await page.keyboard.up('Shift');
    await page.keyboard.press('x');
    await expect(page.locator('.workspace-status')).toContainText('1,048,575 cells');
    await page.keyboard.press('Control+z'); await expect(page.locator('.workspace-status')).toContainText('1,048,576 cells');
    await page.keyboard.press('Control+d');await page.getByText('2D', { exact: true }).click();
    await expect(page.getByTestId('board')).toHaveAttribute('data-color-ready', 'true');
    expect(await sample(page)).toEqual(color);
    expect(errors).toEqual([]);
});

test('large thumbnails, clipboard and placement previews use the same aggregate path', async ({ page }) => {
    await fixture(page, 'thumbnail');
    await page.getByRole('button', { name: 'Show blueprints' }).click();
    await expect(page.locator('.blueprint-entry canvas')).toHaveAttribute('data-ready', 'true');
    await page.getByRole('button', { name: 'Copy blueprint Large circuit' }).click();
    await page.getByRole('button', { name: 'Show clipboard' }).click();
    await expect(page.locator('.clipboard-thumbnail')).toHaveAttribute('data-ready', 'true');
    await page.getByRole('button', { name: 'Fit board in view' }).click();
    const origin = await center(page); await page.mouse.move(origin.x + 20, origin.y + 20); await page.keyboard.press('Control+v');
    await expect(page.locator('.canvas-context')).toContainText('Click to place');
    await settle(page);
    await expect(page.getByTestId('board')).toHaveAttribute('data-color-ready', 'true', { timeout: 15000 });
    const previewColors = await Promise.all([21, 26, 30, 35].map(x => sample(page, x, 45)));
    expect(Math.max(...previewColors.map(color => color[0]))).toBeGreaterThan(50);
    await page.screenshot({ path: buildPath('LargeClipboardPreviewCapture.png') });
    await page.mouse.click(origin.x + 20, origin.y + 20);
    await expect(page.locator('.workspace-status')).toContainText('32,768 cells');
    await expect(page.getByTestId('board')).toHaveAttribute('data-color-ready', 'true');
    await page.screenshot({ path: buildPath('LargePastedCapture.png') });
    for (let i = 0; i < 18; i++) await page.getByRole('button', { name: 'Zoom in', exact: true }).click();
    await expect(page.getByTestId('board')).toHaveAttribute('data-lod', 'color');
    await expect(page.getByTestId('board')).toHaveAttribute('data-color-ready', 'true');
    await page.screenshot({ path: buildPath('ColorOnlyCapture.png') });
    for (let i = 0; i < 20; i++) await page.getByRole('button', { name: 'Zoom in', exact: true }).click();
    await expect(page.getByTestId('board')).toHaveAttribute('data-lod', 'detail');
});

test('sparse overview queries occupied ancestors over a large signed coordinate span', async ({ page }) => {
    await fixture(page, 'sparse'); await page.getByRole('button', { name: 'Fit board in view' }).click();
    await expect(page.getByTestId('board')).toHaveAttribute('data-lod', 'aggregate');
    await expect(page.getByTestId('board')).toHaveAttribute('data-color-ready', 'true');
    const count = Number(await page.getByTestId('board').getAttribute('data-render-objects'));
    expect(count).toBeGreaterThan(0); expect(count).toBeLessThan(20);
    await page.screenshot({ path: buildPath('SparseOverviewCapture.png') });
});
