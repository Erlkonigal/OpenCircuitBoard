import { test, expect, type Page } from '../BrowserTest';
import { buildPath } from '../Paths';
async function ready(page:Page) {
    await page.goto('/');await expect(page.getByTestId('board')).toHaveAttribute('data-render-ready','true');
    const r=(await page.getByTestId('board').boundingBox())!;return {x:r.x+r.width/2,y:r.y+r.height/2};
}
async function drag(page:Page,x:number,y:number,ex:number,ey:number) {
    await page.mouse.move(x,y);await page.mouse.down();await page.mouse.move(ex,ey,{steps:12});await page.mouse.up();
}
async function hoverId(page:Page,x:number,y:number,cells:number) {
    await page.mouse.move(x,y);await expect(page.getByTestId('board')).toHaveAttribute('data-highlight-cells',String(cells));
    return (await page.getByTestId('board').getAttribute('data-highlight-components'))!;
}
async function select(page:Page,x:number,y:number,ex:number,ey:number) {
    await page.keyboard.down('Shift');await drag(page,x,y,ex,ey);await page.keyboard.up('Shift');
}
async function settle(page:Page) {await page.evaluate(()=>new Promise<void>(resolve=>requestAnimationFrame(()=>requestAnimationFrame(()=>resolve()))));}

test('adjacent strokes stay independent, highlight entire regions and merge by clicking with one undo',async({page})=>{
    const c=await ready(page);await page.getByRole('button',{name:'Latch',exact:true}).click();
    await drag(page,c.x+12,c.y+12,c.x+108,c.y+12);await drag(page,c.x+12,c.y+44,c.x+108,c.y+44);
    await expect(page.locator('.workspace-status')).toContainText('8 cells');
    const first=await hoverId(page,c.x+12,c.y+12,4),second=await hoverId(page,c.x+12,c.y+44,4);expect(first).not.toBe(second);
    await page.screenshot({path:buildPath('ComponentHoverCapture.png')});
    await page.getByText('2D',{exact:true}).click();await hoverId(page,c.x+12,c.y+12,4);await page.screenshot({path:buildPath('ComponentFlatHighlightCapture.png')});
    await page.getByRole('button',{name:'Merge',exact:true}).click();
    await page.mouse.click(c.x+12,c.y+12);await page.mouse.click(c.x+108,c.y+44);
    await expect(page.getByTestId('board')).toHaveAttribute('data-merge-count','2');
    await expect(page.getByTestId('board')).toHaveAttribute('data-highlight-cells','8');
    await page.screenshot({path:buildPath('ComponentMergeCapture.png')});
    await page.getByRole('button',{name:'Confirm merge',exact:true}).click();await page.keyboard.press('Control+d');
    const joined=await hoverId(page,c.x+12,c.y+12,8);expect(joined).not.toBe(first);
    await page.keyboard.press('Control+z');await page.keyboard.press('Control+d');expect(await hoverId(page,c.x+12,c.y+12,4)).toBe(first);
    await page.keyboard.press('Control+Shift+z');await page.keyboard.press('Control+d');await hoverId(page,c.x+12,c.y+44,8);
    await page.getByRole('button',{name:'Merge',exact:true}).click();await page.mouse.click(c.x+12,c.y+12);await page.mouse.click(c.x+12,c.y+12,{button:'right'});
    await expect(page.getByTestId('board')).toHaveAttribute('data-edit-tool','pointer');await expect(page.locator('.workspace-status')).toContainText('8 cells');
    await page.keyboard.press('Control+d');await page.mouse.move(100,25);await expect(page.getByTestId('board')).toHaveAttribute('data-highlight-cells','0');
});

test('left paint overwrites, normalizes leftovers and grid-edge cuts allow independent component settings',async({page})=>{
    const c=await ready(page);await page.getByRole('button',{name:'Clock',exact:true}).click();
    await drag(page,c.x+12,c.y+12,c.x+204,c.y+12);const first=await hoverId(page,c.x+12,c.y+12,7);
    await page.keyboard.press('v');await page.mouse.click(c.x+12,c.y+12);
    await page.getByLabel('Clock hold',{exact:true}).fill('4');
    await page.getByRole('button',{name:'Clear selection'}).click();
    await page.getByRole('button',{name:'Trace',exact:true}).click();await page.mouse.click(c.x+108,c.y+12);
    expect(await hoverId(page,c.x+12,c.y+12,3)).toBe(first);const right=await hoverId(page,c.x+140,c.y+12,3);expect(right).not.toBe(first);
    await expect(page.locator('.workspace-status')).toContainText('7 cells');await page.screenshot({path:buildPath('ComponentOverwriteCapture.png')});
    await page.keyboard.press('Control+z');await hoverId(page,c.x+12,c.y+12,7);
    await page.getByRole('button',{name:'Split',exact:true}).click();await expect(page.getByTestId('board')).toHaveAttribute('data-edit-tool','split');
    await drag(page,c.x+64,c.y,c.x+64,c.y+32);await drag(page,c.x+128,c.y,c.x+128,c.y+32);await page.keyboard.press('q');
    await page.getByRole('button',{name:'Clear selection'}).click();await hoverId(page,c.x+75,c.y+12,2);
    await page.mouse.click(c.x+75,c.y+12);await page.getByLabel('Clock hold',{exact:true}).fill('9');
    await page.mouse.click(c.x+12,c.y+12);await expect(page.getByLabel('Clock hold',{exact:true})).toHaveValue('4');
    await page.screenshot({path:buildPath('ComponentSplitCapture.png')});
});

