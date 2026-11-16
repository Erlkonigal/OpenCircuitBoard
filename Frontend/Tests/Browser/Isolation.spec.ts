import { test, expect, type Page } from '../BrowserTest';
import { buildPath } from '../Paths';
async function ready(page: Page) { await page.goto('/'); await expect(page.getByTestId('board')).toHaveAttribute('data-render-ready','true'); const r=(await page.getByTestId('board').boundingBox())!; return {x:r.x+r.width/2,y:r.y+r.height/2}; }
async function drag(page: Page, x:number,y:number,toX:number,toY:number,button:'left'|'right'='left') { await page.mouse.move(x,y); await page.mouse.down({button}); await page.mouse.move(toX,toY,{steps:6}); await page.mouse.up({button}); }
async function settle(page: Page) { await page.mouse.move(100,25); await page.evaluate(()=>new Promise<void>(resolve=>requestAnimationFrame(()=>requestAnimationFrame(()=>resolve())))); }

test('independent edges support drawing, erasing, undo, edge-only selection, perimeter copy and blueprints',async({page})=>{
    const errors:string[]=[];page.on('pageerror',e=>errors.push(e.message)); const c=await ready(page);
    await expect(page.getByRole('button',{name:'Mesh',exact:true})).toHaveCount(0);
    await page.getByLabel('Search components').fill('isolation');
    await expect(page.getByRole('button',{name:'Isolation',exact:true})).toBeVisible();
    await expect(page.getByText('No matching components',{exact:true})).toHaveCount(0);
    await page.getByLabel('Search components').fill('');
    await page.getByRole('button',{name:'Isolation',exact:true}).click();
    await drag(page,c.x+1,c.y,c.x+95,c.y); await expect(page.locator('.workspace-status')).toContainText('3 edges');
    await page.keyboard.press('Control+z'); await expect(page.locator('.workspace-status')).not.toContainText('edges'); await page.keyboard.press('Control+u');
    await drag(page,c.x+1,c.y,c.x+95,c.y,'right'); await expect(page.locator('.workspace-status')).not.toContainText('edges'); await page.keyboard.press('Control+z');
    await page.keyboard.down('Shift'); await drag(page,c.x+1,c.y+1,c.x+95,c.y+30); await page.keyboard.up('Shift');
    await expect(page.getByTestId('right-dock')).toContainText('3 edges');
    await drag(page,c.x+12,c.y+12,c.x+12,c.y+76);
    await expect(page.locator('.canvas-label')).toContainText('3 edges selected');
    await expect(page.locator('.workspace-status')).toContainText('3 edges');
    await page.keyboard.down('Shift'); await drag(page,c.x+1,c.y+1,c.x+95,c.y+30); await page.keyboard.up('Shift');
    await expect(page.locator('.canvas-label')).toContainText('Isolation:');
    await page.keyboard.down('Shift'); await drag(page,c.x+1,c.y+65,c.x+95,c.y+94); await page.keyboard.up('Shift');
    await expect(page.locator('.canvas-label')).toContainText('3 edges selected');
    await page.keyboard.press('Control+c'); await expect(page.locator('.clipboard-thumbnail')).toHaveAttribute('data-ready','true');
    await page.mouse.move(c.x+1,c.y+97);await page.keyboard.press('Control+v');await expect(page.locator('.canvas-context')).toContainText('Click to place');await page.mouse.click(c.x+1,c.y+97);
    await expect(page.locator('.workspace-status')).toContainText('6 edges');
    await page.getByRole('button',{name:'Save as blueprint',exact:true}).click();await page.getByLabel('Blueprint name').fill('Divider');await page.getByRole('dialog').getByRole('button',{name:'Save blueprint',exact:true}).click();await expect(page.getByRole('dialog')).toHaveCount(0);
    await expect(page.locator('.blueprint-entry canvas')).toHaveAttribute('data-ready','true');await settle(page);await page.screenshot({path:buildPath('IsolationBlueprintCapture.png')});
    await page.getByRole('button',{name:'Copy blueprint Divider'}).click();await page.mouse.move(c.x+1,c.y+161);await page.keyboard.press('Control+v');await page.mouse.click(c.x+1,c.y+161);await expect(page.locator('.workspace-status')).toContainText('9 edges');
    await page.keyboard.press('Delete');await expect(page.locator('.workspace-status')).toContainText('6 edges');await page.keyboard.press('Control+z');await expect(page.locator('.workspace-status')).toContainText('9 edges');
    expect(errors).toEqual([]);
});

