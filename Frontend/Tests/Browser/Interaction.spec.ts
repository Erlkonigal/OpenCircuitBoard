import { test, expect, type Page } from '../BrowserTest';
import { buildPath } from '../Paths';
async function ready(page:Page) {
    await page.goto('/');const board=page.getByTestId('board');await expect(board).toHaveAttribute('data-render-ready','true');
    const r=(await board.boundingBox())!;return {x:r.x+r.width/2,y:r.y+r.height/2};
}
async function drag(page:Page,x:number,y:number,tx:number,ty:number) {await page.mouse.move(x,y);await page.mouse.down();await page.mouse.move(tx,ty,{steps:8});await page.mouse.up();}
async function additive(page:Page,x:number,y:number,tx:number,ty:number) {await page.keyboard.down('Shift');await drag(page,x,y,tx,ty);await page.keyboard.up('Shift');}
async function stroke(page:Page,c:{x:number;y:number},row=0,tool='Latch') {
    await page.getByRole('button',{name:tool,exact:true}).click();await drag(page,c.x+12,c.y+row*32+12,c.x+140,c.y+row*32+12);
}
async function count(page:Page,cells:number) {await expect(page.getByTestId('board')).toHaveAttribute('data-selection-cells',String(cells));}

test('pointer selects identities, edits properties and deletes the selection rather than the hovered component',async({page})=>{
    const c=await ready(page),board=page.getByTestId('board');await expect(board).toHaveAttribute('data-edit-tool','pointer');
    await page.mouse.click(c.x+12,c.y+12);await expect(page.locator('.workspace-status')).toContainText('0 cells');
    await stroke(page,c,0,'Clock');await stroke(page,c,1,'Clock');await page.keyboard.press('q');
    await page.mouse.click(c.x+12,c.y+12);await count(page,5);await expect(board).toHaveAttribute('data-selection-kind','components');
    await page.getByLabel('Clock hold',{exact:true}).fill('7');await page.getByLabel('Clock hold',{exact:true}).press('Control+a');await count(page,5);
    await page.getByLabel('Search components').fill('xqgb');await expect(board).toHaveAttribute('data-edit-tool','pointer');await count(page,5);
    await page.getByLabel('Search components').fill('');await page.mouse.click(c.x+12,c.y+44);await expect(page.getByLabel('Clock hold',{exact:true})).toHaveValue('1');
    await page.keyboard.down('Shift');await page.mouse.click(c.x+12,c.y+12);await page.keyboard.up('Shift');await count(page,10);
    await expect(page.getByLabel('Clock hold',{exact:true})).toHaveValue('');await expect(page.getByLabel('Clock hold',{exact:true})).toHaveAttribute('placeholder','Mixed');await expect(page.getByRole('button',{name:'Merge selected components'})).toHaveCount(0);
    await page.getByLabel('Clock hold',{exact:true}).fill('3');await page.mouse.click(c.x+12,c.y+12);await count(page,10);await expect(page.getByRole('button',{name:'Merge selected components'})).toBeVisible();
    await page.keyboard.press('Control+d');await page.mouse.click(c.x+12,c.y+12);await page.mouse.move(c.x+12,c.y+44);await page.keyboard.press('x');
    await expect(page.locator('.workspace-status')).toContainText('5 cells');
    await page.keyboard.press('Control+z');await count(page,5);await expect(page.locator('.workspace-status')).toContainText('10 cells');
    await page.keyboard.press('Control+Shift+z');await expect(page.locator('.workspace-status')).toContainText('5 cells');
    await page.screenshot({path:buildPath('PointerPropertiesCapture.png')});
});

test('Shift clicks preserve multiselection, every marquee selects whole components and eligible groups expose Merge',async({page})=>{
    const c=await ready(page),board=page.getByTestId('board');await stroke(page,c);await stroke(page,c,1);await stroke(page,c,3);await page.keyboard.press('q');
    await page.mouse.click(c.x+12,c.y+12);await count(page,5);
    await page.keyboard.down('Shift');await page.mouse.click(c.x+76,c.y+44);await page.keyboard.up('Shift');await count(page,10);
    const merge=page.getByRole('button',{name:'Merge selected components',exact:true});await expect(merge).toBeVisible();
    await page.screenshot({path:buildPath('ShiftMultiSelectCapture.png')});
    await page.keyboard.down('Shift');await page.mouse.click(c.x+76,c.y+108);await page.keyboard.up('Shift');await count(page,15);await expect(merge).toHaveCount(0);
    await page.keyboard.down('Shift');await page.mouse.click(c.x+76,c.y+108);await page.keyboard.up('Shift');await merge.click();
    await expect(board).toHaveAttribute('data-component-count','2');await count(page,10);await page.keyboard.press('Control+z');await count(page,10);
    await additive(page,c.x+66,c.y+98,c.x+92,c.y+122);await count(page,15);
    await page.screenshot({path:buildPath('ComponentMarqueeCapture.png')});await page.keyboard.press('x');await expect(page.locator('.workspace-status')).toContainText('0 cells');
    await page.keyboard.press('Control+z');await page.keyboard.press('Control+d');
    await drag(page,c.x-18,c.y-18,c.x+61,c.y+60);await count(page,10);await expect(board).toHaveAttribute('data-selection-kind','components');
    await page.getByRole('button',{name:'Clock',exact:true}).click();await additive(page,c.x+66,c.y+2,c.x+92,c.y+60);await count(page,10);
    await expect(board).toHaveAttribute('data-edit-tool','pointer');await expect(page.getByTestId('right-dock')).toContainText('Selected components');
});

