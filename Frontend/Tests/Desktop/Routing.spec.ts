import { browser, $, expect } from '@wdio/globals';
import { routingProject } from '../Fixtures/Routing';
import { buildPath } from '../Paths';
async function ledBits() {
    return browser.execute(() => {
        const canvas=document.querySelector('canvas[aria-label="Circuit board"]') as HTMLCanvasElement,gl=canvas.getContext('webgl2')!;
        const scale=canvas.width/canvas.getBoundingClientRect().width;
        return Array.from({length:8},(_,lane)=>{
            const p=new Uint8Array(4);gl.readPixels(Math.floor(canvas.width/2+3*scale),canvas.height-1-Math.floor(canvas.height/2+((-7+lane*2)*32+3)*scale),1,1,gl.RGBA,gl.UNSIGNED_BYTE,p);return p[0]>100?'1':'0';
        }).join('');
    });
}
describe('Eight-color Bus routing',()=>{
    it('simulates eight independent channels through Bus and Cross in the native renderer',async()=>{
        await browser.execute(async ({path,project})=>{
            const invoke=(window as unknown as {__TAURI_INTERNALS__:{invoke:(command:string,args:unknown)=>Promise<unknown>}}).__TAURI_INTERNALS__.invoke;
            await invoke('saveProject',{path,project});
            await invoke('openProject',{path});
        },{path:buildPath('NativeRouting.ocb'),project:routingProject()});
        await browser.refresh();
        await browser.waitUntil(async()=>await $('[data-testid="board"]').getAttribute('data-render-ready')==='true');
        await $('.project-switcher').click();await $('button=NativeRouting.ocb').click();
        await $('label=2D').click();
        const center=await browser.execute(()=>{const r=document.querySelector('[data-testid="board"]')!.getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2};});
        await $('button=Run circuit').click();await $('button[aria-label="Pause simulation"]').click();
        await $('button[aria-label="Reset simulation"]').click();
        await browser.waitUntil(async()=>await ledBits()==='00000000');
        const toggle=async(lane:number)=>{await browser.action('pointer').move({x:Math.round(center.x-7*32+8),y:Math.round(center.y+(-7+lane*2)*32+8)}).down().up().perform();};
        for(let lane=0;lane<8;lane++){
            await toggle(lane);await $('button[aria-label="Next tick"]').click();
            await browser.waitUntil(async()=>await ledBits()==='0'.repeat(lane)+'1'+'0'.repeat(7-lane),{timeoutMsg:'Incorrect Bus channel '+lane});
            if(lane>=6)await browser.saveScreenshot(buildPath(lane===6?'DesktopBusOrangeCapture.png':'DesktopBusWhiteCapture.png'));
            await toggle(lane);await $('button[aria-label="Next tick"]').click();
            await browser.waitUntil(async()=>await ledBits()==='00000000');
        }
        await $('button=Back to design').click();
        await expect($('.error-toast')).not.toExist();
    });
});
