import { test, expect, type Page } from '../BrowserTest';
import { buildPath } from '../Paths';

type Point = { x: number; y: number };
async function center(page: Page) {
    const box = (await page.getByTestId('board').boundingBox())!;
    return { x: box.x + box.width / 2, y: box.y + box.height / 2 };
}
async function settle(page: Page) {
    await page.evaluate(() => new Promise<void>(resolve => requestAnimationFrame(() => requestAnimationFrame(() => resolve()))));
}
async function cleanCursor(page: Page) {
    await page.mouse.move(100, 25);
    await settle(page);
}
async function paint(page: Page, cells: Point[], tool = 'Or') {
    await page.getByRole('button', { name: tool, exact: true }).click();
    const origin = await center(page);
    for (const cell of cells)
        await page.mouse.click(origin.x + cell.x * 32 + 12, origin.y + cell.y * 32 + 12);
    await cleanCursor(page);
}
async function pixels(page: Page, points: Point[]) {
    await settle(page);
    return page.locator('canvas[aria-label="Circuit board"]').evaluate((element, points) => {
        const canvas = element as HTMLCanvasElement;
        const gl = canvas.getContext('webgl2') || canvas.getContext('webgl');
        if (!gl) throw Error('WebGL context unavailable');
        const scale = canvas.width / canvas.getBoundingClientRect().width;
        return points.map(point => {
            const data = new Uint8Array(4);
            const x = Math.floor(canvas.width / 2 + point.x * .5 * scale);
            const y = canvas.height - 1 - Math.floor(canvas.height / 2 + point.y * .5 * scale);
            gl.readPixels(x, y, 1, 1, gl.RGBA, gl.UNSIGNED_BYTE, data);
            return [...data].slice(0, 3);
        });
    }, points);
}
const brightness = (rgb: number[]) => rgb.reduce((sum, channel) => sum + channel, 0);
function expectUniform(samples: number[][], tolerance = 3) {
    for (const channel of [0, 1, 2]) {
        const values = samples.map(sample => sample[channel]);
        expect(Math.max(...values) - Math.min(...values)).toBeLessThanOrEqual(tolerance);
    }
}
async function image(page: Page) {
    await cleanCursor(page);
    return page.locator('canvas[aria-label="Circuit board"]').evaluate(element => (element as HTMLCanvasElement).toDataURL());
}

const PageErrors = new WeakMap<Page, string[]>();
test.beforeEach(async ({ page }) => {
    const errors: string[] = [];
    PageErrors.set(page, errors);
    page.on('pageerror', error => errors.push(error.message));
    await page.goto('/');
    await expect(page.getByTestId('board')).toHaveAttribute('data-render-ready', 'true');
});
test.afterEach(async ({ page }) => { expect(PageErrors.get(page)).toEqual([]); });

test('continuous horizontal sides and directional shadows have no per-cell seams', async ({ page }) => {
    const shadowPoints = [90, 98, 112].map(y => ({ x: 16, y }));
    const above = { x: 16, y: -12 };
    const seams = [-112, -64, -16, 0, 32, 64, 112].map(x => ({ x, y: 94 }));
    const before = await pixels(page, [...shadowPoints, above, ...seams]);
    const row = Array.from({ length: 6 }, (_, i) => ({ x: i - 3, y: 0 }));
    await paint(page, [...row].reverse());
    const samples = await pixels(page, row.slice(1, -1).flatMap(cell => [8, 24, 48].map(x => ({ x: cell.x * 64 + x, y: 74 }))));
    expectUniform(samples);
    const gradient = await pixels(page, [{ x: 16, y: 68 }, { x: 16, y: 82 }, { x: -196, y: 40 }, { x: -212, y: 40 }]);
    expect(brightness(gradient[0]) - brightness(gradient[1])).toBeGreaterThan(15);
    expect(brightness(gradient[2]) - brightness(gradient[3])).toBeGreaterThan(15);
    const after = await pixels(page, [...shadowPoints, above, ...seams]);
    const darkness = before.map((value, i) => brightness(value) - brightness(after[i]));
    expect(darkness[0]).toBeGreaterThan(3);
    expect(darkness[0]).toBeGreaterThan(darkness[1]);
    expect(darkness[1]).toBeGreaterThanOrEqual(darkness[2]);
    expect(Math.abs(darkness[2])).toBeLessThanOrEqual(1);
    expect(Math.abs(darkness[3])).toBeLessThanOrEqual(1);
    const seamDarkness = darkness.slice(4);
    expect(Math.max(...seamDarkness) - Math.min(...seamDarkness)).toBeLessThanOrEqual(3);
    await page.screenshot({ path: buildPath('ContinuousTilesCapture.png') });
    const original = await image(page);
    for (let i = 0; i < row.length; i++) await page.keyboard.press('Control+z');
    await paint(page, row);
    expect(await image(page)).toBe(original);
});

