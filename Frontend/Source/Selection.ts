import { CellStore } from './CellStore';
import { ComponentIndex } from './ComponentIndex';
import { cellKey, type Point, type Selection } from './Model';
export interface SelectionState {
    Selection: Selection | null;
    Tiles: CellStore;
    Components: ComponentIndex;
}
const Sources = new WeakMap<Selection, {
    Tiles: CellStore;
    Source: CellStore;
}>();
export function selectionIds(s: SelectionState): number[] { return s.Selection?.ids ?? []; }
export function selectionSource(s: SelectionState): CellStore {
    const selection = s.Selection;
    if (!selection)
        return new CellStore();
    const cached = Sources.get(selection);
    if (cached?.Tiles === s.Tiles)
        return cached.Source;
    const source = CellStore.from((function* () { for (const id of selection.ids)
        yield* s.Components.members(id); })());
    Sources.set(selection, { Tiles: s.Tiles, Source: source });
    return source;
}
export function selectionCount(s: SelectionState): number { return selectionIds(s).reduce((n, id) => n + s.Components.count(id), 0); }
export function selectionSamples(s: SelectionState) { return selectionIds(s).map(id => s.Components.sample(id)).filter(tile => !!tile); }
export function selectionContains(s: SelectionState, point: Point) { return selectionIds(s).includes(s.Tiles.get(cellKey(point))?.componentId ?? 0); }
export function canMergeSelection(s: SelectionState): boolean { return s.Components.canMerge(selectionIds(s)); }
export function selectionLabel(s: SelectionState) { return s.Selection ? `${s.Selection.ids.length} components selected` : ''; }