test('only Shift modifies mouse selection while Ctrl keyboard commands remain available',async({page})=>{
    const c=await ready(page);await stroke(page,c);await stroke(page,c,1);await page.keyboard.press('q');await page.mouse.click(c.x+12,c.y+12);
    await page.keyboard.down('Control');await page.mouse.click(c.x+12,c.y+44);await page.keyboard.up('Control');await count(page,5);
    await page.keyboard.down('Meta');await page.mouse.click(c.x+12,c.y+12);await page.keyboard.up('Meta');await count(page,5);
    await page.keyboard.down('Shift');await page.mouse.click(c.x+12,c.y+44);await page.keyboard.up('Shift');await count(page,10);
    await expect(page.getByRole('button',{name:'Merge selected components'})).toBeVisible();await page.keyboard.press('Control+c');await expect(page.getByTestId('left-dock')).toContainText('Clipboard');
    await page.keyboard.press('Control+x');await expect(page.locator('.workspace-status')).toContainText('0 cells');await page.keyboard.press('Control+z');await count(page,10);
});

test('nearby keys and right mouse cancel unfinished edits without deleting or committing a partial gesture',async({page})=>{
    const c=await ready(page),board=page.getByTestId('board');await stroke(page,c);await page.keyboard.press('q');await page.mouse.click(c.x+12,c.y+12);await count(page,5);
    await page.mouse.move(c.x+12,c.y+12);await page.mouse.down();await page.mouse.move(c.x+45,c.y+78,{steps:5});await expect(board).toHaveAttribute('data-gesture','move');
    await page.mouse.down({button:'right'});await page.mouse.up({button:'right'});await page.mouse.up();await expect(board).toHaveAttribute('data-gesture','idle');await count(page,5);
    await expect(page.locator('.workspace-status')).toContainText('5 cells');
    await page.keyboard.press('b');await page.mouse.move(c.x+12,c.y+76);await page.mouse.down();await page.mouse.move(c.x+108,c.y+76,{steps:5});
    await page.keyboard.press('q');await page.mouse.up();await expect(page.locator('.workspace-status')).toContainText('5 cells');await expect(board).toHaveAttribute('data-edit-tool','pointer');
    await page.mouse.click(c.x+12,c.y+12);for(const key of ['Delete','Backspace','Escape','Enter'])await page.keyboard.press(key);await count(page,5);await expect(page.locator('.workspace-status')).toContainText('5 cells');
    await page.mouse.click(c.x+12,c.y+12,{button:'right'});await count(page,0);await expect(page.locator('.workspace-status')).toContainText('5 cells');
    await page.screenshot({path:buildPath('PointerCancelCapture.png')});
});

test('group dragging keeps identities and a cancelled pan returns to the same camera and tool',async({page})=>{
    const c=await ready(page),board=page.getByTestId('board');await stroke(page,c);await stroke(page,c,1);await page.keyboard.press('v');
    await page.mouse.click(c.x+12,c.y+12);await page.keyboard.down('Shift');await page.mouse.click(c.x+12,c.y+44);await page.keyboard.up('Shift');await count(page,10);
    await drag(page,c.x+12,c.y+12,c.x+76,c.y+108);await expect(board).toHaveAttribute('data-component-count','2');await count(page,10);
    await page.keyboard.press('Control+z');await count(page,10);await page.keyboard.press('b');
    await page.keyboard.down('Space');await page.mouse.move(c.x+180,c.y+108);await page.mouse.down();await page.mouse.move(c.x+220,c.y+156,{steps:5});await expect(board).toHaveAttribute('data-gesture','pan');
    await page.mouse.down({button:'right'});await page.mouse.up({button:'right'});await page.mouse.up();await page.keyboard.up('Space');await expect(board).toHaveAttribute('data-edit-tool','pointer');
    await page.mouse.click(c.x+12,c.y+12);await count(page,5);await expect(page.locator('.workspace-status')).toContainText('10 cells');
    await page.screenshot({path:buildPath('PointerGroupMoveCapture.png')});
});