test('rectangles, holes, turns and diagonal contacts render independently of drawing order', async ({ page }) => {
    const rectangle = Array.from({ length: 9 }, (_, i) => ({ x: i % 3 - 5, y: Math.floor(i / 3) - 3 }));
    const ring = Array.from({ length: 9 }, (_, i) => ({ x: i % 3 + 1, y: Math.floor(i / 3) - 3 })).filter(p => p.x !== 2 || p.y !== -2);
    const turn = [{ x: -5, y: 2 }, { x: -5, y: 3 }, { x: -5, y: 4 }, { x: -4, y: 4 }, { x: -3, y: 4 }];
    const diagonal = [{ x: 1, y: 2 }, { x: 2, y: 3 }, { x: 3, y: 4 }];
    const cells = [...rectangle, ...ring, ...turn, ...diagonal];
    await paint(page, cells);
    expectUniform(await pixels(page, [-3, -2, -1].map(y => ({ x: -332, y: y * 64 + 32 }))));
    expectUniform(await pixels(page, [-5, -4, -3].flatMap(x => [12, 40].map(offset => ({ x: x * 64 + offset, y: 10 })))));
    const hole = await pixels(page, [{ x: 148, y: -88 }, { x: 180, y: -88 }]);
    expect(brightness(hole[1]) - brightness(hole[0])).toBeGreaterThan(80);
    await page.screenshot({ path: buildPath('TileShapesCapture.png') });
    const original = await image(page);
    const origin = await center(page);
    await page.keyboard.press('v');await page.mouse.click(origin.x - 4 * 32 + 12, origin.y + 12 - 3 * 32);await page.keyboard.press('x');
    expect(await image(page)).not.toBe(original);
    await page.keyboard.press('Control+z');await page.keyboard.press('Control+d');
    expect(await image(page)).toBe(original);
    for (let i = 0; i < cells.length; i++) await page.keyboard.press('Control+z');
    await paint(page, [...cells].reverse());
    expect(await image(page)).toBe(original);
});

test('mixed off materials and clipboard ghosts stay opaque within each group and join on placement', async ({ page }) => {
    await paint(page, [{ x: -2, y: 0 }], 'Clock');
    await page.getByRole('button', { name: 'Latch', exact: true }).click();
    await page.getByText('Off', { exact: true }).click();
    await paint(page, [{ x: -1, y: 0 }, { x: 0, y: 0 }], 'Latch');
    expectUniform(await pixels(page, [-1, 0].flatMap(x => [8, 24, 48].map(offset => ({ x: x * 64 + offset, y: 74 })))));
    await page.screenshot({ path: buildPath('MixedTileStatesCapture.png') });
    const origin = await center(page);
    await page.keyboard.press('v');
    await page.keyboard.down('Shift');
    await page.mouse.move(origin.x - 63, origin.y + 1);
    await page.mouse.down();
    await page.mouse.move(origin.x + 31, origin.y + 31, { steps: 6 });
    await page.mouse.up();
    await page.keyboard.up('Shift');
    await page.keyboard.press('Control+c');
    await page.mouse.move(origin.x - 64 + 12, origin.y + 32 + 12);
    await page.keyboard.press('Control+v');
    await expect(page.locator('.canvas-context')).toContainText('Click to place');
    await cleanCursor(page);
    const ghost = await pixels(page, [{ x: -124, y: 68 }, { x: -60, y: 68 }, { x: 4, y: 68 }]);
    expect(ghost[0][0]).toBeGreaterThan(60);
    expectUniform(ghost.slice(1));
    await page.screenshot({ path: buildPath('JoinedPreviewCapture.png') });
    const invalid = { x: origin.x - 64 + 12, y: origin.y + 12 };
    await page.mouse.move(invalid.x, invalid.y);
    await settle(page);
    await page.screenshot({ path: buildPath('InvalidPreviewCapture.png') });
    await page.mouse.move(origin.x - 64 + 12, origin.y + 32 + 12);
    await page.mouse.click(origin.x - 64 + 12, origin.y + 32 + 12);
    await expect(page.locator('.workspace-status')).toContainText('6 cells');
    await page.getByRole('button', { name: 'Clear selection', exact: true }).click();
    await cleanCursor(page);
    expectUniform(await pixels(page, [-1, 0].flatMap(x => [8, 24, 48].map(offset => ({ x: x * 64 + offset, y: 138 })))));
    await page.screenshot({ path: buildPath('JoinedTilesCapture.png') });
    await page.keyboard.press('v');
    await page.keyboard.down('Shift');
    await page.mouse.move(origin.x - 63, origin.y + 1);
    await page.mouse.down();
    await page.mouse.move(origin.x + 31, origin.y + 63, { steps: 6 });
    await page.mouse.up();
    await page.keyboard.up('Shift');
    await page.mouse.move(origin.x - 52, origin.y + 12);
    await page.mouse.down();
    await page.mouse.move(origin.x + 76, origin.y + 108, { steps: 8 });
    await settle(page);
    await page.screenshot({ path: buildPath('MovingTilesCapture.png') });
    const movedGhost = await pixels(page, [{ x: 132, y: 196 }, { x: 196, y: 196 }]);
    expect(movedGhost[0][0]).toBeGreaterThan(60);
    expect(movedGhost[0][0]).toBeGreaterThan(movedGhost[1][0] + 30);
    await page.mouse.up();
    await expect(page.locator('.workspace-status')).toContainText('6 cells');
    await page.keyboard.press('Control+z');
    await page.getByRole('button', { name: 'Zoom in', exact: true }).click();
    await page.getByRole('button', { name: 'Fit board in view', exact: true }).click();
    await expect(page.getByTestId('board')).not.toHaveAttribute('data-render-error');
    await page.screenshot({ path: buildPath('TileZoomCapture.png') });
});
