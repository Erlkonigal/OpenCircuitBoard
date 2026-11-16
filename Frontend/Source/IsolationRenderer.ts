import { Container, Graphics } from 'pixi.js';
import { IsolationStore, type IsolationChunk } from './IsolationStore';
import type { TileView } from './TileRenderer';
import { CellSize } from './TileGeometry';
export const IsolationColor = '#e1cf9a', IsolationWidth = 2;
/** Visible chunks share one graphics object; consecutive edge segments become one line. */
export class IsolationRenderer {
    readonly Layer = new Container();
    private readonly Visible = new Map<string, { Source: IsolationChunk; Zoom: number; Graphic: Graphics }>();
    Count = 0;
    constructor(alpha = 1) { this.Layer.alpha = alpha; }
    draw(source: IsolationStore | undefined, view: TileView, tint = 0xffffff) {
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
            entry.Graphic.tint = tint;
        }
        for (const [key, entry] of this.Visible) if (!wanted.has(key)) { entry.Graphic.destroy(); this.Visible.delete(key); }
        this.Count = this.Visible.size;
    }
    clear() { for (const entry of this.Visible.values()) entry.Graphic.destroy(); this.Visible.clear(); this.Count = 0; }
    destroy() { this.clear(); this.Layer.destroy(); }
}
