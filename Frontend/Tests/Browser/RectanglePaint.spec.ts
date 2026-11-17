import { test, expect, type Page } from '../BrowserTest';
import { buildPath } from '../Paths';
async function ready(page: Page) {
    await page.goto('/'); await expect(page.getByTestId('board')).toHaveAttribute('data-render-ready', 'true');
    const b = (await page.getByTestId('board').boundingBox())!; return { x: b.x + b.width / 2, y: b.y + b.height / 2 };
}
async function drag(page: Page, x: number, y: number, endX: number, endY: number) {
    await page.mouse.move(x, y); await page.mouse.down(); await page.mouse.move(endX, endY, { steps: 4 }); await page.mouse.up();
}
test('Draw rectangle previews shrink, commit once and remain independent before Pointer marquee and group move', async ({ page }) => {
    const c = await ready(page), board = page.getByTestId('board'); await page.getByRole('button', { name: 'Clock', exact: true }).click();
    await page.keyboard.down('Shift'); await page.mouse.move(c.x + 76, c.y + 76); await page.mouse.down();
    await page.mouse.move(c.x - 20, c.y - 20); await expect(board).toHaveAttribute('data-rectangle-cells', '16');
    await expect(page.locator('.workspace-status')).toContainText('0 cells'); await expect(board).toHaveAttribute('data-gesture', 'rectanglePaint');
    await expect(page.getByRole('heading', { name: 'Start with a spark.' })).toHaveCount(0);
    await page.screenshot({ path: buildPath('RectanglePaintPreviewCapture.png') });
    await page.mouse.move(c.x + 44, c.y + 44); await expect(board).toHaveAttribute('data-rectangle-cells', '4');
    await page.mouse.up(); await page.keyboard.up('Shift'); await expect(page.locator('.workspace-status')).toContainText('4 cells');
    await expect(board).toHaveAttribute('data-edit-tool', 'draw'); await expect(board).toHaveAttribute('data-component-count', '1');
    await page.keyboard.down('Shift'); await page.mouse.click(c.x + 108, c.y + 44); await page.keyboard.up('Shift');
    await expect(board).toHaveAttribute('data-component-count', '2'); await expect(page.locator('.workspace-status')).toContainText('5 cells');
    await page.keyboard.press('v'); await page.mouse.move(c.x + 44, c.y + 44); await page.mouse.down(); await page.mouse.move(c.x + 108, c.y + 76);
    await expect(board).toHaveAttribute('data-gesture', 'marquee'); await page.screenshot({ path: buildPath('OccupiedStartMarqueeCapture.png') }); await page.mouse.up();
    await expect(board).toHaveAttribute('data-selection-cells', '5'); await expect(board).toHaveAttribute('data-component-count', '2');
    await drag(page, c.x + 44, c.y + 44, c.x - 52, c.y + 76); await expect(board).toHaveAttribute('data-selection-cells', '5');
    await page.screenshot({ path: buildPath('RectangleGroupMoveCapture.png') });
    await page.keyboard.press('Control+z'); await expect(board).toHaveAttribute('data-selection-cells', '5');
    await page.keyboard.press('Control+z'); await expect(page.locator('.workspace-status')).toContainText('4 cells');
    await page.keyboard.press('Control+z'); await expect(page.locator('.workspace-status')).toContainText('0 cells');
    await page.keyboard.press('Control+Shift+z'); await expect(page.locator('.workspace-status')).toContainText('4 cells');
    await expect(board).not.toHaveAttribute('data-render-error');
});
test('rectangle previews cancel on undo, pointer cancellation, window blur and tool changes', async ({ page }) => {
    const c = await ready(page), board = page.getByTestId('board');
    for (const action of ['undo', 'pointercancel', 'blur', 'tool']) {
        await page.getByRole('button', { name: 'Button', exact: true }).click(); await page.keyboard.down('Shift');
        await page.mouse.move(c.x + 12, c.y + 12); await page.mouse.down(); await page.mouse.move(c.x + 108, c.y + 76);
        await expect(board).toHaveAttribute('data-rectangle-cells', '12');
        await page.keyboard.up('Shift'); // The gesture remains rectangular; Ctrl+Z must not become Ctrl+Shift+Z.
        if (action === 'undo') await page.keyboard.press('Control+z');
        if (action === 'pointercancel') await board.dispatchEvent('pointercancel');
        if (action === 'blur') await page.evaluate(() => window.dispatchEvent(new Event('blur')));
        if (action === 'tool') await page.keyboard.press('v');
        await page.mouse.up(); await page.keyboard.up('Shift');
        await expect(board).toHaveAttribute('data-rectangle-cells', '0'); await expect(board).toHaveAttribute('data-gesture', 'idle');
        await expect(page.locator('.workspace-status')).toContainText('0 cells');
    }
});
test('a million-cell rectangle preview stays lightweight and leaves an empty document on cancellation', async ({ page }) => {
    await page.addInitScript(() => {
        (window as unknown as { __TAURI_INTERNALS__: unknown }).__TAURI_INTERNALS__ = { invoke: async (command: string) => {
            if (command === 'recentProjects') return ['EmptyLarge.ocb']; if (command !== 'openProject') throw Error(command);
            return { board: { circuitModel: 'booleanSwitch', selectedTool: 'trace', clockHoldTicks: 1, latchInitialState: true, grid: { originX: -1024, originY: -1024, width: 2048, height: 2048 }, tiles: [] }, blueprints: [] };
        } };
    });
    await ready(page); const board = page.getByTestId('board');
    await page.locator('.project-switcher').click(); await page.getByRole('menuitem', { name: 'EmptyLarge.ocb', exact: true }).click();
    await expect(page.getByRole('menu')).toBeHidden(); // The exit animation must not intercept the upper-left drag origin.
    await expect(page.locator('.workspace-status')).toContainText('2048 x 2048');
    await page.getByRole('button', { name: 'Fit board in view', exact: true }).click(); await board.focus(); await page.keyboard.press('b');
    await expect(board).toHaveAttribute('data-edit-tool', 'draw');
    const b = (await board.boundingBox())!, c = { x: b.x + b.width / 2, y: b.y + b.height / 2 };
    const px = Math.min(b.width, b.height) / 2048;
    await page.keyboard.down('Shift'); await page.mouse.move(c.x - 520 * px, c.y - 520 * px); await page.mouse.down();
    await expect(board).toHaveAttribute('data-gesture', 'rectanglePaint');
    await page.mouse.move(c.x + 520 * px, c.y + 520 * px, { steps: 8 });
    await expect.poll(async () => Number(await board.getAttribute('data-rectangle-cells'))).toBeGreaterThan(1000000);
    expect(Number(await board.getAttribute('data-render-objects'))).toBeLessThan(20);
    await expect(page.locator('.workspace-status')).toContainText('0 cells'); await page.screenshot({ path: buildPath('MillionCellRectanglePreviewCapture.png') });
    await page.keyboard.up('Shift'); await page.keyboard.press('q'); await page.mouse.up(); await expect(board).toHaveAttribute('data-rectangle-cells', '0');
    await expect(page.locator('.workspace-status')).toContainText('0 cells'); await expect(board).not.toHaveAttribute('data-render-error');
});
