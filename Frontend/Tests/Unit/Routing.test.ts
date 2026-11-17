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
    expect([ToolKinds.cross,ToolKinds.read,ToolKinds.write,ToolKinds.led]).toEqual([13,15,16,27]);
    expect(Object.values(ToolKinds)).not.toContain(14);
    for (const id of TraceToolIds) {
        const rgb = inkColor(id).slice(1).match(/../g)!.map(value => parseInt(value,16));
        expect(rgb[0]*.2126+rgb[1]*.7152+rgb[2]*.0722).toBeLessThanOrEqual(160);
    }
});
it('normalizes historical Bus colors in boards and blueprints while keeping independent IDs', () => {
    const aliases = ['bus','busRed','busGreen','busYellow','busCyan','busMagenta'];
    const tiles = aliases.map((toolId,x) => ({ x,y:0,toolId,componentId:x+1,isOn:false }));
    const source = { board:{...newBoard(),selectedTool:'busYellow',tiles}, blueprints:[{id:'b',name:'Bus',width:6,height:1,tiles}] };
    const project = validateProject(source);
    expect(project.board.selectedTool).toBe('bus');
    for(const group of [project.board.tiles,project.blueprints[0].tiles]) {
        expect(group.map(tile=>tile.toolId)).toEqual(Array(6).fill('bus'));
        expect(group.map(tile=>tile.componentId)).toEqual([1,2,3,4,5,6]);
    }
    expect(source.board.tiles.map(tile=>tile.toolId)).toEqual(aliases);
    for(const id of aliases) { expect(canonicalToolId(id)).toBe('bus'); expect(inkColor(id)).toBe(inkColor('bus')); }
    const data = new DataView(encodeBoard(source.board).buffer);
    expect([...new Int32Array(data.buffer,24,6)]).toEqual(Array(6).fill(7));
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
