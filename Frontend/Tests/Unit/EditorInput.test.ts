import { beforeEach, describe, expect, it, vi } from 'vitest';
import { EditorInput } from '../../Source/EditorInput';
import { useEditor } from '../../Source/EditorStore';
import { commandForKey } from '../../Source/EditorShortcuts';
import { canMergeSelection, selectionCount, selectionSource } from '../../Source/Selection';
import { lineCells, newBoard, type Point } from '../../Source/Model';
const s=()=>useEditor.getState();
const point=(x:number,y=0)=>({x:x*64+16,y:y*64+16});
const pointer=(button=0,shiftKey=false,ctrlKey=false)=>({button,shiftKey,ctrlKey,metaKey:false});
let input:EditorInput;
let latch=vi.fn((point:Point)=>{});
let camera:{x:number;y:number;zoom:number;width:number;height:number};
function click(x:number,y=0,options=pointer()){input.down(options,point(x,y));input.up(options.button,point(x,y));}
function stroke(x:number,y:number,end:number,tool='latch'){s().selectTool(tool);s().paint(lineCells({x,y},{x:end,y}));s().commit();s().selectTool('pointer');}
beforeEach(()=>{
    useEditor.setState({Simulating:false});s().load(newBoard());input=new EditorInput();latch=vi.fn((point:Point)=>{});camera={x:0,y:0,zoom:1,width:640,height:480};
    input.connect({View:camera,world:p=>p,cell:p=>({x:Math.floor(p.x/64),y:Math.floor(p.y/64)}),redraw:()=>{},cursor:()=>{},latch:p=>latch(p)});
});
describe('Pointer-first interaction state machine',()=>{
    it('inspects complete components without placing, and X deletes only the chosen identity',()=>{
        stroke(0,0,3);stroke(0,1,3);const before=s().Undo.length;
        click(1);expect(s().Selection).toEqual({kind:'components',ids:[s().Tiles.get('0,0')!.componentId]});expect(selectionCount(s())).toBe(4);expect(s().Undo.length).toBe(before);
        input.move(point(1,1));input.execute('delete',{x:1,y:1});expect(s().Tiles.size).toBe(4);expect(s().Tiles.has('1,1')).toBe(true);
        s().undo();expect(s().Tiles.size).toBe(8);expect(selectionCount(s())).toBe(4);
    });
    it('does not capture neighboring cells or holes inside a component bounding box',()=>{
        s().selectTool('latch');s().paint([{x:0,y:0},{x:1,y:0},{x:2,y:0},{x:0,y:1},{x:2,y:1},{x:0,y:2},{x:1,y:2},{x:2,y:2}]);s().commit();stroke(1,1,1,'clock');
        click(0);expect(selectionSource(s()).size).toBe(8);expect(selectionSource(s()).has('1,1')).toBe(false);
        click(1,1);expect(selectionCount(s())).toBe(1);
        click(8,8);expect(s().Selection).toBeNull();expect(s().Tiles.size).toBe(9);
    });
    it('uses Shift clicks and additive marquees for complete components, including from Draw',()=>{
        stroke(0,0,4);stroke(0,1,4);stroke(0,3,4);click(0);
        input.down(pointer(0,true),point(2,1));expect(selectionCount(s())).toBe(5);input.up(0,point(2,1));expect(selectionCount(s())).toBe(10);expect(canMergeSelection(s())).toBe(true);
        click(4,1,pointer(0,true));expect(selectionCount(s())).toBe(5);click(8,8,pointer(0,true));expect(selectionCount(s())).toBe(5);
        input.down(pointer(0,true),point(2,1));input.move(point(2,3));input.up(0,point(2,3));expect(selectionCount(s())).toBe(15);
        input.execute('delete',{x:0,y:0});expect(s().Tiles.size).toBe(0);s().undo();expect(selectionCount(s())).toBe(15);
        s().selectTool('clock');input.down(pointer(0,true),point(2,1));input.move(point(3,3));input.up(0,point(3,3));
        expect(selectionCount(s())).toBe(10);expect(s().EditTool).toBe('pointer');expect(s().Tiles.size).toBe(15);
    });
    it('shows merge eligibility only for compatible connected selections and merges in one undo',()=>{
        stroke(0,0,2);stroke(0,1,2);stroke(0,3,2);click(0);click(0,3,pointer(0,true));expect(canMergeSelection(s())).toBe(false);
        click(0,1,pointer(0,true));expect(canMergeSelection(s())).toBe(false);click(0,3,pointer(0,true));expect(canMergeSelection(s())).toBe(true);
        const history=s().Undo.length;expect(s().mergeSelection()).toBe(true);expect(s().Components.size).toBe(2);expect(selectionCount(s())).toBe(6);expect(s().Undo.length).toBe(history+1);
        s().undo();expect(s().Components.size).toBe(3);expect(selectionCount(s())).toBe(6);
    });
    it('supports Ctrl multiselect and moves the group after a screen-space threshold without changing IDs',()=>{
        stroke(0,0,2);stroke(0,1,2);click(0);click(0,1,pointer(0,false,true));expect(selectionCount(s())).toBe(6);
        const ids=s().Selection,history=s().Undo.length;
        input.down(pointer(),point(0));input.move({x:point(0).x+3,y:point(0).y});expect(s().Preview).toBeNull();input.up(0,point(0));expect(s().Undo.length).toBe(history);
        input.down(pointer(),point(0));input.move(point(4,3));input.up(0,point(4,3));expect(s().Selection).toEqual(ids);expect(s().Tiles.has('4,3')).toBe(true);expect(s().Tiles.has('6,4')).toBe(true);expect(s().Undo.length).toBe(history+1);
    });
    it('cancels painting, movement, resizing and marquee without changing cells, selection or history',()=>{
        stroke(0,0,2);click(0);const before=s().export(),selection=s().Selection,history=s().Undo.length;
        input.down(pointer(),point(0));input.move(point(4,2));input.cancel();input.up(0,point(4,2));expect(s().export()).toEqual(before);expect(s().Selection).toEqual(selection);
        input.down(pointer(0,true),point(1));input.move(point(8,3));input.cancel();expect(s().Selection).toEqual(selection);
        s().selectTool('clock');input.down(pointer(),point(0));input.move(point(3));input.cancel();input.up(0,point(3));expect(s().export().tiles).toEqual(before.tiles);expect(s().Undo.length).toBe(history);expect(s().EditTool).toBe('pointer');
        input.down(pointer(),{x:-20*64,y:-14*64});input.move({x:-22*64,y:-16*64});input.cancel();expect(s().Board.grid).toEqual(before.grid);
    });
    it('cancels an unfinished split and keeps completed cuts when returning to Pointer',()=>{
        stroke(0,0,4,'clock');click(0);const selection=s().Selection,history=s().Undo.length;
        input.execute('split',{x:0,y:0});input.down(pointer(),{x:128,y:0});input.move({x:128,y:64});input.cancel();input.up(0,{x:128,y:64});
        expect(s().Selection).toEqual(selection);expect(s().EditTool).toBe('pointer');expect(s().Components.size).toBe(1);expect(s().Undo.length).toBe(history);
        input.execute('split',{x:0,y:0});input.down(pointer(),{x:128,y:0});input.move({x:128,y:64});input.up(0,{x:128,y:64});
        expect(s().EditTool).toBe('split');expect(s().Components.size).toBe(2);const after=s().Selection;
        input.cancel();expect(s().Selection).toEqual(after);expect(s().Undo.length).toBe(history+1);expect(s().Components.size).toBe(2);
    });
    it('right click returns to pointer then clears selection; it never deletes',()=>{
        stroke(0,0,2);click(0);const before=s().export();click(0,0,pointer(2));expect(s().Selection).toBeNull();expect(s().export()).toEqual(before);
        s().selectTool('draw');click(0,0,pointer(2));expect(s().EditTool).toBe('pointer');expect(s().Tiles.size).toBe(3);
    });
    it('copies exact selected members, cancels paste, and returns to pointer after repeated fresh placements',()=>{
        stroke(0,0,1);click(0);s().copy();const selection=s().Selection;input.execute('paste',{x:4,y:2});input.cancel();expect(s().Selection).toEqual(selection);expect(s().Tiles.size).toBe(2);
        for(const x of [4,6]){input.execute('paste',{x,y:2});click(x,2);expect(s().EditTool).toBe('pointer');expect(selectionCount(s())).toBe(2);}
        expect(s().Components.size).toBe(3);click(10,2);expect(s().Tiles.size).toBe(6);
    });
    it('edits all selected members even when a marquee covers only a small portion',()=>{
        stroke(0,0,4,'clock');input.down(pointer(0,true),point(1));input.move(point(2));input.up(0,point(2));
        expect(selectionCount(s())).toBe(5);s().configure({clockHoldTicks:9},true);expect([...s().Tiles.values()].every(t=>t.clockHoldTicks===9)).toBe(true);
    });
    it('pans with Space or middle mouse without changing tools or creating history',()=>{
        s().selectTool('clock');input.space(true);input.down(pointer(),point(2));input.move(point(4,3));input.up(0,point(4,3));input.space(false);
        expect(camera.x).toBe(-128);expect(camera.y).toBe(-192);expect(s().EditTool).toBe('draw');expect(s().Tiles.size).toBe(0);expect(s().Undo).toHaveLength(0);
    });
    it('treats undo of an unfinished stroke as cancellation, ignores mutations in simulation, and keeps latch clicks',()=>{
        stroke(0,0,2);s().selectTool('clock');input.down(pointer(),point(4));input.execute('undo',{x:0,y:0});input.up(0,point(4));expect(s().Tiles.size).toBe(3);expect(s().Undo).toHaveLength(1);
        useEditor.setState({Simulating:true});click(0);input.execute('delete',{x:0,y:0});expect(latch).toHaveBeenCalledWith({x:0,y:0});expect(s().Tiles.size).toBe(3);
    });
    it('cancels only an active cut on undo, then supports undo and redo while Split is idle',()=>{
        stroke(0,0,4);input.execute('split',{x:0,y:0});input.down(pointer(),{x:128,y:0});input.move({x:128,y:64});
        input.execute('undo',{x:0,y:0});input.up(0,{x:128,y:64});expect(s().EditTool).toBe('split');expect(s().Tiles.size).toBe(5);expect(s().Undo.length).toBe(1);
        input.down(pointer(),{x:128,y:0});input.move({x:128,y:64});input.up(0,{x:128,y:64});expect(s().Components.size).toBe(2);
        input.execute('undo',{x:0,y:0});expect(s().Components.size).toBe(1);expect(s().EditTool).toBe('split');
        input.execute('redo',{x:0,y:0});expect(s().Components.size).toBe(2);expect(s().EditTool).toBe('split');
        input.cancel();input.execute('merge',{x:0,y:0});const tiles=s().Tiles;input.execute('redo',{x:0,y:0});expect(s().Tiles).toBe(tiles);expect(s().EditTool).toBe('merge');
    });
    it('maps nearby shortcuts and leaves retired canvas keys unbound',()=>{
        const key=(key:string,ctrlKey=false,shiftKey=false)=>commandForKey({key,ctrlKey,metaKey:false,shiftKey,altKey:false});
        expect(key('x')).toBe('delete');expect(key('x',true)).toBe('cut');expect(key('g',false,true)).toBe('split');expect(key('z',true,true)).toBe('redo');
        for(const old of ['Escape','Delete','Backspace','Enter'])expect(key(old)).toBeUndefined();expect(key('u',true)).toBeUndefined();
    });
});
