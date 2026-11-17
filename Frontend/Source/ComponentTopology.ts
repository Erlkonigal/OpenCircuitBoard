import type { Point, Tile } from './Model';
export const componentKey = (tile: {
    x: number;
    y: number;
}) => `${tile.x},${tile.y}`;
export function compatibleComponents(a: Tile, b: Tile): boolean {
    return a.toolId === b.toolId && (a.direction ?? 0) === (b.direction ?? 0) && a.fixedDrive === b.fixedDrive && !!a.defaultValue === !!b.defaultValue && (a.crossMask ?? 0) === (b.crossMask ?? 0) && (a.toolId !== 'latch' || a.isOn === b.isOn)
        && (a.toolId !== 'clock' || a.clockHoldTicks === b.clockHoldTicks);
}
/** Canonical key for an undirected connection between two neighboring cells. */
export function connectionKey(a: Point, b: Point): string {
    return a.x < b.x || (a.x === b.x && a.y < b.y) ? `${componentKey(a)}:${componentKey(b)}` : `${componentKey(b)}:${componentKey(a)}`;
}
export function connectedRegions(tiles: Iterable<Tile>, blocked?: ReadonlySet<string>): Tile[][] {
    const remaining = new Map(Array.from(tiles, tile => [componentKey(tile), tile]));
    const regions: { Tiles: Tile[]; First: Tile }[] = [];
    // Keep one iterator: repeatedly restarting it scans deleted map entries on fragmented regions.
    for (const seed of remaining.values()) {
        const region = [seed];
        let first = seed;
        remaining.delete(componentKey(seed));
        for (let i = 0; i < region.length; i++) {
            const tile = region[i];
            if (tile.y < first.y || (tile.y === first.y && tile.x < first.x)) first = tile;
            for (const [dx, dy] of [[-1, 0], [1, 0], [0, -1], [0, 1]]) {
                const key = `${tile.x + dx},${tile.y + dy}`, next = remaining.get(key);
                if (next && !blocked?.has(connectionKey(tile, next))) { remaining.delete(key); region.push(next); }
            }
        }
        regions.push({ Tiles: region, First: first });
    }
    return regions.sort((a, b) => b.Tiles.length - a.Tiles.length || a.First.y - b.First.y || a.First.x - b.First.x).map(region => region.Tiles);
}
export function validateComponents(tiles: readonly Tile[], error: string): void {
    const groups = new Map<number, Tile[]>();
    for (const tile of tiles) {
        if (!Number.isInteger(tile.componentId) || tile.componentId < 1 || tile.componentId > 2147483647)
            throw Error(error);
        const group = groups.get(tile.componentId);
        if (group) {
            if (!compatibleComponents(group[0], tile))
                throw Error(error);
            group.push(tile);
        }
        else
            groups.set(tile.componentId, [tile]);
    }
    for (const group of groups.values())
        if (connectedRegions(group).length !== 1)
            throw Error(error);
}
/** A snapshot owns its own IDs; clipped fragments must remain independent. */
export function snapshotTiles(tiles: readonly Tile[]): Tile[] {
    const groups = new Map<number, Tile[]>();
    for (const tile of tiles) {
        let group = groups.get(tile.componentId);
        if (!group) {
            group = [];
            groups.set(tile.componentId, group);
        }
        group.push(tile);
    }
    let id = 0;
    return [...groups.values()].flatMap(group => connectedRegions(group).flatMap(region => { const componentId = ++id; return region.map(tile => ({ ...tile, componentId })); }));
}