test('Merge keeps its confirmation tool and Split cuts with a repeated grid-edge stroke on release',async({page})=>{
    const c=await ready(page),board=page.getByTestId('board');await stroke(page,c,0,'Clock');await stroke(page,c,1,'Clock');await page.keyboard.press('q');
    await page.keyboard.press('g');await page.mouse.click(c.x+12,c.y+12);await page.mouse.click(c.x+12,c.y+44);await expect(board).toHaveAttribute('data-merge-count','2');
    await expect(page.getByRole('toolbar',{name:'Pending operation'})).toBeVisible();await page.screenshot({path:buildPath('MergeActionsCapture.png')});
    await page.keyboard.press('g');await expect(board).toHaveAttribute('data-component-count','1');await page.keyboard.press('Shift+g');
    await page.mouse.move(c.x+64,c.y);await page.mouse.down();await page.mouse.move(c.x+64,c.y+32,{steps:4});await page.mouse.move(c.x+96,c.y+32,{steps:4});
    await page.mouse.move(c.x+96,c.y+64,{steps:4});await expect(board).toHaveAttribute('data-component-count','1');await expect(board).toHaveAttribute('data-split-edges','3');
    await page.screenshot({path:buildPath('SplitPathCapture.png')});await page.mouse.up();await expect(board).toHaveAttribute('data-component-count','2');await expect(board).toHaveAttribute('data-edit-tool','split');
    await expect(page.getByRole('button',{name:'Confirm split',exact:true})).toHaveCount(0);await expect(board).toHaveAttribute('data-split-edges','0');
    await drag(page,c.x+128,c.y,c.x+128,c.y+64);await expect(board).toHaveAttribute('data-component-count','3');
    await page.keyboard.press('Control+z');await expect(board).toHaveAttribute('data-component-count','2');await expect(board).toHaveAttribute('data-edit-tool','split');
    await page.keyboard.press('Control+Shift+z');await expect(board).toHaveAttribute('data-component-count','3');await page.keyboard.press('q');await count(page,5);
    await page.keyboard.press('Control+d');await page.mouse.click(c.x+140,c.y+12);await page.getByLabel('Clock hold',{exact:true}).fill('9');
    await page.mouse.click(c.x+12,c.y+44);await expect(page.getByLabel('Clock hold',{exact:true})).toHaveValue('1');
});

test('drawing merges only entered compatible targets and cancelling restores complete target regions',async({page})=>{
    const c=await ready(page),board=page.getByTestId('board');await page.getByRole('button',{name:'Latch',exact:true}).click();
    for(const [start,end] of [[0,1],[4,6],[9,11]])await drag(page,c.x+start*32+12,c.y+12,c.x+end*32+12,c.y+12);
    await expect(board).toHaveAttribute('data-component-count','3');
    await page.mouse.move(c.x+44,c.y+12);await page.mouse.down();await page.mouse.move(c.x+140,c.y+12,{steps:6});await expect(board).toHaveAttribute('data-component-count','2');
    await page.mouse.down({button:'right'});await page.mouse.up({button:'right'});await page.mouse.up();await expect(board).toHaveAttribute('data-component-count','3');
    await expect(page.locator('.workspace-status')).toContainText('8 cells');await page.keyboard.press('b');await drag(page,c.x+44,c.y+12,c.x+300,c.y+12);
    await expect(board).toHaveAttribute('data-component-count','1');await expect(page.locator('.workspace-status')).toContainText('12 cells');
    await page.screenshot({path:buildPath('DrawMergeCapture.png')});await page.keyboard.press('Control+z');await expect(board).toHaveAttribute('data-component-count','3');
    await page.keyboard.press('Control+Shift+z');await expect(board).toHaveAttribute('data-component-count','1');
});

