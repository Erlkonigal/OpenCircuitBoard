import { expect, it } from 'vitest';
import { availablePins } from '../../Source/ComponentPins';
import { CellStore } from '../../Source/CellStore';
import type { Tile } from '../../Source/Model';

function square(toolId: string, direction = 0) {
    return Array.from({ length: 9 }, (_, index): Tile => ({ x: index % 3, y: Math.floor(index / 3), toolId, componentId: 1, isOn: true, direction }));
}
it('shows only the free perimeter contacts of an entire device region', () => {
    const tiles = square('switch'), source = CellStore.from(tiles);
    expect(availablePins(tiles[4], source)).toEqual([]);
    expect(tiles.flatMap(tile => availablePins(tile, source))).toHaveLength(9);
    const connected = source.update([['-1,1', { x: -1, y: 1, toolId: 'trace', componentId: 2, isOn: true }]]);
    expect(availablePins(tiles[3], connected)).toEqual([]);
    expect(tiles.flatMap(tile => availablePins(tile, connected))).toHaveLength(8);
    expect(availablePins(tiles[3], source)).toEqual([{ Side: 2, Kind: 'data' }]);
});
it('rotates component contact sides and distinguishes source, sink and gate pins', () => {
    for (const [toolId, count] of [['buffer', 6], ['not', 6], ['clock', 3], ['led', 3], ['and', 12]] as const) {
        const tiles = square(toolId), source = CellStore.from(tiles);
        expect(tiles.flatMap(tile => availablePins(tile, source))).toHaveLength(count);
    }
    const tiles = square('buffer', 1), source = CellStore.from(tiles);
    expect(availablePins(tiles[1], source)).toEqual([{ Side: 3, Kind: 'input' }]);
    expect(availablePins(tiles[7], source)).toEqual([{ Side: 1, Kind: 'output' }]);
    expect(availablePins(tiles[3], source)).toEqual([]);
});
