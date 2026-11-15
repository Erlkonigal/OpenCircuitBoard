import { describe, expect, it } from 'vitest';
import { BottomFace, exposedFaces, LeftFace } from '../../Source/TileGeometry';
import { cellKey, type Point } from '../../Source/Model';

const occupancy = (points: Point[]) => new Set(points.map(cellKey));
const rectangle = (width: number, height: number): Point[] => Array.from({ length: width * height }, (_, i) => ({ x: i % width, y: Math.floor(i / width) }));
function sideCounts(points: Point[]) {
    const occupied = occupancy(points);
    return points.reduce((sum, point) => {
        const faces = exposedFaces(point, occupied);
        return { left: sum.left + Number(!!(faces & LeftFace)), bottom: sum.bottom + Number(!!(faces & BottomFace)) };
    }, { left: 0, bottom: 0 });
}

describe('Equal-height tile boundaries', () => {
    it('only exposes the perimeter of horizontal and vertical runs', () => {
        expect(sideCounts(rectangle(6, 1))).toEqual({ left: 1, bottom: 6 });
        expect(sideCounts(rectangle(1, 6))).toEqual({ left: 6, bottom: 1 });
        expect(sideCounts(rectangle(4, 3))).toEqual({ left: 3, bottom: 4 });
    });
    it('preserves concave boundaries and holes without joining diagonal contacts', () => {
        expect(sideCounts([{ x: 0, y: 0 }, { x: 0, y: 1 }, { x: 1, y: 1 }])).toEqual({ left: 2, bottom: 2 });
        expect(sideCounts(rectangle(3, 3).filter(p => p.x !== 1 || p.y !== 1))).toEqual({ left: 4, bottom: 4 });
        expect(sideCounts([{ x: 0, y: 0 }, { x: 1, y: 1 }])).toEqual({ left: 2, bottom: 2 });
    });
    it('uses neighbors outside the visible subset and across negative bucket coordinates', () => {
        const visible = { x: -32, y: -1 };
        const occupied = occupancy([visible, { x: -33, y: -1 }, { x: -32, y: 0 }]);
        expect(exposedFaces(visible, occupied)).toBe(0);
        occupied.delete('-33,-1');
        expect(exposedFaces(visible, occupied)).toBe(LeftFace);
        occupied.delete('-32,0');
        expect(exposedFaces(visible, occupied)).toBe(LeftFace | BottomFace);
    });
    it('restores exposed faces after removal and ignores insertion order and material state', () => {
        const points = rectangle(3, 3), forward = occupancy(points), reverse = occupancy([...points].reverse());
        expect(points.map(p => exposedFaces(p, reverse))).toEqual(points.map(p => exposedFaces(p, forward)));
        forward.delete('1,1');
        expect(exposedFaces({ x: 2, y: 1 }, forward) & LeftFace).toBe(LeftFace);
        expect(exposedFaces({ x: 1, y: 0 }, forward) & BottomFace).toBe(BottomFace);
        forward.add('1,1');
        expect(points.map(p => exposedFaces(p, forward))).toEqual(points.map(p => exposedFaces(p, reverse)));
    });
});
