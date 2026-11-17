import { beforeEach, expect, it } from 'vitest';
import { canonicalToolId, Inks, inkColor, newBoard, SelectableToolIds, ToolKinds, TraceToolIds, validateProject } from '../../Source/Model';
import { useEditor } from '../../Source/EditorStore';
import { encodeBoard } from '../../Source/Native';
beforeEach(() => { useEditor.setState({ Simulating: false }); useEditor.getState().load(newBoard()); });
it('exposes eight Trace colors and a single Bus with stable numeric kinds', () => {
    expect(TraceToolIds).toHaveLength(8);
    expect(Inks.find(ink => ink.id === 'trace')?.variants).toEqual(TraceToolIds);
    expect(Inks.find(ink => ink.id === 'bus')?.variants).toBeUndefined();
    expect(SelectableToolIds.filter(id => id.startsWith('bus'))).toEqual(['bus']);
    expect(TraceToolIds.map(id => ToolKinds[id])).toEqual([1,2,3,4,5,6,28,29]);
    expect([ToolKinds.cross,ToolKinds.switch,ToolKinds.led]).toEqual([13,30,27]);
    expect(Object.values(ToolKinds)).not.toContain(14);
    for (const id of TraceToolIds) {
        const rgb = inkColor(id).slice(1).match(/../g)!.map(value => parseInt(value,16));
        expect(rgb[0]*.2126+rgb[1]*.7152+rgb[2]*.0722).toBeLessThanOrEqual(160);
    }
});
it('rejects obsolete archives and removed port inks',()=>{
    const legacy={...newBoard()} as Partial<ReturnType<typeof newBoard>>;delete legacy.circuitModel;
    expect(()=>validateProject({board:legacy})).toThrow('ProjectBoardInvalid');
    for(const toolId of ['read','write','busRed']) expect(()=>validateProject({board:{...newBoard(),tiles:[{x:0,y:0,toolId,componentId:1,isOn:false}]}})).toThrow();
});
it('retains switch direction and Trace source/default parameters through history and the binary protocol',()=>{
    const state=()=>useEditor.getState();state().selectTool('switch');state().configure({direction:1});state().paint([{x:0,y:0}]);state().commit();state().selectAll();state().rotate(1);expect(state().Tiles.get('0,0')?.direction).toBe(2);state().undo();expect(state().Tiles.get('0,0')?.direction).toBe(1);
    state().copy();state().paste({x:3,y:0});state().confirmPaste();expect(state().Tiles.get('3,0')?.direction).toBe(1);
    state().selectTool('traceRed');state().configure({fixedDrive:false,defaultValue:true});state().paint([{x:0,y:2}]);state().commit();const project=state().exportProject();state().load(project);expect(state().Tiles.get('0,2')).toMatchObject({fixedDrive:false,defaultValue:true});
    const data=new DataView(encodeBoard(state().export()).buffer);expect(data.getInt32(4,true)).toBe(4);const count=(data.byteLength-24)/32;expect([...new Int32Array(data.buffer,24+count*5*4,count)]).toContain(0);expect([...new Int32Array(data.buffer,24+count*6*4,count)]).toContain(1);
});
it('keeps new colors through component editing, blueprints, paste and undo', () => {
    const state = () => useEditor.getState();
    for(const [x,tool] of ['traceOrange','traceWhite'].entries()) {
        state().selectTool(tool); state().paint([{x,y:0}]); state().commit();
    }
    state().selectAll(); expect(state().createBlueprint('Eight-color wiring')).toBe(true);
    state().useBlueprint(state().Blueprints[0].id); state().paste({x:4,y:2}); expect(state().confirmPaste()).toBe(true);
    expect(state().Tiles.get('4,2')?.toolId).toBe('traceOrange');
    expect(state().Tiles.get('5,2')?.toolId).toBe('traceWhite');
    state().configure({toolId:'traceWhite'},true);
    expect(state().Tiles.get('4,2')?.toolId).toBe('traceWhite');
    state().undo(); expect(state().Tiles.get('4,2')?.toolId).toBe('traceOrange');
    const project = state().exportProject(); state().load(project); expect(state().exportProject()).toEqual(project);
});
it('keeps draw defaults specific to each ink and resets them when loading', () => {
    const state = () => useEditor.getState();
    state().selectTool('trace');
    state().configure({ fixedDrive: false, defaultValue: true });
    state().selectTool('clock');
    state().configure({ clockHoldTicks: 7 });
    state().paint([{ x: 0, y: 0 }]); state().commit();
    expect(state().Tiles.get('0,0')).toMatchObject({ toolId: 'clock', clockHoldTicks: 7 });
    expect(state().Tiles.get('0,0')).not.toHaveProperty('fixedDrive');
    state().selectTool('cross'); state().configure({ crossMask: 129 });
    state().paint([{ x: 2, y: 0 }]); state().commit();
    expect(state().Tiles.get('2,0')?.crossMask).toBe(129);
    state().load(newBoard());
    expect(state().DrawSettings).toEqual({});
});
