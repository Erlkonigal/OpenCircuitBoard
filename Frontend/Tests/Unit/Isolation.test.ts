import { beforeEach, describe, expect, it } from 'vitest';
import { useEditor } from '../../Source/EditorStore';
import { edgeKey, newBoard, ToolKinds, validateBoard, validateProject, type IsolationEdge } from '../../Source/Model';
import { edgeLine, IsolationStore, nearestEdge } from '../../Source/IsolationStore';
import { encodeBoard } from '../../Source/Native';
const state = () => useEditor.getState();
const vertical = (x: number, y: number): IsolationEdge => ({ x, y, axis: 'vertical' });
const horizontal = (x: number, y: number): IsolationEdge => ({ x, y, axis: 'horizontal' });
beforeEach(() => { useEditor.setState({ Simulating: false }); state().load(newBoard()); });
describe('Independent isolation boundaries', () => {
    it('snap and axis-locked drags fill intermediate segments on signed coordinates', () => {
        expect(nearestEdge({ x: -63, y: 15 })).toEqual(vertical(-1, 0));
        expect(nearestEdge({ x: 15, y: -63 })).toEqual(horizontal(0, -1));
        expect(edgeLine(vertical(-1, 2), { x: 1000, y: -120 })).toEqual([-2,-1,0,1,2].map(y => vertical(-1,y)));
    });
    it('keeps edges in empty space and preserves them when cells are erased', () => {
        state().paintIsolation([vertical(0,0)]); state().commit();
        expect(state().Tiles.size).toBe(0); expect(state().Isolation.size).toBe(1);
        state().paint([{x:0,y:0}]); state().commit(); state().paint([{x:0,y:0}],true); state().commit();
        expect(state().Isolation.size).toBe(1);
        state().paintIsolation([vertical(0,0)],true); state().cancel(); expect(state().Isolation.size).toBe(1);
        state().paintIsolation([vertical(0,0)],true); state().commit(); expect(state().Isolation.size).toBe(0);
        state().undo(); expect(state().Isolation.size).toBe(1); state().redo(); expect(state().Isolation.size).toBe(0);
    });
    it('copies the complete perimeter, supports edge-only blueprints, and deduplicates pastes', () => {
        const edges = [horizontal(0,0), horizontal(0,1), vertical(0,0), vertical(1,0)];
        state().paintIsolation(edges); state().commit(); state().select({ originX:0,originY:0,width:1,height:1 });
        expect(state().Selection?.isolationEdges).toHaveLength(4); expect(state().copy()).toBe(true);
        expect(state().Clipboard[0].isolationEdges).toEqual(expect.arrayContaining(edges));
        expect(state().createBlueprint('Boundary',true)).toBe(true);
        state().useBlueprint(state().Blueprints[0].id); state().paste({x:3,y:2}); expect(state().confirmPaste()).toBe(true);
        expect(state().Isolation.size).toBe(8); state().paste({x:3,y:2}); expect(state().confirmPaste()).toBe(true); expect(state().Isolation.size).toBe(8);
        expect(state().exportProject().blueprints[0].tiles).toEqual([]);
        state().load(JSON.parse(JSON.stringify(state().exportProject()))); expect(state().Isolation.size).toBe(8);
    });
    it('cuts and moves edges including the selected perimeter and restores them on undo', () => {
        state().paintIsolation([vertical(1,0)]); state().commit(); state().select({originX:0,originY:0,width:1,height:1});
        expect(state().confirmMove({x:2,y:1})).toBe(true); expect(state().Isolation.get(edgeKey(vertical(3,1)))).toBeDefined(); expect(state().Isolation.size).toBe(1);
        state().undo(); expect(state().Isolation.get(edgeKey(vertical(1,0)))).toBeDefined();
        state().copy(true); expect(state().Isolation.size).toBe(0); state().undo(); expect(state().Isolation.size).toBe(1);
    });
    it('rejects paste and canvas resizing that would clip edges and keeps simulation read-only', () => {
        state().paintIsolation([vertical(20,0)]); state().commit();
        expect(state().resize({originX:-20,originY:-14,width:39,height:28})).toBe(false);
        state().select({originX:19,originY:0,width:1,height:1}); state().copy(); state().paste({x:20,y:0}); expect(state().confirmPaste()).toBe(false);
        useEditor.setState({ Simulating:true }); state().paintIsolation([vertical(0,0)]); state().deleteSelection(); expect(state().Isolation.size).toBe(1);
    });
    it('rejects unknown modules uniformly and serializes canonical masks with stable kinds', () => {
        for (const id of ['mesh','undefined']) {
            expect(() => validateBoard({...newBoard(), tiles:[{x:0,y:0,toolId:id,isOn:false}]})).toThrow('ProjectBoardInvalid');
            expect(() => validateProject({board:newBoard(),blueprints:[{id:'x',name:'x',width:1,height:1,tiles:[{x:0,y:0,toolId:id,isOn:false}]}]})).toThrow('ProjectBlueprintInvalid');
        }
        const board = {...newBoard(), tiles:[{x:-2,y:-1,toolId:'latch',isOn:false},{x:-1,y:0,toolId:'latch',isOn:false}], isolationEdges:[vertical(-1,-1),horizontal(-2,0)]};
        const bytes = encodeBoard(board), data = new DataView(bytes.buffer);
        expect(data.getInt32(4,true)).toBe(2); expect(data.getInt32(24+4*3*4,true)).toBe(3);
        expect(ToolKinds.latch).toBe(25); expect(ToolKinds.read).toBe(15); expect(ToolKinds.mesh).toBeUndefined();
        const previous = state().exportProject(); expect(() => state().load({...board, isolationEdges:[vertical(30,0)]})).toThrow(); expect(state().exportProject()).toEqual(previous);
    });
    it('shares chunks outside local changes and queries only the requested perimeter', () => {
        const store = IsolationStore.from([vertical(-1000000,-1000000),horizontal(1000000,1000000),vertical(1,0)]);
        const next = store.update([horizontal(0,0)]);
        expect(next.chunk(-15625,-15625)).toBe(store.chunk(-15625,-15625));
        expect([...next.query({originX:0,originY:0,width:1,height:1})]).toEqual(expect.arrayContaining([horizontal(0,0),vertical(1,0)]));
        expect([...next.chunks({originX:0,originY:0,width:1,height:1})]).toHaveLength(1);
    });
});
