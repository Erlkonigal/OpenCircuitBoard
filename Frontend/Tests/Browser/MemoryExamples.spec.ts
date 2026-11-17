import { test, expect } from '../BrowserTest';
import { exampleProject } from '../ExampleArchive';
import { buildPath } from '../Paths';

for (const name of ['HelloWorld5x8', 'Ram16x8'] as const) {
    for (const mode of ['2D', '2.5D'] as const) {
        test(name + ' compact overview and storage detail in ' + mode, async ({ page }) => {
            const project = exampleProject(name), errors: string[] = [];
            page.on('pageerror', error => errors.push(error.message));
            await page.addInitScript(({ name, project }) => {
                (window as unknown as { __TAURI_INTERNALS__: unknown }).__TAURI_INTERNALS__ = { invoke: async (command: string) => {
                    if (command === 'recentProjects') return [name + '.ocb'];
                    if (command === 'openProject') return project;
                    throw Error('Unexpected example test IPC: ' + command);
                } };
            }, { name, project });
            await page.goto('/');
            const board = page.getByTestId('board');
            await expect(board).toHaveAttribute('data-render-ready', 'true');
            await page.locator('.project-switcher').click();
            await page.getByRole('menuitem', { name: name + '.ocb', exact: true }).click();
            await expect(page.locator('.workspace-status')).toContainText(project.board.tiles.length.toLocaleString('en-US') + ' cells');
            await page.getByText(mode, { exact: true }).click();
            await page.getByRole('button', { name: 'Fit board in view' }).click();
            await expect(board).toHaveAttribute('data-color-ready', 'true');
            expect(Number(await board.getAttribute('data-render-objects'))).toBeGreaterThan(0);
            await page.screenshot({ path: buildPath(name + '-' + mode + '-OverviewCapture.png') });
            // Anchor zoom at a storage cell, keeping the same physical circuit in view.
            const grid = project.board.grid;
            const target = name === 'Ram16x8' ? { x: -42, y: -112 } : { x: -289, y: -130 };
            const box = (await board.boundingBox())!;
            const pixels = Math.min(box.width / grid.width, box.height / grid.height);
            const x = box.x + box.width / 2 + (target.x - grid.originX - grid.width / 2) * pixels;
            const y = box.y + box.height / 2 + (target.y - grid.originY - grid.height / 2) * pixels;
            await page.keyboard.down('Space'); await page.mouse.move(x, y); await page.mouse.down();
            await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2, { steps: 4 });
            await page.mouse.up(); await page.keyboard.up('Space');
            await board.evaluate((element, point) => {
                for (let i = 0; i < 27; i++) element.dispatchEvent(new WheelEvent('wheel', { bubbles: true, cancelable: true,
                    clientX: point.x, clientY: point.y, deltaY: -100 }));
            }, { x: box.x + box.width / 2, y: box.y + box.height / 2 });
            await expect(board).toHaveAttribute('data-lod', 'detail');
            await expect(board).toHaveAttribute('data-color-ready', 'true');
            await page.screenshot({ path: buildPath(name + '-' + mode + '-StorageCapture.png') });
            await expect(page.locator('.error-toast')).toHaveCount(0);
            expect(errors).toEqual([]);
        });
    }
}
