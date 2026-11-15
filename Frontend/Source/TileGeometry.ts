import { cellKey, type Point } from './Model';

export const CellSize = 64;
export const Extrusion = 24;
export const ShadowMargin = 48;
export const LeftFace = 1;
export const BottomFace = 2;

export function exposedFaces(point: Point, occupied: { has(key: string): boolean }): number {
    return (occupied.has(cellKey({ x: point.x - 1, y: point.y })) ? 0 : LeftFace)
        | (occupied.has(cellKey({ x: point.x, y: point.y + 1 })) ? 0 : BottomFace);
}
