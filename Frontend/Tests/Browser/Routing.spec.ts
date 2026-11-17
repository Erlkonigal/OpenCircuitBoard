import { test, expect } from '../BrowserTest';
import { routingProject } from '../Fixtures/Routing';
import { buildPath } from '../Paths';
test('renders eight Trace colors, a shared Bus and Cross in both modes and clipboard previews', async ({page}) => {
    await page.addInitScript(project => {
        (window as unknown as {__TAURI_INTERNALS__:unknown}).__TAURI_INTERNALS__={invoke:async(command:string)=>{
            if(command==='recentProjects') return ['Routing.ocb'];
            if(command==='openProject') return project;
            throw Error(command);
        }};
    }, routingProject());
    await page.goto('/'); await expect(page.getByTestId('board')).toHaveAttribute('data-render-ready','true');
    await page.locator('.project-switcher').click(); await page.getByRole('menuitem',{name:'Routing.ocb',exact:true}).click();
    await page.getByTestId('board').focus(); await page.keyboard.press('Control+a'); await page.keyboard.press('Control+c');
    await expect(page.locator('.clipboard-thumbnail')).toHaveAttribute('data-ready','true');
    const box=(await page.getByTestId('board').boundingBox())!;
    for(const mode of ['2D','2.5D']) {
        await page.getByText(mode,{exact:true}).click();
        await page.getByTestId('board').focus();
        await page.mouse.move(box.x+box.width/2+4*32,box.y+box.height/2-7*32);
        await page.keyboard.press('Control+v');
        await expect(page.locator('.canvas-context')).toContainText('Click to place');
        await expect(page.getByTestId('board')).toHaveAttribute('data-color-ready','true');
        await page.screenshot({path:buildPath('Routing'+(mode==='2D'?'Flat':'Depth')+'PreviewCapture.png')});
        await page.keyboard.press('q'); await page.keyboard.press('Control+d'); await page.mouse.move(100,25);
        const colors=await page.locator('canvas[aria-label="Circuit board"]').evaluate(element=>{
            const canvas=element as HTMLCanvasElement,gl=canvas.getContext('webgl2')!;
            const scale=canvas.width/canvas.getBoundingClientRect().width;
            return Array.from({length:8},(_,lane)=>{
                const p=new Uint8Array(4);gl.readPixels(Math.floor(canvas.width/2+(-5*32+3)*scale),canvas.height-1-Math.floor(canvas.height/2+((-7+lane*2)*32+3)*scale),1,1,gl.RGBA,gl.UNSIGNED_BYTE,p);return [...p].slice(0,3).join(',');
            });
        });
        expect(new Set(colors).size).toBe(8);
        await page.screenshot({path:buildPath('Routing'+(mode==='2D'?'Flat':'Depth')+'Capture.png')});
    }
});
