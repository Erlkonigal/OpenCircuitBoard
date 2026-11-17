import { cellKey, isDirectional, type Tile } from './Model';

export type PinKind = 'input' | 'output' | 'data' | 'control';
export interface ComponentPin { Side: number; Kind: PinKind }
const GatePins: readonly ComponentPin[] = [
    { Side: 0, Kind: 'output' }, { Side: 1, Kind: 'input' },
    { Side: 2, Kind: 'input' }, { Side: 3, Kind: 'input' },
];
const UnaryPins = [GatePins[0], GatePins[2]];
const SwitchPins: readonly ComponentPin[] = [
    { Side: 0, Kind: 'data' }, { Side: 2, Kind: 'data' }, { Side: 1, Kind: 'control' },
];
const Neighbors = [[1, 0], [0, 1], [-1, 0], [0, -1]] as const;

/** Only free contacts on a component boundary can accept another Trace. */
export function availablePins(tile: Tile, occupied: { has(key: string): boolean }): ComponentPin[] {
    if (!isDirectional(tile.toolId)) return [];
    const pins = tile.toolId === 'switch' ? SwitchPins : tile.toolId === 'clock' ? [GatePins[0]]
        : tile.toolId === 'led' ? [GatePins[2]] : ['buffer', 'not'].includes(tile.toolId) ? UnaryPins : GatePins;
    const result: ComponentPin[] = [];
    for (const pin of pins) {
        const side = (pin.Side + (tile.direction ?? 0)) % 4;
        const [dx, dy] = Neighbors[side];
        if (!occupied.has(cellKey({ x: tile.x + dx, y: tile.y + dy }))) result.push({ Side: side, Kind: pin.Kind });
    }
    return result;
}