test('an incomplete cut leaves no barrier and right mouse cancels a preview in either display mode',async({page})=>{
    const c=await ready(page),board=page.getByTestId('board');await stroke(page,c,0,'Clock');await stroke(page,c,1,'Clock');await page.keyboard.press('q');
    await page.keyboard.press('Control+a');await page.getByRole('button',{name:'Merge selected components'}).click();
    for(const mode of ['2D','2.5D']) {
        await page.getByText(mode,{exact:true}).click();await page.getByRole('button',{name:'Split',exact:true}).click();
        await drag(page,c.x+64,c.y,c.x+64,c.y+32);await expect(board).toHaveAttribute('data-component-count','1');
        await expect(page.getByRole('toolbar',{name:'Split tool'})).toContainText('did not cut');
        await page.mouse.move(c.x+64,c.y);await page.mouse.down();await page.mouse.move(c.x+64,c.y+64,{steps:5});
        await page.screenshot({path:buildPath(mode==='2D'?'SplitFlatPreviewCapture.png':'SplitDepthPreviewCapture.png')});
        await page.mouse.down({button:'right'});await page.mouse.up({button:'right'});await page.mouse.up();await expect(board).toHaveAttribute('data-component-count','1');await expect(board).toHaveAttribute('data-edit-tool','pointer');
    }
});

test('Split previews retract along the tail, redirect and leave only the remaining cut in both display modes',async({page})=>{
    const c=await ready(page),board=page.getByTestId('board');await stroke(page,c,0,'Clock');await stroke(page,c,1,'Clock');await page.keyboard.press('q');
    await page.keyboard.press('Control+a');await page.getByRole('button',{name:'Merge selected components'}).click();
    for(const mode of ['2D','2.5D']) {
        await page.getByText(mode,{exact:true}).click();await page.getByRole('button',{name:'Split',exact:true}).click();
        await page.mouse.move(c.x+64,c.y);await page.mouse.down();await page.mouse.move(c.x+64,c.y+64,{steps:4});await expect(board).toHaveAttribute('data-split-edges','2');
        const full=await page.locator('canvas[aria-label="Circuit board"]').screenshot();
        await page.mouse.move(c.x+64,c.y+32,{steps:2});await expect(board).toHaveAttribute('data-split-edges','1');
        expect(await page.locator('canvas[aria-label="Circuit board"]').screenshot()).not.toEqual(full);
        await page.mouse.move(c.x+96,c.y+32,{steps:2});await page.mouse.move(c.x+96,c.y+64,{steps:2});await expect(board).toHaveAttribute('data-split-edges','3');
        await page.screenshot({path:buildPath(mode==='2D'?'SplitBacktrackFlatCapture.png':'SplitBacktrackCapture.png')});await page.mouse.up();
        await expect(board).toHaveAttribute('data-component-count','2');await expect(page.locator('.workspace-status')).toContainText('10 cells');
        await page.keyboard.press('Control+z');await expect(board).toHaveAttribute('data-component-count','1');await expect(board).toHaveAttribute('data-edit-tool','split');
        await page.mouse.move(c.x+64,c.y);await page.mouse.down();await page.mouse.move(c.x+64,c.y+64);await expect(board).toHaveAttribute('data-split-edges','2');
        await page.mouse.move(c.x+64,c.y);await expect(board).toHaveAttribute('data-split-edges','0');await page.mouse.up();
        await expect(board).toHaveAttribute('data-component-count','1');await expect(board).toHaveAttribute('data-gesture','idle');await expect(page.getByRole('toolbar',{name:'Split tool'})).not.toContainText('did not cut');
        await page.keyboard.press('Control+Shift+z');await expect(board).toHaveAttribute('data-component-count','2');await page.keyboard.press('Control+z');await expect(board).toHaveAttribute('data-component-count','1');
    }
});

test('paste is temporary, right click cancels it and a confirmed paste cannot accidentally start painting',async({page})=>{
    const c=await ready(page),board=page.getByTestId('board');await stroke(page,c);await page.keyboard.press('q');await page.mouse.click(c.x+12,c.y+12);await page.keyboard.press('Control+c');
    await page.mouse.move(c.x+12,c.y+108);await page.keyboard.press('Control+v');await expect(page.locator('.canvas-context')).toBeVisible();await page.mouse.click(c.x+12,c.y+108,{button:'right'});
    await expect(page.locator('.canvas-context')).toHaveCount(0);await count(page,5);await expect(page.locator('.workspace-status')).toContainText('5 cells');
    await page.keyboard.press('Control+v');await page.mouse.click(c.x+12,c.y+108);await expect(board).toHaveAttribute('data-edit-tool','pointer');await expect(board).toHaveAttribute('data-component-count','2');
    await page.mouse.click(c.x+12,c.y+172);await expect(page.locator('.workspace-status')).toContainText('10 cells');
    await page.getByRole('button',{name:'Keyboard shortcuts',exact:true}).click();await page.keyboard.press('x');await page.keyboard.press('q');await expect(page.getByRole('dialog')).toBeVisible();await expect(page.locator('.workspace-status')).toContainText('10 cells');
});
