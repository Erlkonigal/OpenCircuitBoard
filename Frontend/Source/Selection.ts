import { CellStore } from './CellStore';
import { ComponentIndex } from './ComponentIndex';
import { cellKey, contains, type Point, type Selection } from './Model';
export interface SelectionState {
    Selection: Selection | null;
    Tiles: CellStore;
    Components: ComponentIndex;
}
const Sources = new WeakMap<Selection, {
    Tiles: CellStore;
    Source: CellStore;
}>();
export function selectionIds(s: SelectionState): number[] {
    const selection = s.Selection;
    return !selection ? [] : selection.kind === 'components' ? selection.ids : [...new Set(selection.cells.map(key => s.Tiles.get(key)?.componentId).filter((id): id is number => !!id))];
}
export function selectionSource(s: SelectionState): CellStore {
    const selection = s.Selection;
    if (!selection)
        return new CellStore();
    const cached = Sources.get(selection);
    if (cached?.Tiles === s.Tiles)
        return cached.Source;
    const source = CellStore.from(selection.kind === 'components'
        ? (function* () { for (const id of selection.ids)
            yield* s.Components.members(id); })()
        : s.Tiles.query(selection.bounds));
    Sources.set(selection, { Tiles: s.Tiles, Source: source });
    return source;
}
export function selectionCount(s: SelectionState): number {
    return !s.Selection ? 0 : s.Selection.kind === 'components' ? s.Selection.ids.reduce((n, id) => n + s.Components.count(id), 0) : s.Selection.cells.length;
}
export function selectionSamples(s: SelectionState) { return selectionIds(s).map(id => s.Components.sample(id)).filter(tile => !!tile); }
export function selectionContains(s: SelectionState, point: Point) {
    if (!s.Selection)
        return false;
    return s.Selection.kind === 'region' ? contains(s.Selection.bounds, point) : s.Selection.ids.includes(s.Tiles.get(cellKey(point))?.componentId ?? 0);
}
export function canSplitSelection(s: SelectionState): boolean {
    if (s.Selection?.kind !== 'region')
        return false;
    const counts = new Map<number, number>();
    for (const key of s.Selection.cells) {
        const id = s.Tiles.get(key)?.componentId;
        if (id)
            counts.set(id, (counts.get(id) ?? 0) + 1);
    }
    return [...counts].some(([id, count]) => count < s.Components.count(id));
}
export function selectionLabel(s: SelectionState) {
    return !s.Selection ? '' : s.Selection.kind === 'components' ? `${s.Selection.ids.length} components selected` : `${selectionCount(s)} local cells selected`;
}
