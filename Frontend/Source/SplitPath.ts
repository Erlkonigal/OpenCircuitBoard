import { connectionKey } from './ComponentTopology';
import type { Point } from './Model';
export interface CutEdge {
    Start: Point;
    End: Point;
    Cells: readonly [Point, Point];
}
/** Four-connected vertex interpolation, canonicalized so reverse strokes use the same edges. */
export function gridLine(start: Point, end: Point): Point[] {
    const reverse = start.x > end.x || (start.x === end.x && start.y > end.y);
    const a = reverse ? end : start, b = reverse ? start : end;
    const dx = Math.abs(b.x - a.x), dy = Math.abs(b.y - a.y), sx = Math.sign(b.x - a.x), sy = Math.sign(b.y - a.y);
    const result: Point[] = [{ ...a }];
    let x = a.x, y = a.y, ix = 0, iy = 0;
    while (ix < dx || iy < dy) {
        if (ix < dx && (iy === dy || (ix + .5) / dx <= (iy + .5) / dy)) {
            x += sx;
            ix++;
        }
        else {
            y += sy;
            iy++;
        }
        result.push({ x, y });
    }
    return reverse ? result.reverse() : result;
}
/** Mutable geometry belongs only to the current gesture; it is never document data. */
export class SplitPath {
    readonly Edges = new Map<string, CutEdge>();
    Last: Point;
    constructor(start: Point) { this.Last = { ...start }; }
    append(point: Point) {
        const vertices = gridLine(this.Last, point);
        for (let i = 1; i < vertices.length; i++) {
            const a = vertices[i - 1], b = vertices[i];
            const x = Math.min(a.x, b.x), y = Math.min(a.y, b.y);
            const cells: [Point, Point] = a.y === b.y ? [{ x, y: y - 1 }, { x, y }] : [{ x: x - 1, y }, { x, y }];
            this.Edges.set(connectionKey(...cells), { Start: a, End: b, Cells: cells });
        }
        this.Last = { ...point };
    }
}
