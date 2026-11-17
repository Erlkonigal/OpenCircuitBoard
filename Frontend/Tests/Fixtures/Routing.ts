import type { ProjectDocument, Tile } from '../../Source/Model';
export const TraceTools = ['trace','traceRed','traceGreen','traceBlue','traceCyan','traceMagenta','traceOrange','traceWhite'];
/** Eight independent source/sink pairs share a Bus and cross into Trace receivers. */
export function routingProject(): ProjectDocument {
    const tiles: Tile[] = [];
    for(let y=-7;y<=7;y++) tiles.push({x:-4,y,toolId:'bus',componentId:1,isOn:true});
    for(const [lane,trace] of TraceTools.entries()) {
        const y=-7+lane*2;
        for(const [offset,toolId] of ['latch','read',trace,'bus','cross',trace,'write','led'].entries()) {
            if(toolId==='bus') continue;
            tiles.push({x:-7+offset,y,toolId,componentId:10+lane*10+offset,isOn:toolId!=='latch'});
        }
    }
    return {board:{selectedTool:'traceOrange',clockHoldTicks:1,latchInitialState:false,
        grid:{originX:-20,originY:-14,width:40,height:28},tiles},blueprints:[]};
}
