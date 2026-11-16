import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { ColorCache } from '../../Source/ColorCache';
import { ColorPyramid } from '../../Source/ColorPyramid';
import { CellStore } from '../../Source/CellStore';
import { useEditor } from '../../Source/EditorStore';
import { applyFrame } from '../../Source/Native';
import type { ColorJob } from '../../Source/ColorWorker';
import type { Tile } from '../../Source/Model';
const Workers: TestWorker[] = [];
class TestWorker {
    onmessage?: (event: MessageEvent) => void;
    onerror?: (event: ErrorEvent) => void;
    Jobs: ColorJob[] = [];
    Pyramid = new ColorPyramid();
    Terminated = false;
    constructor() { Workers.push(this); }
    postMessage(job: ColorJob) { this.Jobs.push(job); }
    terminate() { this.Terminated = true; }
    finish() {
        const job = this.Jobs.shift()!;
        if (job.reset) this.Pyramid.clear();
        this.Pyramid.update(job.chunks);
        this.Pyramid.updateStates(job.stateChunks);
        this.onmessage?.({ data: { generation: job.generation, rasters: job.requests.map(request => this.Pyramid.raster(request)) } } as MessageEvent);
    }
}
const tile = (x: number, isOn = true): Tile => ({ x, y: 0, toolId: 'latch', componentId: 1, isOn });
beforeEach(() => { Workers.length = 0; vi.stubGlobal('Worker', TestWorker); });
afterEach(() => vi.unstubAllGlobals());
describe('Asynchronous color cache', () => {
    it('discards stale results while retaining edits received during worker execution', () => {
        const cache = new ColorCache(() => {}), worker = Workers[0], source = CellStore.from([tile(0)]), request = { x: 0, y: 0, level: 1 };
        cache.sync(source, null); cache.texture(request); cache.flush();
        cache.sync(source.update([['0,0', tile(0, false)]]), null);
        worker.finish(); expect(cache.texture(request)).toBeUndefined();
        worker.finish(); expect(cache.texture(request)).toBeDefined(); expect(cache.Ready).toBe(true);
        cache.destroy(); expect(worker.Terminated).toBe(true);
    });
    it('coalesces runtime chunk versions even when several frames arrive between draws', () => {
        const source = CellStore.from([tile(0), tile(64)]), cache = new ColorCache(() => {}), worker = Workers[0];
        const base = { session: 1, sequence: 1, tick: 0, width: 65, height: 1, originX: 0, originY: 0, full: true, running: false, tps: 0, capacity: 10, first: 0, last: 0, data: new Uint8Array(65).fill(1) };
        applyFrame(base); cache.sync(source, useEditor.getState().RuntimeGrid); cache.texture({ x: 0, y: 0, level: 1 }); cache.flush(); worker.finish();
        applyFrame({ ...base, full: false, data: new Int32Array([0, 0]) });
        applyFrame({ ...base, full: false, data: new Int32Array([64, 0]) });
        cache.sync(source, useEditor.getState().RuntimeGrid); cache.texture({ x: 0, y: 0, level: 1 }); cache.flush();
        expect(worker.Jobs[0].chunks).toHaveLength(0);
        expect(worker.Jobs[0].stateChunks.map(chunk => chunk.x).sort()).toEqual([0, 1]);
        expect(worker.Jobs[0].stateChunks.every(chunk => chunk.states[0] === 0)).toBe(true);
        worker.finish(); cache.destroy();
    });
    it('bounds initial jobs, prioritizes visible chunks and releases a discarded source', () => {
        const cache = new ColorCache(() => {}), worker = Workers[0];
        cache.sync(CellStore.from(Array.from({ length: 100 }, (_, i) => tile(i * 128))), null);
        cache.texture({ x: 99, y: 0, level: 1 }); cache.flush();
        expect(worker.Jobs[0].chunks).toHaveLength(64); expect(worker.Jobs[0].chunks[0].x).toBe(198);
        cache.clear(); worker.finish(); expect(worker.Jobs[0].reset).toBe(true);
        expect(worker.Jobs[0].chunks).toHaveLength(0); expect(worker.Jobs[0].requests).toHaveLength(0);
        worker.finish(); expect(cache.Ready).toBe(true); cache.destroy();
    });
    it('keeps progressing when runtime deltas arrive during every worker job', () => {
        const source = CellStore.from([tile(0)]), cache = new ColorCache(() => {}), worker = Workers[0], request = { x: 0, y: 0, level: 1 };
        const frame = { session: 1, sequence: 1, tick: 0, width: 1, height: 1, originX: 0, originY: 0, full: true, running: false, tps: 0, capacity: 10, first: 0, last: 0, data: new Uint8Array([1]) };
        applyFrame(frame); cache.sync(source, useEditor.getState().RuntimeGrid); cache.texture(request); cache.flush(); worker.finish();
        for (let i = 0; i < 5; i++) {
            applyFrame({ ...frame, full: false, data: new Int32Array([0, i % 2]) });
            cache.sync(source, useEditor.getState().RuntimeGrid); cache.texture(request); cache.flush();
            applyFrame({ ...frame, full: false, data: new Int32Array([0, 1 - i % 2]) });
            cache.sync(source, useEditor.getState().RuntimeGrid);
            worker.finish(); expect(cache.texture(request)).toBeDefined();
        }
        while (worker.Jobs.length) worker.finish();
        expect(cache.Ready).toBe(true); cache.destroy();
    });

    it('reuses geometry across simulation resets and restores editable colors after runtime', () => {
        const source = CellStore.from([tile(0)]), cache = new ColorCache(() => {}), worker = Workers[0], request = { x: 0, y: 0, level: 1 };
        cache.sync(source, null); cache.texture(request); cache.flush(); worker.finish();
        const design = new Uint8Array(cache.texture(request)!.source.resource as Uint8Array);
        const frame = { session: 1, sequence: 1, tick: 0, width: 1, height: 1, originX: 0, originY: 0, full: true, running: false, tps: 0, capacity: 10, first: 0, last: 0, data: new Uint8Array([0]) };
        for (let i = 0; i < 2; i++) {
            applyFrame(frame); cache.sync(source, useEditor.getState().RuntimeGrid); cache.texture(request); cache.flush();
            expect(worker.Jobs[0].chunks).toHaveLength(0); expect(worker.Jobs[0].stateChunks).toHaveLength(1);
            worker.finish(); expect(cache.texture(request)!.source.resource).not.toEqual(design);
        }
        cache.sync(source, null); cache.texture(request); cache.flush();
        expect(worker.Jobs[0].chunks).toHaveLength(0); expect(worker.Jobs[0].stateChunks[0].states[0]).toBe(1);
        worker.finish(); expect(cache.texture(request)!.source.resource).toEqual(design);
        cache.destroy();
    });
    it('updates visible color chunks synchronously and clears removed pixels without worker jobs', () => {
        let source = CellStore.from([tile(0), tile(1)]);
        const cache = new ColorCache(() => {}), worker = Workers[0], request = { x: 0, y: 0, level: 0 };
        cache.sync(source, null); cache.begin();
        const texture = cache.texture(request)!;
        cache.flush(); expect(worker.Jobs).toHaveLength(0); expect(cache.Ready).toBe(true);
        const before = new Uint8Array(texture.source.resource as Uint8Array);
        const frame = { session: 1, sequence: 1, tick: 0, width: 2, height: 1, originX: 0, originY: 0, full: true, running: false, tps: 0, capacity: 10, first: 0, last: 0, data: new Uint8Array([0, 1]) };
        applyFrame(frame); cache.sync(source, useEditor.getState().RuntimeGrid); cache.begin();
        expect(cache.texture(request)).toBe(texture);
        expect(texture.source.resource).not.toEqual(before);
        expect([...(texture.source.resource as Uint8Array).slice(4, 8)]).toEqual([...before.slice(4, 8)]);
        cache.flush(); expect(worker.Jobs).toHaveLength(0); expect(cache.Ready).toBe(true);
        source = source.update([['0,0', undefined]]);
        cache.sync(source, null); cache.begin(); expect(cache.texture(request)).toBe(texture);
        expect([...(texture.source.resource as Uint8Array).slice(0, 4)]).toEqual([0, 0, 0, 0]);
        cache.destroy();
    });
    it('can leave an aggregate worker in flight and rebuild the latest overview after color rendering', () => {
        const source = CellStore.from([tile(0)]), cache = new ColorCache(() => {}), worker = Workers[0];
        const aggregate = { x: 0, y: 0, level: 1 }, color = { x: 0, y: 0, level: 0 };
        cache.sync(source, null); cache.begin(); cache.texture(aggregate); cache.flush();
        const frame = { session: 1, sequence: 1, tick: 0, width: 1, height: 1, originX: 0, originY: 0, full: true, running: false, tps: 0, capacity: 10, first: 0, last: 0, data: new Uint8Array([0]) };
        applyFrame(frame); cache.sync(source, useEditor.getState().RuntimeGrid); cache.begin();
        const pixels = new Uint8Array(cache.texture(color)!.source.resource as Uint8Array);
        worker.finish(); expect(worker.Jobs).toHaveLength(0); expect(cache.Ready).toBe(true);
        cache.begin(); cache.texture(aggregate); cache.flush();
        expect(worker.Jobs[0].chunks).toHaveLength(0); expect(worker.Jobs[0].stateChunks[0].states[0]).toBe(0);
        worker.finish();
        const result = cache.texture(aggregate)!.source.resource as Uint8Array;
        expect([...result.slice(0, 3)]).toEqual([...pixels.slice(0, 3)].map(value => Math.round(value / 4)));
        cache.destroy();
    });
});
