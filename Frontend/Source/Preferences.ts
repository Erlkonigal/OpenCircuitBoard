import type { RenderMode } from './Model';
const PreferencesKey = 'OpenCircuitBoard.preferences';
export function loadRenderMode(): RenderMode {
    try { return JSON.parse(localStorage.getItem(PreferencesKey) ?? '{}').renderMode === '2d' ? '2d' : '2.5d'; }
    catch { return '2.5d'; }
}
export function saveRenderMode(renderMode: RenderMode) {
    try { localStorage.setItem(PreferencesKey, JSON.stringify({ renderMode })); }
    catch { /* A temporary storage failure must not prevent changing the view. */ }
}
