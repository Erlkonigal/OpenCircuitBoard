import { test, expect, type Page } from '../BrowserTest';
import { buildPath } from '../Paths';

async function ready(page: Page) {
    await page.goto('/');
    await expect(page.getByTestId('board')).toHaveAttribute('data-render-ready', 'true');
    const box = (await page.getByTestId('board').boundingBox())!;
    return { x: box.x + box.width / 2, y: box.y + box.height / 2 };
}
async function settle(page: Page) {
    await page.mouse.move(100, 25);
    await page.evaluate(() => new Promise<void>(resolve => requestAnimationFrame(() => requestAnimationFrame(() => resolve()))));
}

test('direction pins rotate with Switch and survive history, clipboard and both display modes', async ({ page }) => {
    const center = await ready(page);
    await page.getByRole('button', { name: 'Switch', exact: true }).click();
    await page.mouse.click(center.x + 12, center.y + 12);
    await page.keyboard.press('v');
    await page.mouse.click(center.x + 12, center.y + 12);
    const direction = page.locator('[aria-label="Direction"]');
    await expect(direction.locator('input[value="0"]')).toBeChecked();
    await settle(page);
    const pins = () => page.locator('canvas[aria-label="Circuit board"]').evaluate(element => {
        const canvas = element as HTMLCanvasElement, gl = canvas.getContext('webgl2')!;
        const scale = canvas.width / canvas.getBoundingClientRect().width;
        return [[16, 1], [31, 16], [16, 31]].map(([x, y]) => {
            const pixel = new Uint8Array(4);
            gl.readPixels(Math.floor(canvas.width / 2 + x * scale), canvas.height - 1 - Math.floor(canvas.height / 2 + y * scale), 1, 1, gl.RGBA, gl.UNSIGNED_BYTE, pixel);
            return [...pixel];
        });
    });
    const before = await pins();
    await page.getByTestId('board').focus(); await page.keyboard.press('r');
    await expect(direction.locator('input[value="1"]')).toBeChecked();
    await settle(page); expect(await pins()).not.toEqual(before);
    await page.screenshot({ path: buildPath('SwitchDirectionCapture.png') });
    await page.getByTestId('board').focus(); await page.keyboard.press('Control+z');
    await expect(direction.locator('input[value="0"]')).toBeChecked();
    await settle(page); expect(await pins()).toEqual(before);
    await page.getByTestId('board').focus(); await page.keyboard.press('Control+Shift+z');
    await page.keyboard.press('Control+c');
    await expect(page.locator('.clipboard-thumbnail')).toHaveAttribute('data-ready', 'true');
    for (const mode of ['2D', '2.5D']) {
        await page.getByText(mode, { exact: true }).click();
        await page.getByTestId('board').focus();
        await page.mouse.move(center.x + 4 * 32 + 12, center.y + 12); await page.keyboard.press('Control+v');
        await expect(page.getByTestId('board')).toHaveAttribute('data-color-ready', 'true');
        await page.screenshot({ path: buildPath(mode === '2D' ? 'SwitchFlatPreviewCapture.png' : 'SwitchDepthPreviewCapture.png') });
        await page.keyboard.press('q');
    }
    await page.getByTestId('board').focus(); await page.keyboard.press('Shift+r');
    await expect(direction.locator('input[value="0"]')).toBeChecked();
});

