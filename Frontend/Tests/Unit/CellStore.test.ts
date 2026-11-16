import { describe, expect, it } from 'vitest';
import { CellStore } from '../../Source/CellStore';
import { cellKey, type Tile } from '../../Source/Model';
const tile = (x: number, y: number): Tile => ({ x, y, toolId: 'or', componentId: 1, isOn: true });
describe('Persistent sparse spatial index', () => {
    it('shares unaffected chunks and diffs only changed paths', () => {
        const source = CellStore.from([tile(-65, -64), tile(-1, 0), tile(64, 64)]);
        const next = source.update([['-65,-64', tile(-65, -64)], ['0,0', tile(0, 0)]]);
        expect(next.chunk(1, 1)).toBe(source.chunk(1, 1)); expect(source.has('0,0')).toBe(false);
        expect([...next.changes(source)].map(change => change.key)).toEqual(['0,0']);
        expect([...next.query({ originX: -66, originY: -64, width: 3, height: 1 })]).toEqual([tile(-65, -64)]);
        expect(source.Bounds).toEqual({ originX: -65, originY: -64, width: 130, height: 129 });
    });
    it('finds aggregate blocks without enumerating leaf tiles over huge sparse spans', () => {
        const source = CellStore.from([tile(-1000000000, -1000000000), tile(1000000000, 1000000000)]);
        const bounds = { originX: -2147483648, originY: -2147483648, width: 4294967295, height: 4294967295 };
        expect([...source.blocks(bounds, 24)]).toHaveLength(2);
        expect([...source.chunks()]).toHaveLength(2);
    });
    it('bitset collision checks match per-cell checks across signed chunk boundaries and arbitrary offsets', () => {
        const source = CellStore.from(Array.from({ length: 150 }, (_, i) => tile(i * 7 % 131 - 66, i * 11 % 93 - 47)));
        const target = CellStore.from(Array.from({ length: 220 }, (_, i) => tile(i * 13 % 151 - 75, i * 17 % 119 - 60)));
        for (let x = -67; x <= 67; x += 7) for (let y = -4; y <= 4; y++) {
            const expected = [...source.values()].some(t => target.has(cellKey({ x: t.x + x, y: t.y + y })));
            expect(source.overlaps(target, { x, y })).toBe(expected);
        }
        expect(source.overlaps(source, { x: 0, y: 0 }, source)).toBe(false);
    });
});
