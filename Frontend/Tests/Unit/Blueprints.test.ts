import { beforeEach, describe, expect, it } from 'vitest';
import { useEditor } from '../../Source/EditorStore';
import { newBoard, validateProject } from '../../Source/Model';
import { loadRenderMode } from '../../Source/Preferences';
const state = () => useEditor.getState();
beforeEach(() => { useEditor.setState({ Simulating: false }); state().load(newBoard()); });
describe('Project blueprints', () => {
    function create() {
        state().selectTool('clock'); state().configure({ clockHoldTicks: 9 }); state().paint([{ x: -2, y: -1 }]); state().commit();
        state().selectTool('clock'); state().configure({ clockHoldTicks: 17 }); state().paint([{ x: 0, y: 0 }]); state().commit();
        state().select({ originX: -3, originY: -2, width: 5, height: 4 });
        expect(state().createBlueprint('Circuit')).toBe(true);
        return state().Blueprints[0];
    }
    it('keeps whitespace, parameters, independent placements and clipboard snapshots', () => {
        const blueprint = create();
        expect(blueprint).toMatchObject({ width: 5, height: 4, tiles: [{ x: 1, y: 1, clockHoldTicks: 9 }, { x: 3, y: 2, clockHoldTicks: 17 }] });
        state().useBlueprint(blueprint.id);
        expect(state().ClipboardOrigin).toBe('blueprint');
        state().paste({ x: 3, y: 2 }); const source = state().Preview!.Source;
        state().paste({ x: 4, y: 2 }); expect(state().Preview!.Source).toBe(source);
        expect(state().confirmPaste()).toBe(true);
        state().paste({ x: 10, y: 3 }); expect(state().confirmPaste()).toBe(true);
        state().deleteBlueprint(blueprint.id); expect(state().Blueprints).toHaveLength(0);
        expect(state().Tiles.get('5,3')?.clockHoldTicks).toBe(9);
        expect(state().Tiles.get('13,5')?.clockHoldTicks).toBe(17);
        state().undo(); expect(state().Blueprints).toHaveLength(1);
        state().undo(); expect(state().Tiles.has('13,5')).toBe(false);
        expect(state().Tiles.has('5,3')).toBe(true);
    });
    it('round-trips as a project and tracks management commands', () => {
        const blueprint = create(); state().renameBlueprint(blueprint.id, 'Renamed');
        state().undo(); expect(state().Blueprints[0].name).toBe('Circuit');
        state().redo(); expect(state().Blueprints[0].name).toBe('Renamed');
        const project = JSON.parse(JSON.stringify(state().exportProject())); state().load(project);
        expect(state().exportProject()).toEqual(project); expect(state().Clipboard).toHaveLength(0);
        state().load(newBoard()); expect(state().Blueprints).toHaveLength(0);
    });
    it('rejects malformed blueprints without replacing the document', () => {
        const blueprint = create(), original = state().exportProject();
        for (const invalid of [{ ...blueprint, tiles: [] }, { ...blueprint, name: ' ' }, { ...blueprint, width: 0 }, { ...blueprint, tiles: [blueprint.tiles[0], blueprint.tiles[0]] }, { ...blueprint, tiles: [{ ...blueprint.tiles[0], clockHoldTicks: undefined }] }]) {
            expect(() => state().load({ board: newBoard(), blueprints: [invalid] })).toThrow('ProjectBlueprintInvalid');
            expect(state().exportProject()).toEqual(original);
        }
        expect(validateProject({ board: newBoard() }).blueprints).toEqual([]);
    });
    it('creates from clipboard and preserves the global display preference across projects', () => {
        create(); state().copy(); expect(state().createBlueprint('Clipboard', true)).toBe(true);
        state().setRenderMode('2d'); state().load(newBoard()); expect(state().RenderMode).toBe('2d'); expect(loadRenderMode()).toBe('2d');
        state().setRenderMode('2.5d');
    });
});
