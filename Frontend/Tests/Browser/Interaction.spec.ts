import { test, expect, type Page } from '../BrowserTest';
import { buildPath } from '../Paths';
async function ready(page:Page) {
    await page.goto('/');const board=page.getByTestId('board');await expect(board).toHaveAttribute('data-render-ready','true');
    const r=(await board.boundingBox())!;return {x:r.x+r.width/2,y:r.y+r.height/2};
}
async function drag(page:Page,x:number,y:number,tx:number,ty:number) {await page.mouse.move(x,y);await page.mouse.down();await page.mouse.move(tx,ty,{steps:8});await page.mouse.up();}
async function local(page:Page,x:number,y:number,tx:number,ty:number) {await page.keyboard.down('Shift');await drag(page,x,y,tx,ty);await page.keyboard.up('Shift');}
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
    await page.keyboard.down('Control');await page.mouse.click(c.x+12,c.y+12);await page.keyboard.up('Control');await count(page,10);
    await expect(page.getByLabel('Clock hold',{exact:true})).toHaveValue('');await expect(page.getByLabel('Clock hold',{exact:true})).toHaveAttribute('placeholder','Mixed');
    await page.getByLabel('Clock hold',{exact:true}).fill('3');await page.mouse.click(c.x+12,c.y+12);await count(page,10);
    await page.keyboard.press('Control+d');await page.mouse.click(c.x+12,c.y+12);await page.mouse.move(c.x+12,c.y+44);await page.keyboard.press('x');
    await expect(page.locator('.workspace-status')).toContainText('5 cells');
    await page.keyboard.press('Control+z');await count(page,5);await expect(page.locator('.workspace-status')).toContainText('10 cells');
    await page.keyboard.press('Control+Shift+z');await expect(page.locator('.workspace-status')).toContainText('5 cells');
    await page.screenshot({path:buildPath('PointerPropertiesCapture.png')});
});

test('ordinary marquee selects complete components while Shift marquee deletes only clipped cells and splits the remainder',async({page})=>{
    const c=await ready(page),board=page.getByTestId('board');await stroke(page,c);await stroke(page,c,1);await page.keyboard.press('q');
    await drag(page,c.x-18,c.y-18,c.x+61,c.y+60);await expect(board).toHaveAttribute('data-selection-kind','components');await count(page,10);
    await page.screenshot({path:buildPath('ComponentMarqueeCapture.png')});await page.keyboard.press('x');await expect(page.locator('.workspace-status')).toContainText('0 cells');
    await page.keyboard.press('Control+z');await page.keyboard.press('Control+d');
    await local(page,c.x+66,c.y+2,c.x+92,c.y+60);await count(page,2);await expect(board).toHaveAttribute('data-selection-kind','region');
    await expect(page.getByTestId('right-dock')).toContainText('Local cell selection');await expect(page.getByLabel('Clock hold',{exact:true})).toHaveCount(0);
    await page.screenshot({path:buildPath('LocalSelectionCapture.png')});await page.keyboard.press('x');
    await expect(page.locator('.workspace-status')).toContainText('8 cells');await expect(board).toHaveAttribute('data-component-count','4');
    await page.keyboard.press('Control+z');await count(page,2);await expect(board).toHaveAttribute('data-component-count','2');
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
    await page.mouse.click(c.x+12,c.y+12);await page.keyboard.down('Control');await page.mouse.click(c.x+12,c.y+44);await page.keyboard.up('Control');await count(page,10);
    await drag(page,c.x+12,c.y+12,c.x+76,c.y+108);await expect(board).toHaveAttribute('data-component-count','2');await count(page,10);
    await page.keyboard.press('Control+z');await count(page,10);await page.keyboard.press('b');
    await page.keyboard.down('Space');await page.mouse.move(c.x+180,c.y+108);await page.mouse.down();await page.mouse.move(c.x+220,c.y+156,{steps:5});await expect(board).toHaveAttribute('data-gesture','pan');
    await page.mouse.down({button:'right'});await page.mouse.up({button:'right'});await page.mouse.up();await page.keyboard.up('Space');await expect(board).toHaveAttribute('data-edit-tool','pointer');
    await page.mouse.click(c.x+12,c.y+12);await count(page,5);await expect(page.locator('.workspace-status')).toContainText('10 cells');
    await page.screenshot({path:buildPath('PointerGroupMoveCapture.png')});
});

test('G and Shift+G share the floating confirmation workflow and local properties become editable after splitting',async({page})=>{
    const c=await ready(page),board=page.getByTestId('board');await stroke(page,c,0,'Clock');await stroke(page,c,1,'Clock');await page.keyboard.press('q');
    await page.keyboard.press('g');await page.mouse.click(c.x+12,c.y+12);await page.mouse.click(c.x+12,c.y+44);await expect(board).toHaveAttribute('data-merge-count','2');
    await expect(page.getByRole('toolbar',{name:'Pending operation'})).toBeVisible();await page.screenshot({path:buildPath('MergeActionsCapture.png')});
    await page.keyboard.press('g');await expect(board).toHaveAttribute('data-edit-tool','pointer');await expect(board).toHaveAttribute('data-component-count','1');
    await page.keyboard.press('Shift+g');await local(page,c.x+65,c.y+1,c.x+123,c.y+30);await expect(page.getByRole('button',{name:'Confirm split',exact:true})).toBeEnabled();
    await page.screenshot({path:buildPath('SplitActionsCapture.png')});await page.keyboard.press('Shift+g');await expect(board).toHaveAttribute('data-selection-kind','components');
    await count(page,2);await page.getByLabel('Clock hold',{exact:true}).fill('9');await page.mouse.click(c.x+12,c.y+44);await expect(page.getByLabel('Clock hold',{exact:true})).toHaveValue('1');
});

test('paste is temporary, right click cancels it and a confirmed paste cannot accidentally start painting',async({page})=>{
    const c=await ready(page),board=page.getByTestId('board');await stroke(page,c);await page.keyboard.press('q');await page.mouse.click(c.x+12,c.y+12);await page.keyboard.press('Control+c');
    await page.mouse.move(c.x+12,c.y+108);await page.keyboard.press('Control+v');await expect(page.locator('.canvas-context')).toBeVisible();await page.mouse.click(c.x+12,c.y+108,{button:'right'});
    await expect(page.locator('.canvas-context')).toHaveCount(0);await count(page,5);await expect(page.locator('.workspace-status')).toContainText('5 cells');
    await page.keyboard.press('Control+v');await page.mouse.click(c.x+12,c.y+108);await expect(board).toHaveAttribute('data-edit-tool','pointer');await expect(board).toHaveAttribute('data-component-count','2');
    await page.mouse.click(c.x+12,c.y+172);await expect(page.locator('.workspace-status')).toContainText('10 cells');
    await page.getByRole('button',{name:'Keyboard shortcuts',exact:true}).click();await page.keyboard.press('x');await page.keyboard.press('q');await expect(page.getByRole('dialog')).toBeVisible();await expect(page.locator('.workspace-status')).toContainText('10 cells');
});
