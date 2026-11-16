import { ColorPyramid, type ColorChunk, type ColorStateChunk, type ColorRequest } from './ColorPyramid';
export interface ColorJob {
    generation: number;
    reset: boolean;
    chunks: ColorChunk[];
    stateChunks: ColorStateChunk[];
    requests: ColorRequest[];
}
export interface ColorResult {
    generation: number;
    rasters: { key: string; version: number; pixels: Uint8Array }[];
}
const pyramid = new ColorPyramid();
self.onmessage = (event: MessageEvent<ColorJob>) => {
    const { generation, reset, chunks, stateChunks, requests } = event.data;
    if (reset) pyramid.clear();
    pyramid.update(chunks);
    pyramid.updateStates(stateChunks);
    const rasters = requests.map(request => pyramid.raster(request));
    self.postMessage({ generation, rasters }, { transfer: rasters.map(r => r.pixels.buffer) });
};
