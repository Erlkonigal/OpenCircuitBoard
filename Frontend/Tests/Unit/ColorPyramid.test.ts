import { describe, expect, it } from 'vitest';
import { ColorPyramid, ColorRaster, colorLevel, detailLevel, tileColor } from '../../Source/ColorPyramid';
import type { Tile } from '../../Source/Model';
describe('Area weighted color LOD', () => {
    it('matches design and runtime colors across local and worker rasters while preserving holes', () => {
        const tiles: Tile[] = [
            { x: 0, y: 0, toolId: 'traceRed', componentId: 1, isOn: false },
            { x: 3, y: 2, toolId: 'button', componentId: 2, isOn: false },
            { x: 63, y: 63, toolId: 'traceWhite', componentId: 3, isOn: true },
        ];
        const raster = new ColorRaster(new Map(tiles.map(tile => [tile.y * 64 + tile.x, tile])));
        const pyramid = new ColorPyramid();
        pyramid.update([{ x: 0, y: 0, tiles }]);
        const design = pyramid.raster({ level: 0, x: 0, y: 0 }).pixels;
        expect(raster.Pixels).toEqual(design);
        expect([...design.slice(0, 4)]).toEqual([...tileColor(tiles[0], true), 255]);
        const buttonOffset = (2 * 64 + 3) * 4;
        expect([...design.slice(buttonOffset, buttonOffset + 4)]).toEqual([...tileColor(tiles[1], false), 255]);
        expect(tileColor(tiles[0])).toEqual(tileColor(tiles[0], true));
        raster.update(tile => tile.toolId === 'button');
        pyramid.updateStates([{ x: 0, y: 0, states: new Uint8Array([0, 1, 0]) }]);
        expect(raster.Pixels).toEqual(pyramid.raster({ level: 0, x: 0, y: 0 }).pixels);
        expect([...raster.Pixels.slice(0, 4)]).toEqual([...tileColor(tiles[0], false), 255]);
        expect([...raster.Pixels.slice(4, 8)]).toEqual([0, 0, 0, 0]);
    });
    it('averages premultiplied color and preserves empty coverage', () => {
        const pyramid = new ColorPyramid();
        const tiles: Tile[] = [{ x: 0, y: 0, toolId: 'traceRed', componentId: 1, isOn: true }, { x: 1, y: 0, toolId: 'traceBlue', componentId: 2, isOn: true }];
        pyramid.update([{ x: 0, y: 0, tiles }]);
        const pixel = pyramid.raster({ level: 1, x: 0, y: 0 }).pixels.slice(0, 4), a = tileColor(tiles[0]), b = tileColor(tiles[1]);
        expect([...pixel]).toEqual([...a.map((v, i) => Math.round((v + b[i]) / 4)), 128]);
        expect([...pyramid.raster({ level: 1, x: 0, y: 0 }).pixels.slice(4, 8)]).toEqual([0, 0, 0, 0]);
    });
    it('updates ancestors and handles negative quadrants, removal and runtime states', () => {
        const pyramid = new ColorPyramid(), tile: Tile = { x: -1, y: -1, toolId: 'button', componentId: 3, isOn: true };
        pyramid.update([{ x: -1, y: -1, tiles: [tile] }]);
        const request = { level: 1, x: -1, y: -1 };
        expect(pyramid.raster(request).pixels.at(-1)).toBe(64);
        const before = pyramid.raster(request);
        pyramid.update([{ x: -1, y: -1, tiles: [tile], states: new Uint8Array([0]) }]);
        expect(pyramid.raster(request).pixels.at(-4)).toBeLessThan(before.pixels.at(-4)!);
        pyramid.update([{ x: -1, y: -1, tiles: [] }]); expect(pyramid.raster(request).pixels.every(value => value === 0)).toBe(true);
    });
    it('selects detail using CSS pixels and keeps aggregate texels near screen pixel size', () => {
        expect([12, 11.9, 2, 1.99].map(detailLevel)).toEqual(['detail', 'color', 'color', 'aggregate']);
        for (const scale of [1, .8, .25, .001]) expect(scale * 2 ** colorLevel(scale)).toBeGreaterThanOrEqual(1);
    });
    it('reduces dense and sparse quadrants to the same area sums without seams', () => {
        const pyramid = new ColorPyramid();
        const chunks = [];
        for (let y = -2; y < 2; y++) for (let x = -2; x < 2; x++) {
            const tiles: Tile[] = [];
            for (let py = 0; py < 64; py++) for (let px = 0; px < 64; px++) if ((px + py) % 4 !== 0)
                tiles.push({ x: x * 64 + px, y: y * 64 + py, toolId: 'traceRed', componentId: 4, isOn: true });
            chunks.push({ x, y, tiles });
        }
        pyramid.update(chunks);
        for (const x of [-1, 0]) for (const y of [-1, 0]) {
            const raster = pyramid.raster({ level: 1, x, y }).pixels;
            for (const px of [0, 31, 32, 63]) for (const py of [0, 31, 32, 63]) {
                const count = 3;
                expect([...raster.slice((py * 64 + px) * 4, (py * 64 + px) * 4 + 4)])
                    .toEqual([255, 77, 77, 255].map(value => Math.round(value * count / 4)));
            }
        }
    });

    it('applies state-only updates to dense and sparse chunks without stale lazy ancestors', () => {
        const dense = Array.from({ length: 4096 }, (_, index): Tile => ({ x: index % 64, y: Math.floor(index / 64), toolId: 'traceRed', componentId: 1, isOn: true }));
        const sparse: Tile[] = [{ x: -1, y: -1, toolId: 'led', componentId: 2, isOn: false }];
        const pyramid = new ColorPyramid();
        pyramid.update([{ x: 0, y: 0, tiles: dense }, { x: -1, y: -1, tiles: sparse }]);
        const requests = [{ x: 0, y: 0, level: 0 }, { x: 0, y: 0, level: 1 }, { x: 0, y: 0, level: 6 }, { x: -1, y: -1, level: 2 }, { x: -1, y: -1, level: 25 }];
        for (const request of requests) pyramid.raster(request);
        for (let tick = 0; tick < 4; tick++) {
            const states = Uint8Array.from(dense, (_, index) => Number((index + tick) % 3 === 0));
            const sparseStates = new Uint8Array([tick % 2]);
            pyramid.updateStates([{ x: 0, y: 0, states }, { x: -1, y: -1, states: sparseStates }]);
            const reference = new ColorPyramid();
            reference.update([{ x: 0, y: 0, tiles: dense, states }, { x: -1, y: -1, tiles: sparse, states: sparseStates }]);
            for (const request of requests) {
                expect(pyramid.raster(request).pixels).toEqual(reference.raster(request).pixels);
                const version = pyramid.raster(request).version;
                pyramid.updateStates([{ x: 0, y: 0, states }, { x: -1, y: -1, states: sparseStates }]);
                expect(pyramid.raster(request).version).toBe(version);
            }
        }
        pyramid.update([{ x: 0, y: 0, tiles: [] }, { x: -1, y: -1, tiles: [] }]);
        for (const request of requests) expect(pyramid.raster(request).pixels.every(value => value === 0)).toBe(true);
    });
});
