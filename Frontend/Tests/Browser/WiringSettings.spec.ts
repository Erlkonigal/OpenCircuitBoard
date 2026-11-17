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

test('Switch icons rotate without pin dots and survive history, clipboard and both display modes', async ({ page }) => {
    const center = await ready(page);
    await page.getByRole('button', { name: 'Switch', exact: true }).click();
    await page.mouse.click(center.x + 12, center.y + 12);
    await page.keyboard.press('v');
    await page.mouse.click(center.x + 12, center.y + 12);
    const direction = page.locator('[aria-label="Direction"]');
    await expect(direction.locator('input[value="0"]')).toBeChecked();
    await settle(page);
    const icon = () => page.locator('canvas[aria-label="Circuit board"]').evaluate(element => {
        const canvas = element as HTMLCanvasElement, gl = canvas.getContext('webgl2')!;
        const scale = canvas.width / canvas.getBoundingClientRect().width;
        const size = Math.round(24 * scale), pixels = new Uint8Array(size * size * 4);
        gl.readPixels(Math.floor(canvas.width / 2 + 4 * scale), canvas.height - Math.floor(canvas.height / 2 + 28 * scale), size, size, gl.RGBA, gl.UNSIGNED_BYTE, pixels);
        return [...pixels];
    });
    const before = await icon();
    await page.getByTestId('board').focus(); await page.keyboard.press('r');
    await expect(direction.locator('input[value="1"]')).toBeChecked();
    await settle(page); expect(await icon()).not.toEqual(before);
    await page.screenshot({ path: buildPath('SwitchDirectionCapture.png') });
    await page.getByTestId('board').focus(); await page.keyboard.press('Control+z');
    await expect(direction.locator('input[value="0"]')).toBeChecked();
    await settle(page); expect(await icon()).toEqual(before);
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

test('Trace has no drive controls and Clock and Cross settings remain editable', async ({ page }) => {
    const center = await ready(page);
    await page.getByRole('button', { name: 'Trace', exact: true }).click();
    await page.mouse.click(center.x + 12, center.y + 12);
    await page.keyboard.press('v'); await page.mouse.click(center.x + 12, center.y + 12);
    await expect(page.getByLabel('Fixed drive')).toHaveCount(0);
    await expect(page.getByLabel('Undriven default')).toHaveCount(0);
    await page.screenshot({ path: buildPath('PassiveTraceSettingsCapture.png') });
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

test('joined devices use icons without input/output dots in either display mode', async ({ page }) => {
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
        const free = await pixels(); expect(free[0]).toEqual(free[1]);
        await page.screenshot({ path: buildPath(mode === '2D' ? 'ComponentIconsFlatCapture.png' : 'ComponentIconsDepthCapture.png') });
        await page.getByRole('button', { name: 'Trace', exact: true }).click();
        await page.mouse.click(center.x - 20, center.y + 44); await settle(page);
        const connected = await pixels(); expect(connected[0]).toEqual(connected[1]);
        await page.screenshot({ path: buildPath(mode === '2D' ? 'ComponentIconsConnectedFlatCapture.png' : 'ComponentIconsConnectedDepthCapture.png') });
        await page.getByTestId('board').focus(); await page.keyboard.press('Control+z'); await settle(page);
        expect(await pixels()).toEqual(free);
    }
});

test('Button icons have no output stub and preserve rotation and the off initial state', async ({ page }) => {
    const center = await ready(page);
    await expect(page.getByRole('button', { name: 'Button', exact: true })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Latch', exact: true })).toHaveCount(0);
    await page.getByRole('button', { name: 'Button', exact: true }).click();
    await page.getByText('Off', { exact: true }).click();
    await page.mouse.click(center.x + 12, center.y + 12);
    await page.keyboard.press('v'); await page.mouse.click(center.x + 12, center.y + 12);
    await expect(page.getByTestId('right-dock')).toContainText('Output only');
    const icon = () => page.locator('canvas[aria-label="Circuit board"]').evaluate(element => {
        const canvas = element as HTMLCanvasElement, gl = canvas.getContext('webgl2')!;
        const scale = canvas.width / canvas.getBoundingClientRect().width;
        return [[30, 16], [16, 30]].map(([x, y]) => {
            const pixel = new Uint8Array(4);
            gl.readPixels(Math.floor(canvas.width / 2 + x * scale), canvas.height - 1 - Math.floor(canvas.height / 2 + y * scale), 1, 1, gl.RGBA, gl.UNSIGNED_BYTE, pixel);
            return [...pixel];
        });
    });
    await settle(page); const before = await icon();
    expect(before[0]).toEqual(before[1]);
    await page.getByTestId('board').focus(); await page.keyboard.press('r'); await settle(page);
    expect(await icon()).toEqual(before);
    await expect(page.locator('.active-component-symbol .tool-glyph')).toHaveAttribute('style', /rotate\(90deg\)/);
    await page.screenshot({ path: buildPath('LatchIconDirectionCapture.png') });
    await page.getByTestId('board').focus(); await page.keyboard.press('Control+z'); await settle(page);
    expect(await icon()).toEqual(before);
    await page.getByText('On', { exact: true }).click(); await settle(page);
    const powered = await icon(); expect(powered[0]).toEqual(powered[1]);
    const symbol = () => page.locator('canvas[aria-label="Circuit board"]').evaluate(element => {
        const canvas = element as HTMLCanvasElement, gl = canvas.getContext('webgl2')!;
        const scale = canvas.width / canvas.getBoundingClientRect().width;
        const size = Math.round(24 * scale), pixels = new Uint8Array(size * size * 4);
        gl.readPixels(Math.floor(canvas.width / 2 + 4 * scale), canvas.height - Math.floor(canvas.height / 2 + 28 * scale), size, size, gl.RGBA, gl.UNSIGNED_BYTE, pixels);
        return [...pixels];
    });
    const upright = await symbol();
    await page.getByTestId('board').focus(); await page.keyboard.press('r'); await settle(page);
    expect(await symbol()).not.toEqual(upright);
    await page.screenshot({ path: buildPath('ButtonOnIconCapture.png') });
});
