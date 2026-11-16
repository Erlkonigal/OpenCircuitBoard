export const EditorShortcuts = [
    { id: 'pointer', label: 'Pointer tool', key: 'V' },
    { id: 'draw', label: 'Draw with last ink', key: 'B' },
    { id: 'delete', label: 'Delete selection', key: 'X' },
    { id: 'cancel', label: 'Cancel / return to pointer', key: 'Q' },
    { id: 'merge', label: 'Merge tool / confirm merge', key: 'G' },
    { id: 'split', label: 'Split along grid edges', key: 'Shift+G' },
    { id: 'fit', label: 'Fit canvas', key: 'F' },
    { id: 'undo', label: 'Undo', key: 'Ctrl+Z' },
    { id: 'redo', label: 'Redo', key: 'Ctrl+Shift+Z' },
    { id: 'copy', label: 'Copy selection', key: 'Ctrl+C' },
    { id: 'cut', label: 'Cut selection', key: 'Ctrl+X' },
    { id: 'paste', label: 'Paste', key: 'Ctrl+V' },
    { id: 'selectAll', label: 'Select all components', key: 'Ctrl+A' },
    { id: 'clearSelection', label: 'Clear selection', key: 'Ctrl+D' },
    { id: 'new', label: 'New circuit', key: 'Ctrl+N' },
    { id: 'open', label: 'Open project', key: 'Ctrl+O' },
    { id: 'save', label: 'Save project', key: 'Ctrl+S' },
    { id: 'saveAs', label: 'Save project as', key: 'Ctrl+Shift+S' },
    { id: 'commands', label: 'Command menu', key: 'Ctrl+K' },
] as const;
export type EditorCommand = typeof EditorShortcuts[number]['id'];
export const shortcutFor = (id: EditorCommand) => EditorShortcuts.find(shortcut => shortcut.id === id)!.key;
export function commandForKey(event: Pick<KeyboardEvent, 'key' | 'ctrlKey' | 'metaKey' | 'shiftKey' | 'altKey'>): EditorCommand | undefined {
    if (event.altKey)
        return;
    const key = [...(event.ctrlKey || event.metaKey ? ['Ctrl'] : []), ...(event.shiftKey ? ['Shift'] : []), event.key.toUpperCase()].join('+');
    return EditorShortcuts.find(shortcut => shortcut.key === key)?.id;
}
export function editorKeysBlocked(target: EventTarget | null): boolean {
    return !!document.querySelector('[role="dialog"]') || target instanceof Element && !!target.closest('input,textarea,select,[contenteditable=true],[role=textbox],[role=spinbutton]');
}
