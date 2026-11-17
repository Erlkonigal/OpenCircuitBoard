import { beforeEach, describe, expect, it } from 'vitest';
import { EditorInput } from '../../Source/EditorInput';
import { useEditor } from '../../Source/EditorStore';
import { newBoard, type Point } from '../../Source/Model';
import { selectionCount } from '../../Source/Selection';
const state = () => useEditor.getState();
const screen = (p: Point) => ({ x: p.x * 64 + 16, y: p.y * 64 + 16 });
const pointer = (shiftKey = false) => ({ button: 0, shiftKey });
let input: EditorInput;
function rectangle(start: Point, end: Point) {
    input.down(pointer(true), screen(start)); input.move(screen(end)); input.up(0, screen(end));
}
beforeEach(() => {
    useEditor.setState({ Simulating: false }); state().load(newBoard()); state().selectTool('clock');
    input = new EditorInput();
    input.connect({ View: { x: 0, y: 0, zoom: 1, width: 640, height: 480 }, world: p => p,
        cell: p => ({ x: Math.floor(p.x / 64), y: Math.floor(p.y / 64) }), redraw: () => {}, cursor: () => {}, button: () => {} });
});
describe('Filled ink rectangles', () => {
    for (const end of [{ x: 3, y: 2 }, { x: -3, y: 2 }, { x: 3, y: -2 }, { x: -3, y: -2 }])
        it('fills inclusive endpoints in direction ' + JSON.stringify(end) + ' as one component and undo step', () => {
            rectangle({ x: 0, y: 0 }, end);
            expect(state().Tiles.size).toBe(12); expect(state().Components.size).toBe(1); expect(state().Undo).toHaveLength(1);
            expect(state().Tiles.has(end.x + ',' + end.y)).toBe(true); expect(state().RectanglePaint).toBeNull(); expect(state().EditTool).toBe('draw');
            const after = state().export(); state().undo(); expect(state().Tiles.size).toBe(0); state().redo(); expect(state().export()).toEqual(after);
        });
    it('previews shrinking and million-cell rectangles without changing document, IDs or history', () => {
        const board = newBoard(); board.grid = { originX: -1024, originY: -1024, width: 2048, height: 2048 }; state().load(board); state().selectTool('clock');
        const tiles = state().Tiles, next = state().Ids.Next;
        input.down(pointer(true), screen({ x: 0, y: 0 })); input.move(screen({ x: 1023, y: 1023 }));
        expect(state().RectanglePaint?.Bounds).toEqual({ originX: 0, originY: 0, width: 1024, height: 1024 });
        expect(state().Tiles).toBe(tiles); expect(state().Ids.Next).toBe(next); expect(state().Undo).toHaveLength(0);
        input.move(screen({ x: 1, y: 1 })); input.up(0, screen({ x: 1, y: 1 }));
        expect(state().Tiles.size).toBe(4); expect(state().Tiles.has('2,2')).toBe(false); expect(state().Undo).toHaveLength(1);
    });
    it('clips both endpoints and inherits the nearest in-board starting cell', () => {
        state().paint([{ x: 19, y: 13 }]); state().commit(); const id = state().Tiles.get('19,13')!.componentId;
        state().configure({ clockHoldTicks: 9 });
        rectangle({ x: 25, y: 20 }, { x: 18, y: 12 });
        expect(state().Tiles.size).toBe(4); expect(state().Components.size).toBe(1);
        expect([...state().Tiles.values()].every(t => t.componentId === id && t.clockHoldTicks === 1)).toBe(true);
        state().selectTool('draw'); rectangle({ x: 25, y: 20 }, { x: 24, y: 19 });
        expect(state().Undo).toHaveLength(2); expect(state().RectanglePaint).toBeNull(); expect(state().Active).toBeNull();
    });
    it('keeps the original anchor and merges whole compatible targets outside a reverse rectangle', () => {
        state().paint([{ x: 3, y: 2 }]); state().commit(); const anchor = state().Tiles.get('3,2')!.componentId;
        state().paint([{ x: 0, y: 0 }, { x: -1, y: 0 }, { x: -2, y: 0 }]); state().commit();
        const before = state().export(), history = state().Undo.length;
        state().configure({ clockHoldTicks: 8 }); rectangle({ x: 3, y: 2 }, { x: 0, y: 0 });
        expect(state().Tiles.size).toBe(14); expect(state().Components.size).toBe(1); expect(state().Tiles.get('-2,0')?.componentId).toBe(anchor);
        expect([...state().Tiles.values()].every(t => t.clockHoldTicks === 1)).toBe(true); expect(state().Undo.length).toBe(history + 1);
        state().undo(); expect(state().export().tiles).toEqual(before.tiles); state().redo(); expect(state().Components.size).toBe(1);
    });
    it('replaces only covered incompatible cells and keeps untouched survivors independent', () => {
        state().paint([{ x: -2, y: 0 }, { x: -1, y: 0 }, { x: 0, y: 0 }, { x: 1, y: 0 }, { x: 2, y: 0 }]); state().commit();
        const before = state().export(); state().selectTool('button'); rectangle({ x: 0, y: -1 }, { x: 0, y: 1 });
        expect(state().Tiles.size).toBe(7); expect(state().Components.size).toBe(3);
        expect(state().Tiles.get('-1,0')?.componentId).not.toBe(state().Tiles.get('1,0')?.componentId);
        state().undo(); expect(state().export().tiles).toEqual(before.tiles);
    });
    it('does not merge side contacts or a compatible component entered from empty space', () => {
        state().paint([{ x: 2, y: 0 }, { x: 3, y: 0 }]); state().commit(); const other = state().Tiles.get('3,0')!.componentId;
        rectangle({ x: 0, y: 0 }, { x: 2, y: 1 });
        expect(state().Tiles.get('3,0')?.componentId).toBe(other); expect(state().Tiles.get('2,0')?.componentId).not.toBe(other);
        expect(state().Components.size).toBe(2);
    });
    it('draws a single cell and commits final release coordinates without a last move event', () => {
        rectangle({ x: 0, y: 0 }, { x: 0, y: 0 }); expect(state().Tiles.size).toBe(1);
        input.down(pointer(true), screen({ x: 4, y: 4 })); input.up(0, screen({ x: 5, y: 5 }));
        expect(state().Tiles.size).toBe(5); expect(state().Components.size).toBe(2);
    });
    for (const action of ['cancel', 'undo', 'pointer'] as const)
        it('clears an unfinished rectangle on ' + action + ' without changing earlier history', () => {
            rectangle({ x: 0, y: 0 }, { x: 0, y: 0 }); const before = state().export();
            input.down(pointer(true), screen({ x: 2, y: 2 })); input.move(screen({ x: 6, y: 6 }));
            input.execute(action, { x: 0, y: 0 }); input.up(0, screen({ x: 6, y: 6 }));
            expect(state().export()).toEqual(before); expect(state().Undo).toHaveLength(1); expect(state().RectanglePaint).toBeNull(); expect(state().Gesture).toBe('idle');
        });
    it('uses Pointer drags starting on unselected cells to select, then moves only already-selected groups', () => {
        rectangle({ x: 0, y: 0 }, { x: 1, y: 1 }); rectangle({ x: 2, y: 0 }, { x: 2, y: 1 }); state().selectTool('pointer');
        const before = state().export(), history = state().Undo.length;
        input.down(pointer(), screen({ x: 0, y: 0 })); input.move(screen({ x: 2, y: 1 }));
        expect(state().Gesture).toBe('marquee'); expect(state().Preview).toBeNull(); input.up(0, screen({ x: 2, y: 1 }));
        expect(selectionCount(state())).toBe(6); expect(state().export()).toEqual(before); expect(state().Undo.length).toBe(history);
        input.down(pointer(), screen({ x: 0, y: 0 })); input.move(screen({ x: 4, y: 3 })); input.up(0, screen({ x: 4, y: 3 }));
        expect(state().Tiles.has('4,3')).toBe(true); expect(state().Tiles.has('6,4')).toBe(true); expect(selectionCount(state())).toBe(6);
        expect(state().Undo.length).toBe(history + 1);
    });
    it('keeps selection until marquee release and restores it on cancellation', () => {
        rectangle({ x: 0, y: 0 }, { x: 1, y: 1 }); state().selectTool('pointer'); state().selectAll(); const selection = state().Selection;
        input.down(pointer(), screen({ x: 5, y: 5 })); input.move(screen({ x: 8, y: 8 })); input.cancel();
        expect(state().Selection).toEqual(selection);
        input.down(pointer(), screen({ x: 5, y: 5 })); input.up(0, screen({ x: 5, y: 5 })); expect(state().Selection).toBeNull();
    });
});