test('Trace sources and undriven defaults stay separate from Clock settings and Cross color joins', async ({ page }) => {
    const center = await ready(page);
    await page.getByRole('button', { name: 'Trace', exact: true }).click();
    await page.locator('[aria-label="Fixed drive"]').getByText('0', { exact: true }).click();
    await page.locator('[aria-label="Undriven default"]').getByText('1', { exact: true }).click();
    await page.mouse.click(center.x + 12, center.y + 12);
    await page.keyboard.press('v'); await page.mouse.click(center.x + 12, center.y + 12);
    await expect(page.locator('[aria-label="Fixed drive"] input[value="0"]')).toBeChecked();
    await expect(page.locator('[aria-label="Undriven default"] input[value="1"]')).toBeChecked();
    await page.screenshot({ path: buildPath('TraceSourceSettingsCapture.png') });
    await page.getByRole('button', { name: 'Clear selection' }).click();
    await page.getByRole('button', { name: 'Clock', exact: true }).click();
    await page.getByLabel('Clock hold', { exact: true }).fill('7');
    await page.mouse.click(center.x + 76, center.y + 12);
    await page.keyboard.press('v'); await page.mouse.click(center.x + 76, center.y + 12);
    await expect(page.getByLabel('Clock hold', { exact: true })).toHaveValue('7');
    await page.getByRole('button', { name: 'Clear selection' }).click();
    await page.getByRole('button', { name: 'Cross', exact: true }).click();
    await page.getByRole('button', { name: 'Join traceRed', exact: true }).click();
    await page.mouse.click(center.x + 140, center.y + 12);
    await page.keyboard.press('v'); await page.mouse.click(center.x + 140, center.y + 12);
    await expect(page.getByRole('button', { name: 'Join traceRed', exact: true })).toHaveAttribute('aria-pressed', 'true');
    await page.getByRole('button', { name: 'Join traceWhite', exact: true }).click();
    await page.getByTestId('board').focus(); await page.keyboard.press('Control+z');
    await expect(page.getByRole('button', { name: 'Join traceWhite', exact: true })).toHaveAttribute('aria-pressed', 'false');
    await page.keyboard.press('Control+Shift+z');
    await expect(page.getByRole('button', { name: 'Join traceWhite', exact: true })).toHaveAttribute('aria-pressed', 'true');
    await settle(page); await page.screenshot({ path: buildPath('CrossJoinSettingsCapture.png') });
});

test('joined devices show free contacts only on their perimeter and hide connected contacts until undo', async ({ page }) => {
    const center = await ready(page);
    await page.getByRole('button', { name: 'Switch', exact: true }).click();
    await page.keyboard.down('Shift');
    await page.mouse.move(center.x + 12, center.y + 12); await page.mouse.down();
    await page.mouse.move(center.x + 76, center.y + 76, { steps: 8 }); await page.mouse.up();
    await page.keyboard.up('Shift');
    await expect(page.getByTestId('board')).toHaveAttribute('data-component-count', '1');
    const pixels = () => page.locator('canvas[aria-label="Circuit board"]').evaluate(element => {
        const canvas = element as HTMLCanvasElement, gl = canvas.getContext('webgl2')!;
        const scale = canvas.width / canvas.getBoundingClientRect().width;
        return [1.5, 33.5].map(x => {
            const pixel = new Uint8Array(4);
            gl.readPixels(Math.floor(canvas.width / 2 + x * scale), canvas.height - 1 - Math.floor(canvas.height / 2 + 48 * scale), 1, 1, gl.RGBA, gl.UNSIGNED_BYTE, pixel);
            return [...pixel];
        });
    });
    for (const mode of ['2D', '2.5D']) {
        await page.getByText(mode, { exact: true }).click(); await settle(page);
        const free = await pixels(); expect(free[0]).not.toEqual(free[1]);
        await page.screenshot({ path: buildPath(mode === '2D' ? 'ComponentFreePinsFlatCapture.png' : 'ComponentFreePinsDepthCapture.png') });
        await page.getByRole('button', { name: 'Trace', exact: true }).click();
        await page.mouse.click(center.x - 20, center.y + 44); await settle(page);
        const connected = await pixels(); expect(connected[0]).toEqual(connected[1]);
        await page.screenshot({ path: buildPath(mode === '2D' ? 'ComponentConnectedPinsFlatCapture.png' : 'ComponentConnectedPinsDepthCapture.png') });
        await page.getByTestId('board').focus(); await page.keyboard.press('Control+z'); await settle(page);
        expect(await pixels()).toEqual(free);
    }
});
