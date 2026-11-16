import { BufferImageSource, Texture } from 'pixi.js';
import { CellStore, type CellChunk } from './CellStore';
import { ColorRaster, colorKey, type ColorChunk, type ColorStateChunk, type ColorRequest } from './ColorPyramid';
import type { ColorJob, ColorResult } from './ColorWorker';
import type { RuntimeGrid } from './EditorStore';
import type { Point } from './Model';
const CacheBudget = 64 * 1024 * 1024;
interface CachedTexture { Texture: Texture; Pixels: Uint8Array; Version: number; Generation: number; Raster?: ColorRaster; Source?: CellChunk; Runtime?: unknown }
/** Shared LRU includes offscreen thumbnails and all live source rasters. */
class TextureBudget {
    private readonly Entries = new Map<object, { Bytes: number; Dispose: () => void }>();
    private Bytes = 0;
    touch(key: object, bytes: number, dispose: () => void) {
        const entry = this.Entries.get(key);
        if (entry) { this.Entries.delete(key); this.Entries.set(key, entry); return; }
        this.Entries.set(key, { Bytes: bytes, Dispose: dispose }); this.Bytes += bytes;
        while (this.Bytes > CacheBudget && this.Entries.size > 1) {
            const [old, value] = this.Entries.entries().next().value!;
            this.Entries.delete(old); this.Bytes -= value.Bytes; value.Dispose();
        }
    }
    remove(key: object) { const value = this.Entries.get(key); if (value) { this.Bytes -= value.Bytes; this.Entries.delete(key); } }
}
export const RenderBudget = new TextureBudget();
export class ColorCache {
    private readonly Worker = new Worker(new URL('./ColorWorker.ts', import.meta.url), { type: 'module' });
    private Store = new CellStore();
    private Runtime: RuntimeGrid | null = null;
    private Generation = 0;
    private Busy = false;
    private Failure?: Error;
    private Reset = true;
    private Pending = new Map<string, Point>();
    private Wanted = new Map<string, ColorRequest>();
    private Textures = new Map<string, CachedTexture>();
    private readonly SentChunks = new Map<string, CellChunk>();
    private readonly Active = new Map<string, ColorRequest>();
    private NeedsWorker = false;
    private InFlight: ColorRequest[] = [];
    constructor(private readonly Redraw: () => void) {
        this.Worker.onmessage = (event: MessageEvent<ColorResult>) => {
            this.Busy = false;
            const result = event.data;
            if (result.generation === this.Generation) {
                for (const raster of result.rasters) {
                    this.Wanted.delete(raster.key);
                    let entry = this.Textures.get(raster.key);
                    if (!entry) {
                        const source = new BufferImageSource({ resource: raster.pixels, width: 64, height: 64, format: 'rgba8unorm', alphaMode: 'premultiplied-alpha', scaleMode: 'nearest' });
                        entry = { Texture: new Texture({ source }), Pixels: raster.pixels, Version: raster.version, Generation: result.generation };
                        this.Textures.set(raster.key, entry);
                    }
                    else {
                        if (entry.Version !== raster.version) {
                            let start = entry.Pixels.length, end = 0;
                            for (let i = 0; i < raster.pixels.length; i++) if (entry.Pixels[i] !== raster.pixels[i]) { start = Math.min(start, i); end = i + 1; }
                            entry.Pixels.set(raster.pixels);
                            if (end) (entry.Texture.source as BufferImageSource).update(Math.floor(start / 4), Math.ceil(end / 4));
                        }
                        entry.Version = raster.version; entry.Generation = result.generation;
                    }
                    const cached = entry;
                    RenderBudget.touch(entry, 16384, () => { this.Textures.delete(raster.key); cached.Texture.destroy(true); });
                }
            }
            else if (!this.Reset) for (const request of this.InFlight) this.Wanted.set(colorKey(request.level, request.x, request.y), request);
            if (this.Pending.size) for (const request of this.InFlight) this.Wanted.set(colorKey(request.level, request.x, request.y), request);
            this.InFlight = [];
            this.flush(); this.Redraw();
        };
        this.Worker.onerror = event => { this.Busy = false; this.Failure = Error(`Color worker failed: ${event.message}`); this.Redraw(); };
    }
    sync(store: CellStore, runtime: RuntimeGrid | null) {
        if (store === this.Store && runtime === this.Runtime) return;
        const sourceChanged = store !== this.Store;
        const runtimeReset = !runtime || !this.Runtime || runtime.generation !== this.Runtime.generation;
        if (store.Identity !== this.Store.Identity) {
            for (const entry of this.Textures.values()) { RenderBudget.remove(entry); entry.Texture.destroy(true); }
            this.Textures.clear(); this.Pending.clear(); this.Wanted.clear(); this.SentChunks.clear(); this.Active.clear(); this.Store = new CellStore(); this.Reset = true;
        }
        for (const chunk of store.changedChunks(this.Store)) this.Pending.set(`${chunk.x},${chunk.y}`, chunk);
        if (runtime !== this.Runtime) {
            if (!runtime || !this.Runtime || runtime.generation !== this.Runtime.generation || !runtime.chunkVersions || !this.Runtime.chunkVersions) {
                for (const chunk of store.chunks()) this.Pending.set(`${chunk.X},${chunk.Y}`, { x: chunk.X, y: chunk.Y });
            }
            else {
                const cx = Math.floor(runtime.originX / 64), cy = Math.floor(runtime.originY / 64), wide = Math.floor((runtime.originX + runtime.width - 1) / 64) - cx + 1;
                for (let index = 0; index < runtime.chunkVersions.length; index++) if (runtime.chunkVersions[index] !== this.Runtime.chunkVersions[index]) {
                    const x = cx + index % wide, y = cy + Math.floor(index / wide);
                    this.Pending.set(`${x},${y}`, { x, y });
                }
            }
        }
        // Runtime jobs are sequential: show completed intermediate frames while newer deltas coalesce.
        // Editable-source changes and full runtime replacements invalidate outstanding results.
        if (sourceChanged || runtimeReset) this.Generation++;
        else if (this.Pending.size) for (const entry of this.Textures.values()) entry.Generation = -1;
        this.Store = store; this.Runtime = runtime;
    }
    begin() { this.Active.clear(); this.Wanted.clear(); this.NeedsWorker = false; }
    prepare(store: CellStore, runtime: RuntimeGrid | null) {
        this.sync(store, runtime);
        for (const [key, request] of this.Active) if (request.level > 0) this.Wanted.set(key, request);
        this.flush();
    }
    private localTexture(request: ColorRequest): Texture | undefined {
        const key = colorKey(0, request.x, request.y), chunk = this.Store.chunk(request.x, request.y);
        if (!chunk) return;
        const runtime = this.Runtime;
        let stamp: unknown = runtime;
        if (runtime?.chunkVersions) {
            const cx = Math.floor(runtime.originX / 64), cy = Math.floor(runtime.originY / 64);
            const wide = Math.floor((runtime.originX + runtime.width - 1) / 64) - cx + 1;
            const high = Math.floor((runtime.originY + runtime.height - 1) / 64) - cy + 1;
            stamp = `${runtime.generation}:${request.x >= cx && request.x < cx + wide && request.y >= cy && request.y < cy + high ? runtime.chunkVersions[(request.y - cy) * wide + request.x - cx] : 0}`;
        }
        let entry = this.Textures.get(key);
        if (!entry) {
            const raster = new ColorRaster(chunk.Tiles);
            const source = new BufferImageSource({ resource: raster.Pixels, width: 64, height: 64, format: 'rgba8unorm', alphaMode: 'premultiplied-alpha', scaleMode: 'nearest' });
            entry = { Texture: new Texture({ source }), Pixels: raster.Pixels, Version: 0, Generation: this.Generation, Raster: raster };
            this.Textures.set(key, entry);
        }
        if (entry.Source !== chunk || entry.Runtime !== stamp) {
            if (entry.Source && entry.Source !== chunk) entry.Raster = new ColorRaster(chunk.Tiles);
            const raster = entry.Raster!;
            const change = raster.update(tile => {
                const x = runtime ? tile.x - runtime.originX : -1, y = runtime ? tile.y - runtime.originY : -1;
                return runtime && x >= 0 && x < runtime.width && y >= 0 && y < runtime.height ? !!runtime.states[y * runtime.width + x] : tile.isOn;
            });
            if (entry.Pixels !== raster.Pixels) {
                entry.Pixels = raster.Pixels; (entry.Texture.source as BufferImageSource).resource = raster.Pixels;
                entry.Texture.source.update();
            }
            else if (change.end) (entry.Texture.source as BufferImageSource).update(change.start, change.end);
            entry.Source = chunk; entry.Runtime = stamp; entry.Generation = this.Generation;
        }
        const cached = entry;
        RenderBudget.touch(entry, entry.Raster!.Bytes, () => { this.Textures.delete(key); cached.Texture.destroy(true); });
        return entry.Texture;
    }
    texture(request: ColorRequest): Texture | undefined {
        this.Active.set(colorKey(request.level, request.x, request.y), request);
        if (request.level === 0) return this.localTexture(request);
        this.NeedsWorker = true;
        if (this.Failure) throw this.Failure;
        const key = colorKey(request.level, request.x, request.y), entry = this.Textures.get(key);
        if (!entry || entry.Generation !== this.Generation) this.Wanted.set(key, request);
        if (entry) {
            RenderBudget.touch(entry, 16384, () => { this.Textures.delete(key); entry.Texture.destroy(true); });
            return entry.Texture;
        }
    }
    get Ready() { return !this.NeedsWorker || !this.Busy && !this.Pending.size && !this.Wanted.size; }
    flush() {
        if (!this.NeedsWorker || this.Busy || (!this.Pending.size && !this.Wanted.size && !this.Reset)) return;
        const chunks: ColorChunk[] = [], stateChunks: ColorStateChunk[] = [];
        const requests = [...this.Wanted.values()];
        let sent = 0;
        const append = (key: string, point: Point) => {
            const { x, y } = point;
            const source = this.Store.chunk(x, y);
            const tiles = source?.Tiles.values() ?? [];
            const runtime = this.Runtime;
            const states = runtime ? Uint8Array.from(tiles, tile => {
                const tx = tile.x - runtime.originX, ty = tile.y - runtime.originY;
                return tx >= 0 && tx < runtime.width && ty >= 0 && ty < runtime.height ? runtime.states[ty * runtime.width + tx] : Number(tile.isOn);
            }) : Uint8Array.from(source?.Tiles.values() ?? [], tile => Number(tile.isOn));
            if (!source || this.SentChunks.get(key) !== source) {
                chunks.push({ x, y, tiles: [...(source?.Tiles.values() ?? [])], states });
                if (source) this.SentChunks.set(key, source); else this.SentChunks.delete(key);
            }
            else stateChunks.push({ x, y, states });
            this.Pending.delete(key); sent++;
        };
        for (const [key, point] of this.Pending) {
            if (sent >= 64) break;
            if (requests.some(request => Math.floor(point.x / 2 ** request.level) === request.x && Math.floor(point.y / 2 ** request.level) === request.y)) append(key, point);
        }
        for (const [key, point] of this.Pending) { if (sent >= 64) break; append(key, point); }
        this.InFlight = [...this.Wanted.values()];
        const job: ColorJob = { generation: this.Generation, reset: this.Reset, chunks, stateChunks, requests: this.InFlight };
        this.Wanted.clear(); this.Reset = false; this.Busy = true;
        this.Worker.postMessage(job, [...chunks.flatMap(c => c.states ? [c.states.buffer] : []), ...stateChunks.map(c => c.states.buffer)]);
    }
    clear() {
        this.Store = new CellStore(); this.Runtime = null; this.Generation++; this.Reset = true;
        this.Pending.clear(); this.Wanted.clear(); this.SentChunks.clear(); this.Active.clear();
        for (const entry of this.Textures.values()) { RenderBudget.remove(entry); entry.Texture.destroy(true); }
        this.Textures.clear(); this.flush();
    }
    destroy() {
        this.Worker.terminate();
        for (const entry of this.Textures.values()) { RenderBudget.remove(entry); entry.Texture.destroy(true); }
        this.Textures.clear(); this.Pending.clear(); this.Wanted.clear(); this.SentChunks.clear(); this.Active.clear();
    }
}
