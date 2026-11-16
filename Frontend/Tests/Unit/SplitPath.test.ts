import { beforeEach, describe, expect, it } from 'vitest';
import { gridLine, SplitPath } from '../../Source/SplitPath';
import { useEditor } from '../../Source/EditorStore';
import { newBoard, validateProject, type Point, type Tile } from '../../Source/Model';
const s = () => useEditor.getState();
function path(...points: Point[]) { const cut = new SplitPath(points[0]); for (const point of points.slice(1)) cut.append(point); return cut; }
function rectangle(x: number, y: number, width: number, height: number, id = 7): Tile[] {
    return Array.from({ length: width * height }, (_, i) => ({ x: x + i % width, y: y + Math.floor(i / width), toolId: 'clock', componentId: id, isOn: true, clockHoldTicks: 3 }));
}
function load(tiles: Tile[]) { s().load({ ...newBoard(), tiles }); s().selectTool('split'); }
function ids() { return [...s().Components.ids()]; }
beforeEach(() => { useEditor.setState({ Simulating: false }); });
describe('Grid-edge split paths', () => {
    it('fills fast and diagonal movements with reversible, four-connected grid edges', () => {
        const a = { x: -5, y: 3 }, b = { x: 8, y: -2 }, forward = gridLine(a, b);
        expect(forward).toEqual(gridLine(b, a).reverse()); expect(forward).toHaveLength(19);
        for (let i = 1; i < forward.length; i++) expect(Math.abs(forward[i].x - forward[i - 1].x) + Math.abs(forward[i].y - forward[i - 1].y)).toBe(1);
        const cut = path(a, b), keys = [...cut.Edges.keys()].sort(); cut.append(a); expect(cut.Edges.size).toBe(0); expect(cut.Last).toEqual(a); cut.append(b); expect([...cut.Edges.keys()].sort()).toEqual(keys);
        expect([...path(b, a).Edges.keys()].sort()).toEqual(keys);
    });
    it('retracts the tail one step at a time across corners and can grow in a new direction', () => {
        const cut = path({ x: 0, y: 0 }, { x: 3, y: 0 }, { x: 3, y: 2 });
        expect(cut.Edges.size).toBe(5); cut.append({ x: 3, y: 1 }); expect(cut.Edges.size).toBe(4);
        cut.append({ x: 3, y: 0 }); cut.append({ x: 1, y: 0 }); expect(cut.Edges.size).toBe(1); expect(cut.Last).toEqual({ x: 1, y: 0 });
        cut.append({ x: 1, y: 2 }); expect(cut.Edges.size).toBe(3); expect(cut.Last).toEqual({ x: 1, y: 2 });
        expect([...cut.Edges.values()].map(edge => [edge.Start, edge.End])).toEqual([
            [{ x: 0, y: 0 }, { x: 1, y: 0 }], [{ x: 1, y: 0 }, { x: 1, y: 1 }], [{ x: 1, y: 1 }, { x: 1, y: 2 }]
        ]);
    });
    it('keeps an earlier occurrence of an edge when retracting an overlapping tail', () => {
        const cut = path({ x: 0, y: 0 }, { x: 1, y: 0 }, { x: 1, y: 1 }, { x: 0, y: 1 }, { x: 0, y: 0 });
        const loop = [...cut.Edges.keys()].sort(); expect(cut.Edges.size).toBe(4);
        cut.append({ x: 1, y: 0 }); cut.append({ x: 0, y: 0 }); expect([...cut.Edges.keys()].sort()).toEqual(loop);
        cut.append({ x: 0, y: 1 }); expect(cut.Edges.size).toBe(3);
        cut.append({ x: 1, y: 1 }); cut.append({ x: 1, y: 0 }); cut.append({ x: 0, y: 0 }); expect(cut.Edges.size).toBe(0);
    });
    it('uses only the remaining line after backtracking and redirection', () => {
        load(rectangle(0, 0, 5, 2));
        const cut = path({ x: 2, y: 0 }, { x: 2, y: 2 }, { x: 2, y: 0 }, { x: 3, y: 0 }, { x: 3, y: 2 });
        expect(s().splitAlong(cut)).toBe(true); expect(s().Components.size).toBe(2); expect(s().Components.count(7)).toBe(6);
        expect(s().Tiles.get('2,0')!.componentId).toBe(7); expect(s().Tiles.get('3,0')!.componentId).not.toBe(7);
    });
    it('treats an entirely retracted line as an empty gesture and preserves redo', () => {
        load(rectangle(0, 0, 4, 2)); s().splitAlong(path({ x: 2, y: 0 }, { x: 2, y: 2 })); s().undo();
        const before = s().exportProject(), selection = s().Selection;
        s().begin(); expect(s().splitAlong(path({ x: 2, y: 0 }, { x: 2, y: 2 }, { x: 2, y: 0 }))).toBe(false);
        expect(s().exportProject()).toEqual(before); expect(s().Selection).toEqual(selection); expect(s().Undo).toHaveLength(0); expect(s().Redo).toHaveLength(1);
        expect(s().Active).toBeNull(); expect(s().SplitNotice).toBe(''); expect(s().EditTool).toBe('split');
    });
    it('cuts a bent boundary without deleting cells and keeps the largest region identity', () => {
        load(rectangle(0, 0, 6, 4)); const before = s().exportProject();
        expect(s().splitAlong(path({ x: 2, y: 0 }, { x: 2, y: 2 }, { x: 4, y: 2 }, { x: 4, y: 4 }))).toBe(true);
        expect(s().Components.size).toBe(2); expect(s().Tiles.size).toBe(24); expect(s().Components.count(7)).toBe(12);
        expect(s().Tiles.get('0,0')!.componentId).toBe(7); expect(s().Tiles.get('5,0')!.componentId).not.toBe(7);
        expect(s().Undo).toHaveLength(1); expect(s().EditTool).toBe('split'); expect(validateProject(s().exportProject())).toEqual(s().exportProject());
        s().undo(); expect(s().exportProject()).toEqual(before); s().redo(); expect(s().Components.size).toBe(2);
    });
    it('does not extend an incomplete line or persist any partial barrier', () => {
        load(rectangle(0, 0, 4, 4)); const before = s().exportProject();
        for (const cut of [path({ x: 2, y: 0 }, { x: 2, y: 2 }), path({ x: 1, y: 1 }, { x: 3, y: 1 }), path({ x: 0, y: 0 }, { x: 4, y: 0 })]) {
            expect(s().splitAlong(cut)).toBe(false); expect(s().exportProject()).toEqual(before); expect(s().Undo).toHaveLength(0);
            expect(s().SplitNotice).toContain('did not cut'); expect(s().EditTool).toBe('split');
        }
    });
    it('supports closed loops, self-crossing strokes and repeated traversal', () => {
        load(rectangle(0, 0, 3, 3));
        const loop = path({ x: 1, y: 1 }, { x: 2, y: 1 }, { x: 2, y: 2 }, { x: 1, y: 2 }, { x: 1, y: 1 });
        expect(s().splitAlong(loop)).toBe(true); expect(s().Components.count(7)).toBe(8); expect(s().Tiles.get('1,1')!.componentId).not.toBe(7);
        s().undo(); const cross = path({ x: 1, y: 0 }, { x: 1, y: 3 }, { x: -1, y: 3 }, { x: -1, y: 1 }, { x: 3, y: 1 });
        expect(s().splitAlong(cross)).toBe(true); expect(s().Components.size).toBe(4); expect(s().Tiles.size).toBe(9);
    });
    it('partitions every crossed component independently of the current selection', () => {
        load([...rectangle(0, 0, 4, 1, 7), ...rectangle(0, 3, 4, 1, 8), ...rectangle(10, 0, 2, 1, 9)]);
        s().selectComponents([9]); expect(s().splitAlong(path({ x: 2, y: 0 }, { x: 2, y: 4 }))).toBe(true);
        expect(s().Components.size).toBe(5); expect(s().Components.count(7)).toBe(2); expect(s().Components.count(8)).toBe(2); expect(s().Components.count(9)).toBe(2);
        expect(s().Selection!.ids).toHaveLength(4); expect(s().Selection!.ids).not.toContain(9); expect(s().Undo).toHaveLength(1);
    });
    it('can split more than twice, follows signed chunk boundaries and round-trips flat blueprint snapshots', () => {
        s().load({ ...newBoard(), grid: { originX: -70, originY: -4, width: 90, height: 12 }, tiles: rectangle(-65, -1, 4, 2) }); s().selectTool('split');
        const cut = path({ x: -64, y: -1 }, { x: -64, y: 1 }, { x: -62, y: 1 }, { x: -62, y: -1 });
        expect(s().splitAlong(cut)).toBe(true); expect(s().Components.size).toBe(3); expect(s().Components.count(7)).toBe(4);
        s().selectTool('pointer'); expect(s().copy()).toBe(true); expect(s().createBlueprint('Pieces')).toBe(true);
        const project = s().exportProject(); expect(validateProject(JSON.parse(JSON.stringify(project)))).toEqual(project);
        s().load(project); expect(ids()).toHaveLength(3); expect(new Set(s().Blueprints[0].tiles.map(t => t.componentId)).size).toBe(3);
    });
    it('does not merge different component identities when crossing their existing contact', () => {
        load([...rectangle(0, 0, 2, 2, 7), ...rectangle(2, 0, 2, 2, 8)]); const before = s().exportProject();
        expect(s().splitAlong(path({ x: 2, y: 0 }, { x: 2, y: 2 }))).toBe(false); expect(s().exportProject()).toEqual(before);
    });
    it('uses literal connectivity around holes and never cuts during simulation', () => {
        load(rectangle(0, 0, 3, 3).filter(t => t.x !== 1 || t.y !== 1));
        expect(s().splitAlong(path({ x: 1, y: 0 }, { x: 1, y: 1 }))).toBe(false);
        expect(s().splitAlong(path({ x: 1, y: 0 }, { x: 1, y: 3 }))).toBe(true); expect(s().Components.size).toBe(2);
        const before = s().exportProject(); useEditor.setState({ Simulating: true });
        expect(s().splitAlong(path({ x: 2, y: 0 }, { x: 2, y: 3 }))).toBe(false); expect(s().exportProject()).toEqual(before);
    });
});
