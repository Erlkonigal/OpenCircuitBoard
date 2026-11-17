import { beforeEach, describe, expect, it } from 'vitest';
import { useEditor } from '../../Source/EditorStore';
import { cellKey, lineCells, newBoard, ToolKinds, validateBoard, validateProject, type Tile } from '../../Source/Model';
import { CellStore } from '../../Source/CellStore';
import { ComponentIndex } from '../../Source/ComponentIndex';
import { snapshotTiles } from '../../Source/ComponentTopology';
import { encodeBoard } from '../../Source/Native';
import { SplitPath } from '../../Source/SplitPath';
const state=()=>useEditor.getState();
const tile=(x:number,y:number,id=1,toolId='latch'):Tile=>({x,y,componentId:id,toolId,isOn:false});
const id=(x:number,y=0)=>state().Tiles.get(`${x},${y}`)!.componentId;
function stroke(x:number,y:number,end:number,tool='latch') {state().selectTool(tool);state().paint(lineCells({x,y},{x:end,y}));state().commit();}
const select=(x:number,y:number,width:number,height=1)=>state().selectRegionComponents({originX:x,originY:y,width,height});
beforeEach(()=>{useEditor.setState({Simulating:false});state().load(newBoard());});
describe('Explicit component identity',()=>{
    it('keeps adjacent strokes independent for every ink, while a same-ink starting cell extends its component',()=>{
        for(const tool of Object.keys(ToolKinds).filter(t=>t!=='empty')) {
            state().load(newBoard());stroke(0,0,3,tool);stroke(0,1,3,tool);
            expect(id(0)).toBe(id(3));expect(id(0)).not.toBe(id(0,1));
            const first=id(0);stroke(2,0,5,tool);expect(id(5)).toBe(first);expect(state().Components.count(first)).toBe(6);
        }
    });
    it('inherits starting parameters and only overwrites traversed cells of other components',()=>{
        state().configure({isOn:false});stroke(0,0,3);state().configure({isOn:true});stroke(5,0,7);
        const original=id(0),other=id(7);stroke(2,0,5);
        expect(id(5)).toBe(original);expect(id(6)).toBe(other);expect(state().Tiles.get('5,0')?.isOn).toBe(false);
        state().undo();expect(id(5)).toBe(other);expect(state().Tiles.has('4,0')).toBe(false);
    });
    it('overwrites occupied cells and splits the remainder by size, then top-left tie break, in one undo',()=>{
        stroke(-3,0,3);const original=id(-3),before=state().export();stroke(0,0,0,'clock');
        expect(id(-3)).toBe(original);expect(id(1)).not.toBe(original);expect(id(1)).toBe(id(3));
        expect(state().Components.size).toBe(3);expect(state().Undo).toHaveLength(2);
        state().undo();expect(state().export().tiles).toEqual(before.tiles);state().redo();expect(state().Components.size).toBe(3);
        state().load(newBoard());stroke(-3,0,3);const biggest=id(-3);stroke(-1,0,-1,'trace');expect(id(0)).toBe(biggest);expect(id(-3)).not.toBe(biggest);
    });
    it('normalizes diagonal pieces and never reunites contacts automatically',()=>{
        state().selectTool('latch');state().paint([{x:0,y:0},{x:1,y:1}]);state().commit();expect(id(0)).not.toBe(id(1,1));
        stroke(0,1,1);expect(id(0,1)).not.toBe(id(0));expect(id(0,1)).toBe(id(1,1));
    });
    it('normalizes overwritten leftovers, while cut and delete operate on complete identities',()=>{
        stroke(-2,0,2);const before=state().export();state().paint([{x:0,y:0}],true);state().commit();
        expect(id(-1)).not.toBe(id(1));state().undo();expect(state().export()).toEqual(before);
        for(const cut of [true,false]) {
            select(0,0,1);if(cut)state().copy(true);else state().deleteSelection();
            expect(state().Tiles.size).toBe(0);state().undo();expect(state().export()).toEqual(before);
        }
        state().paint([{x:0,y:0}],true);state().cancel();expect(state().export()).toEqual(before);
    });
    it('merges every entered compatible component into the starting identity in one reversible stroke',()=>{
        for(const tool of ['latch','clock','traceRed']) {
            state().load(newBoard());stroke(0,0,1,tool);stroke(4,0,6,tool);stroke(9,0,12,tool);
            const original=id(0),before=state().export(),history=state().Undo.length;
            stroke(1,0,9,tool);expect(state().Components.size).toBe(1);expect(id(12)).toBe(original);expect(state().Tiles.size).toBe(13);
            expect(state().Undo.length).toBe(history+1);state().undo();expect(state().export()).toEqual(before);
            state().redo();expect(state().Components.size).toBe(1);expect(id(12)).toBe(original);
        }
    });
    it('does not merge mere side contacts, corner contacts or a stroke started in empty space',()=>{
        stroke(0,0,0);stroke(3,1,5);const other=id(3,1);stroke(0,0,4);expect(id(4)).not.toBe(other);
        state().load(newBoard());stroke(0,0,0);stroke(1,1,3);const diagonal=id(1,1);
        stroke(0,0,0);state().paint([{x:0,y:0},{x:1,y:1}]);state().commit();expect(id(1,1)).toBe(diagonal);expect(id(0)).not.toBe(diagonal);
        state().load(newBoard());stroke(4,0,6);const original=id(6);stroke(0,0,4);expect(id(0)).not.toBe(original);expect(id(5)).toBe(original);
    });
    it('keeps incompatible color and parameter targets separate while replacing only traversed cells',()=>{
        for(const [source,target] of [['latch','latch'],['clock','clock'],['traceRed','traceBlue']]) {
            state().load(newBoard());state().configure({isOn:false,clockHoldTicks:3});stroke(0,0,1,source);
            state().configure({isOn:true,clockHoldTicks:7});stroke(4,0,7,target);const other=id(7);
            stroke(1,0,4,source);expect(id(4)).toBe(id(0));expect(id(5)).toBe(other);expect(id(0)).not.toBe(other);
            if(source==='clock')expect(state().Tiles.get('4,0')!.clockHoldTicks).toBe(3);
        }
    });
    it('rolls back full target merges and bridge cells when an extended stroke is cancelled',()=>{
        stroke(0,0,1);stroke(4,0,7);const before=state().export(),history=state().Undo.length;
        state().paint(lineCells({x:1,y:0},{x:4,y:0}));expect(state().Components.size).toBe(1);
        state().cancel();expect(state().export()).toEqual(before);expect(state().Undo.length).toBe(history);expect(state().Components.size).toBe(2);
    });
    it('merges whole regions by clicks, rejects nonadjacent or incompatible picks and records one command',()=>{
        stroke(0,0,3);stroke(0,1,3);stroke(0,3,3);stroke(4,1,4,'clock');const before=state().export(),history=state().Undo.length;
        state().selectTool('merge');state().pickComponent({x:0,y:0});state().pickComponent({x:0,y:3});expect(state().MergeIds).toHaveLength(1);expect(state().MergeError).toBeTruthy();
        state().pickComponent({x:3,y:1});state().pickComponent({x:4,y:1});expect(state().MergeIds).toHaveLength(2);
        expect(state().confirmMerge()).toBe(true);expect(state().Components.count(id(0))).toBe(8);expect(state().Undo).toHaveLength(history+1);
        state().undo();expect(state().export()).toEqual(before);state().redo();expect(id(3,1)).toBe(id(0));
        state().selectTool('merge');state().pickComponent({x:0,y:0});state().cancel();expect(state().MergeIds).toEqual([]);expect(state().EditTool).toBe('pointer');
    });
    it('requires the entire picked set to stay connected, including when removing a bridge',()=>{
        for(let y=0;y<3;y++)stroke(0,y,1);state().selectTool('merge');
        for(let y=0;y<3;y++)state().pickComponent({x:0,y});state().pickComponent({x:0,y:1});expect(state().MergeIds).toHaveLength(3);
        state().pickComponent({x:0,y:2});expect(state().MergeIds).toHaveLength(2);
    });
    it('rejects different latch and clock settings when merging',()=>{
        for(const tool of ['latch','clock']) {
            state().load(newBoard());stroke(0,0,1,tool);state().configure({isOn:false,clockHoldTicks:9});stroke(0,1,1,tool);
            state().selectTool('merge');state().pickComponent({x:0,y:0});state().pickComponent({x:0,y:1});expect(state().MergeIds).toHaveLength(1);
        }
    });
    it('splits along grid edges and edits whole results independently',()=>{
        stroke(0,0,5,'clock');const original=id(0);state().selectComponents([original]);state().configure({clockHoldTicks:4},true);
        state().selectTool('split');const path=new SplitPath({x:2,y:0});path.append({x:2,y:1});
        expect(state().splitAlong(path)).toBe(true);expect(state().Components.size).toBe(2);expect(id(2)).toBe(original);expect(id(0)).not.toBe(original);
        state().selectTool('pointer');select(0,0,1);state().configure({clockHoldTicks:9},true);expect(state().Tiles.get('1,0')?.clockHoldTicks).toBe(9);expect(state().Tiles.get('2,0')?.clockHoldTicks).toBe(4);
        state().undo();state().undo();expect(state().Components.size).toBe(1);
    });
    it('moves complete components even when a marquee only touches part of their area',()=>{
        stroke(0,0,4);const original=id(0);select(2,0,1);expect(state().confirmMove({x:0,y:2})).toBe(true);
        expect(id(4,2)).toBe(original);expect(state().Tiles.has('0,2')).toBe(true);expect(state().Tiles.has('2,0')).toBe(false);
        state().undo();expect(state().Components.size).toBe(1);expect(id(4)).toBe(original);
    });
    it('remaps independent blueprint placements, preserving flat internal groups and clipped fragments',()=>{
        stroke(0,0,3);stroke(0,1,3);select(0,0,4,2);state().copy();expect(state().createBlueprint('Pair',true)).toBe(true);
        state().useBlueprint(state().Blueprints[0].id);const source=id(0),groups:number[]=[];
        for(const x of [5,9]) {state().paste({x,y:0});expect(state().confirmPaste()).toBe(true);groups.push(id(x),id(x,1));expect(id(x)).toBe(id(x+3));}
        expect(new Set([source,...groups]).size).toBe(5);expect(state().exportProject().blueprints[0]).not.toHaveProperty('children');
        const fragments=snapshotTiles([tile(0,0),tile(2,0)]);expect(fragments[0].componentId).not.toBe(fragments[1].componentId);
    });
    it('exits merge and split tools when starting an ordinary paste preview',()=>{
        stroke(0,0,1);select(0,0,2);state().copy();
        for(const mode of ['merge','split']) {
            state().selectTool(mode);if(mode==='merge')state().pickComponent({x:0,y:0});
            state().paste({x:4,y:mode==='merge'?0:1});expect(state().EditTool).toBe('pointer');expect(state().MergeIds).toEqual([]);
            expect(state().confirmPaste()).toBe(true);
        }
    });
    it('maintains membership and contact indexes across signed chunk edges, cancellation, undo and redo',()=>{
        const source=CellStore.from([tile(-65,0,1),tile(-64,0,2),tile(-64,1,2),tile(-64,2,3)]),index=new ComponentIndex(source);
        expect(index.canJoin([1],2)).toBe(true);expect(index.canJoin([1],3)).toBe(false);expect(index.connected([1,2,3])).toBe(true);
        const next=source.update([['-64,0',undefined]]);index.sync(next);expect(index.connected([1,2])).toBe(false);expect(index.count(2)).toBe(1);index.sync(source);expect(index.canJoin([1],2)).toBe(true);
        expect([...index.members(2)].map(cellKey)).toEqual(['-64,0','-64,1']);
    });
    it('requires valid IDs and homogeneous connected regions, without changing a loaded document on error',()=>{
        stroke(0,0,1);const previous=state().export();
        for(const tiles of [[{x:0,y:0,toolId:'latch',isOn:false}], [tile(0,0,0)], [tile(0,0),tile(2,0)], [tile(0,0),{...tile(1,0),isOn:true}], [tile(0,0,1,'mesh')]]) {
            expect(()=>state().load(JSON.parse(JSON.stringify({...newBoard(),tiles})))).toThrow('ProjectBoardInvalid');expect(state().export()).toEqual(previous);
            expect(()=>validateProject({board:newBoard(),blueprints:[{id:'x',name:'x',width:4,height:4,tiles}]})).toThrow('ProjectBlueprintInvalid');
        }
    });
    it('encodes compile v4 with zero for empty cells and preserves numeric ink IDs',()=>{
        const board={...newBoard(),tiles:[tile(-2,-1,17),tile(-1,0,23,'switch')]};const d=new DataView(encodeBoard(board).buffer);
        expect(d.getInt32(4,true)).toBe(4);expect([...new Int32Array(d.buffer,24+4*3*4,4)]).toEqual([17,0,0,23]);
        expect(ToolKinds.switch).toBe(30);expect(ToolKinds.latch).toBe(25);expect(Object.values(ToolKinds)).not.toContain(14);
        expect(validateBoard(board).tiles[0].componentId).toBe(17);
    });
});
