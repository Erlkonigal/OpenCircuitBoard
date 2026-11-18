import { Container, Graphics } from 'pixi.js';
import { ChunkSize, type CellChunk, type CellStore } from './CellStore';
import { inkColor, type Grid, type Tile } from './Model';
import { CellSize } from './TileGeometry';

const RightEdge = 1;
const BottomEdge = 2;
const BoundaryColor = 0x0c1219;
const BoundaryWidth = 1.5;
const BoundaryOpacity = .65;
const FadeStart = 8;
const FadeEnd = 12;

interface BoundaryChunk {
    Source: CellChunk;
    Right?: CellChunk;
    Bottom?: CellChunk;
    Segments: number[];
    Graphics?: Graphics;
}

function needsBoundary(tile: Tile, neighbor?: Tile) {
    return neighbor !== undefined && neighbor.componentId !== tile.componentId
        && (neighbor.toolId === tile.toolId || inkColor(neighbor.toolId) === inkColor(tile.toolId));
}

function appendRuns(edges: Uint8Array, horizontal: boolean, segments: number[]) {
    const mask = horizontal ? BottomEdge : RightEdge;
    const stride = horizontal ? 1 : ChunkSize;
    for (let line = 0; line < ChunkSize; line++) {
        const base = horizontal ? line * ChunkSize : line;
        let start = -1;
        for (let offset = 0; offset <= ChunkSize; offset++) {
            if (offset < ChunkSize && (edges[base + offset * stride] & mask)) {
                if (start < 0) start = offset;
            }
            else if (start >= 0) {
                if (horizontal) segments.push(start, line + 1, offset, line + 1);
                else segments.push(line + 1, start, line + 1, offset);
                start = -1;
            }
        }
    }
}

function chunkSegments(chunk: CellChunk, right?: CellChunk, bottom?: CellChunk) {
    let edges: Uint8Array | undefined;
    for (const [index, tile] of chunk.Tiles) {
        const column = index % ChunkSize;
        const rightTile = column === ChunkSize - 1 ? right?.Tiles.get(index - column) : chunk.Tiles.get(index + 1);
        const bottomTile = index >= ChunkSize * (ChunkSize - 1) ? bottom?.Tiles.get(column) : chunk.Tiles.get(index + ChunkSize);
        const mask = (needsBoundary(tile, rightTile) ? RightEdge : 0) | (needsBoundary(tile, bottomTile) ? BottomEdge : 0);
        if (mask) (edges ??= new Uint8Array(ChunkSize * ChunkSize))[index] = mask;
    }
    const segments: number[] = [];
    if (edges) {
        appendRuns(edges, true, segments);
        appendRuns(edges, false, segments);
    }
    return segments;
}

export class ComponentBoundaries {
    readonly Layer = new Container();
    private readonly Chunks = new Map<string, BoundaryChunk>();
    private Zoom = 0;

    get Count() { return this.Layer.children.length; }

    draw(source: CellStore, bounds: Grid, zoom: number) {
        const pixels = zoom * CellSize;
        if (pixels <= FadeStart) {
            this.clear();
            return;
        }
        this.Layer.alpha = BoundaryOpacity * Math.min(1, (pixels - FadeStart) / (FadeEnd - FadeStart));
        const wanted = new Set<string>();
        for (const chunk of source.chunks(bounds)) {
            const key = `${chunk.X},${chunk.Y}`;
            wanted.add(key);
            const right = source.chunk(chunk.X + 1, chunk.Y);
            const bottom = source.chunk(chunk.X, chunk.Y + 1);
            const previous = this.Chunks.get(key);
            let entry = previous;
            if (!entry || entry.Source !== chunk || entry.Right !== right || entry.Bottom !== bottom) {
                entry?.Graphics?.destroy();
                const segments = chunkSegments(chunk, right, bottom);
                entry = { Source: chunk, Right: right, Bottom: bottom, Segments: segments };
                if (segments.length) {
                    entry.Graphics = new Graphics();
                    entry.Graphics.position.set(chunk.X * ChunkSize * CellSize, chunk.Y * ChunkSize * CellSize);
                    this.Layer.addChild(entry.Graphics);
                }
                this.Chunks.set(key, entry);
            }
            if (entry.Graphics && (entry !== previous || this.Zoom !== zoom)) {
                const { Graphics: graphics, Segments: segments } = entry;
                graphics.clear();
                for (let i = 0; i < segments.length; i += 4)
                    graphics.moveTo(segments[i] * CellSize, segments[i + 1] * CellSize)
                        .lineTo(segments[i + 2] * CellSize, segments[i + 3] * CellSize);
                graphics.stroke({ color: BoundaryColor, width: BoundaryWidth / zoom, cap: 'butt' });
            }
        }
        for (const [key, entry] of this.Chunks) if (!wanted.has(key)) {
            entry.Graphics?.destroy();
            this.Chunks.delete(key);
        }
        this.Zoom = zoom;
    }

    clear() {
        for (const entry of this.Chunks.values()) entry.Graphics?.destroy();
        this.Chunks.clear();
        this.Zoom = 0;
    }
}
