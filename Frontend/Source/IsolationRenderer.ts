import { BlendModeFilter, Container, Graphics } from 'pixi.js';
import { IsolationStore, type IsolationChunk } from './IsolationStore';
import type { TileView } from './TileRenderer';
import { CellSize } from './TileGeometry';
export const IsolationColor = 0xffffff, IsolationWidth = 2;
/** Invert the backdrop once through an opaque edge mask, including at intersections. */
export function createIsolationFilter(opacity = 1) {
    const filter = new BlendModeFilter({
        gl: { functions: '', main: `
            float coverage = front.a * uBlend;
            finalColor = vec4(mix(back.rgb, vec3(1.0) - back.rgb, coverage),
                coverage + back.a * (1.0 - coverage));
        ` },
        gpu: { functions: '', main: `
            let coverage = front.a * blendUniforms.uBlend;
            out = vec4<f32>(mix(back.rgb, vec3<f32>(1.0) - back.rgb, coverage),
                coverage + back.a * (1.0 - coverage));
        ` }
    });
    filter.resources.blendUniforms.uniforms.uBlend = opacity;
    filter.resolution = 'inherit'; filter.antialias = 'inherit';
    return filter;
}
/** Visible chunks share one graphics object; consecutive edge segments become one line. */
export class IsolationRenderer {
    readonly Layer = new Container();
    private readonly Visible = new Map<string, { Source: IsolationChunk; Zoom: number; Graphic: Graphics }>();
    private readonly Filter: BlendModeFilter;
    Count = 0;
    constructor(alpha = 1) { this.Filter = createIsolationFilter(alpha); this.Layer.filters = [this.Filter]; }
    draw(source: IsolationStore | undefined, view: TileView) {
        this.Layer.visible = !!source?.size && view.zoom * CellSize >= 2;
        if (!this.Layer.visible) { this.clear(); return; }
        const bounds = { originX: Math.floor((view.x - view.width / view.zoom / 2) / CellSize) - 1,
            originY: Math.floor((view.y - view.height / view.zoom / 2) / CellSize) - 1,
            width: Math.ceil(view.width / view.zoom / CellSize) + 2, height: Math.ceil(view.height / view.zoom / CellSize) + 2 };
        const wanted = new Set<string>();
        for (const chunk of source!.chunks(bounds)) {
            const key = `${chunk.x},${chunk.y}`; wanted.add(key);
            let entry = this.Visible.get(key);
            if (!entry) { const graphic = new Graphics(); this.Layer.addChild(graphic); entry = { Source: chunk, Zoom: 0, Graphic: graphic }; this.Visible.set(key, entry); }
            if (entry.Source !== chunk || entry.Zoom !== view.zoom) {
                const graphic = entry.Graphic; graphic.clear(); graphic.position.set(chunk.x * 64 * CellSize, chunk.y * 64 * CellSize);
                const lines = new Map<string, number[]>();
                for (const edge of chunk.Edges.values()) {
                    const horizontal = edge.axis === 'horizontal', axis = horizontal ? edge.y : edge.x, key = `${horizontal ? 'h' : 'v'}:${axis}`;
                    let positions = lines.get(key); if (!positions) { positions = []; lines.set(key, positions); }
                    positions.push(horizontal ? edge.x : edge.y);
                }
                for (const [key, positions] of lines) {
                    const [direction, fixed] = key.split(':'), horizontal = direction === 'h', axis = Number(fixed);
                    positions.sort((a, b) => a - b);
                    for (let i = 0; i < positions.length;) {
                        const start = positions[i]; let end = start + 1; i++;
                        while (i < positions.length && positions[i] === end) { end++; i++; }
                        const x = (horizontal ? start - chunk.x * 64 : axis - chunk.x * 64) * CellSize;
                        const y = (horizontal ? axis - chunk.y * 64 : start - chunk.y * 64) * CellSize;
                        graphic.moveTo(x, y).lineTo(x + (horizontal ? end - start : 0) * CellSize, y + (horizontal ? 0 : end - start) * CellSize);
                    }
                }
                graphic.stroke({ color: IsolationColor, width: IsolationWidth / view.zoom, cap: 'butt' });
                entry.Source = chunk; entry.Zoom = view.zoom;
            }
        }
        for (const [key, entry] of this.Visible) if (!wanted.has(key)) { entry.Graphic.destroy(); this.Visible.delete(key); }
        this.Count = this.Visible.size;
    }
    clear() { for (const entry of this.Visible.values()) entry.Graphic.destroy(); this.Visible.clear(); this.Count = 0; }
    destroy() { this.clear(); this.Layer.destroy(); this.Filter.destroy(); }
}