test('merge rejects distant and incompatible regions and leaves cancelled choices untouched',async({page})=>{
    const c=await ready(page);await page.getByRole('button',{name:'Latch',exact:true}).click();
    for(const y of [0,1,3])await drag(page,c.x+12,c.y+y*32+12,c.x+108,c.y+y*32+12);
    await page.getByRole('button',{name:'Clock',exact:true}).click();await page.mouse.click(c.x+140,c.y+44);
    await page.getByRole('button',{name:'Merge',exact:true}).click();await page.mouse.click(c.x+12,c.y+12);await page.mouse.click(c.x+12,c.y+108);
    await expect(page.getByRole('alert')).toContainText('adjacent');await expect(page.getByTestId('board')).toHaveAttribute('data-merge-count','1');
    await page.mouse.click(c.x+12,c.y+44);await page.mouse.click(c.x+140,c.y+44);await expect(page.getByTestId('board')).toHaveAttribute('data-merge-count','2');
    await page.keyboard.press('q');await hoverId(page,c.x+12,c.y+12,4);
    await expect(page.locator('.workspace-status')).toContainText('13 cells');
});

test('blueprints paste fresh flat components even in direct contact with existing placements',async({page})=>{
    const c=await ready(page);await page.getByRole('button',{name:'Latch',exact:true}).click();
    await drag(page,c.x+12,c.y+12,c.x+108,c.y+12);await drag(page,c.x+12,c.y+44,c.x+108,c.y+44);
    await select(page,c.x+1,c.y+2,c.x+125,c.y+62);await page.getByRole('button',{name:'Save blueprint',exact:true}).click();
    await page.getByRole('textbox',{name:'Blueprint name'}).fill('Latch pair');await page.getByRole('dialog').getByRole('button',{name:'Save blueprint',exact:true}).click();
    await page.getByRole('button',{name:'Copy blueprint Latch pair'}).click();
    for(const x of [4,8]) {await page.mouse.move(c.x+x*32+12,c.y+12);await page.keyboard.press('Control+v');await page.mouse.click(c.x+x*32+12,c.y+12);}
    await page.getByRole('button',{name:'Clear selection'}).click();
    const ids=[];for(const x of [0,4,8])for(const y of [0,1])ids.push(await hoverId(page,c.x+x*32+12,c.y+y*32+12,4));
    expect(new Set(ids).size).toBe(6);await expect(page.locator('.workspace-status')).toContainText('24 cells');
    await expect(page.locator('.blueprint-entry canvas')).toHaveAttribute('data-ready','true');await settle(page);await page.screenshot({path:buildPath('ComponentBlueprintCapture.png')});
});


test('whole-region highlights preserve holes and leave touching independent components unchanged in both modes',async({page})=>{
    await page.addInitScript(()=>{
        (window as unknown as {__TAURI_INTERNALS__:unknown}).__TAURI_INTERNALS__={invoke:async(command:string)=>{
            if(command==='recentProjects')return ['Regions.ocb'];if(command!=='openProject')throw Error(command);
            const tiles=[];for(let y=0;y<3;y++)for(let x=0;x<3;x++)if(x!==1||y!==1)tiles.push({x,y,toolId:'latch',componentId:1,isOn:true});
            for(let y=0;y<3;y++)tiles.push({x:3,y,toolId:'latch',componentId:2,isOn:true});
            return {board:{selectedTool:'latch',clockHoldTicks:1,latchInitialState:true,grid:{originX:-20,originY:-14,width:40,height:28},tiles},blueprints:[]};
        }};
    });
    const c=await ready(page);await page.locator('.project-switcher').click();await page.getByRole('menuitem',{name:'Regions.ocb',exact:true}).click();
    await expect(page.locator('.workspace-status')).toContainText('11 cells');
    const pixels=()=>page.locator('canvas[aria-label="Circuit board"]').evaluate(element=>{
        const canvas=element as HTMLCanvasElement,gl=canvas.getContext('webgl2')!,scale=canvas.width/canvas.getBoundingClientRect().width;
        return [[0,0],[1,1],[3,1]].map(([x,y])=>{const p=new Uint8Array(4);gl.readPixels(Math.floor(canvas.width/2+(x*32+8)*scale),canvas.height-1-Math.floor(canvas.height/2+(y*32+8)*scale),1,1,gl.RGBA,gl.UNSIGNED_BYTE,p);return [...p];});
    });
    for(const mode of ['2D','2.5D']) {
        await page.getByText(mode,{exact:true}).click();await page.mouse.move(100,25);await settle(page);const before=await pixels();
        await hoverId(page,c.x+12,c.y+12,8);await settle(page);const after=await pixels();
        expect(after[0]).not.toEqual(before[0]);expect(after[1]).toEqual(before[1]);expect(after[2]).toEqual(before[2]);
        await page.screenshot({path:buildPath(mode==='2D'?'ComponentHoleFlatCapture.png':'ComponentHoleCapture.png')});
    }
});