test('latch dividers render in both modes and Trace variants are pure color in canvas and previews',async({page})=>{
    const c=await ready(page);await page.getByRole('button',{name:'Latch',exact:true}).click();
    for(const y of [0,1]) await drag(page,c.x+1,c.y+y*32+12,c.x+95,c.y+y*32+12);
    await page.getByRole('button',{name:'Isolation',exact:true}).click();await drag(page,c.x+1,c.y+32,c.x+95,c.y+32);
    const boundaryPixels = () => page.locator('canvas[aria-label="Circuit board"]').evaluate(element => {
        const canvas = element as HTMLCanvasElement, gl = canvas.getContext('webgl2')!;
        const scale = canvas.width / canvas.getBoundingClientRect().width;
        return [12,44,76].map(x => {
            const pixel = new Uint8Array(4);
            gl.readPixels(Math.floor(canvas.width / 2 + x * scale), canvas.height - 1 - Math.floor(canvas.height / 2 + 32 * scale), 1, 1, gl.RGBA, gl.UNSIGNED_BYTE, pixel);
            return [...pixel];
        });
    });
    for (const [mode, capture] of [['2.5D','IsolationCapture.png'],['2D','IsolationFlatCapture.png']]) {
        await page.getByText(mode,{exact:true}).click();await settle(page);
        const colors = await boundaryPixels();
        expect(colors).toEqual(Array.from({length:3},()=>[225,207,154,255]));
        await page.mouse.move(c.x+44,c.y+32);
        await page.evaluate(()=>new Promise<void>(resolve=>requestAnimationFrame(()=>requestAnimationFrame(()=>resolve()))));
        expect(await boundaryPixels()).toEqual(colors);
        await page.screenshot({path:buildPath(capture)});
    }
    await page.getByRole('button',{name:'Trace',exact:true}).click();
    for(const [i,id] of ['trace','traceRed','traceGreen','traceBlue','traceCyan','traceMagenta'].entries()){
        await page.getByRole('button',{name:id,exact:true}).click();await page.mouse.click(c.x+(i-3)*32+12,c.y+108);
    }
    await settle(page);
    const ranges=await page.locator('canvas[aria-label="Circuit board"]').evaluate(element=>{
        const canvas=element as HTMLCanvasElement,gl=canvas.getContext('webgl2')!,scale=canvas.width/canvas.getBoundingClientRect().width;
        return Array.from({length:6},(_,i)=>{const p=new Uint8Array(20*20*4);gl.readPixels(Math.floor(canvas.width/2+((i-3)*32+6)*scale),canvas.height-Math.floor(canvas.height/2+122*scale),Math.floor(20*scale),Math.floor(20*scale),gl.RGBA,gl.UNSIGNED_BYTE,p);return [0,1,2].map(channel=>{const values=[];for(let n=channel;n<p.length;n+=4)values.push(p[n]);return Math.max(...values)-Math.min(...values);});});
    });
    for(const range of ranges)expect(range).toEqual([0,0,0]);
    await page.keyboard.down('Shift');await drag(page,c.x-95,c.y+97,c.x+95,c.y+126);await page.keyboard.up('Shift');await page.keyboard.press('Control+c');await expect(page.locator('.clipboard-thumbnail')).toHaveAttribute('data-ready','true');
    await settle(page);await page.screenshot({path:buildPath('TraceColorOnlyCapture.png')});
});

test('large sparse boundaries remain chunked and are hidden in aggregate LOD',async({page})=>{
    await page.addInitScript(()=>{ (window as unknown as {__TAURI_INTERNALS__:unknown}).__TAURI_INTERNALS__={invoke:async(command:string)=>{if(command==='recentProjects')return ['Edges.ocb'];if(command!=='openProject')throw Error(command);const isolationEdges=[];for(let y=-512;y<512;y++)for(let x=-512;x<512;x++)isolationEdges.push({x,y,axis:'horizontal'});return {board:{selectedTool:'or',clockHoldTicks:1,latchInitialState:true,grid:{originX:-512,originY:-512,width:1024,height:1024},tiles:[],isolationEdges},blueprints:[]};}}; });
    await ready(page);await page.locator('.project-switcher').click();await page.getByRole('menuitem',{name:'Edges.ocb',exact:true}).click();await expect(page.locator('.workspace-status')).toContainText('1,048,576 edges',{timeout:45000});
    await expect(page.getByTestId('board')).toHaveAttribute('data-edit-tool','ink');
    expect(Number(await page.getByTestId('board').getAttribute('data-isolation-objects'))).toBeLessThan(16);
    await page.getByRole('button',{name:'Fit board in view'}).click();await expect(page.getByTestId('board')).toHaveAttribute('data-isolation-objects','0');await settle(page);await page.screenshot({path:buildPath('IsolationOverviewCapture.png')});
    await page.getByRole('button',{name:'Isolation',exact:true}).click();await expect(page.locator('.canvas-label')).toContainText('Zoom in');
});
