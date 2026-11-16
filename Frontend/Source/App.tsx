import { useCallback, useEffect, useRef, useState } from 'react';
import { useShallow } from 'zustand/react/shallow';
import { Alert, Button, Modal, TextInput, Tooltip } from '@mantine/core';
import { Activity, ArrowDownLeft, BookOpen, Clipboard, Copy, FilePlus2, FolderOpen, Combine, Keyboard, Layers3, Maximize2, Minus, MousePointer2, Plus, Save, Scissors, Search } from 'lucide-react';
import { BoardCanvas, type CameraCommand } from './BoardCanvas';
import { editorInput } from './EditorInput';
import { EditorShortcuts, commandForKey, editorKeysBlocked, shortcutFor } from './EditorShortcuts';
import { selectionLabel, canSplitSelection } from './Selection';
import { useEditor } from './EditorStore';
import { cellKey, newBoard, type Point } from './Model';
import { ActivityPanel, BlueprintLibrary, ClipboardLibrary, ComponentLibrary, Inspector } from './WorkspacePanels';
import { IconControl, WorkspaceToolbar } from './WorkspaceToolbar';
import { useSimulation } from './SimulationController';
import * as Native from './Native';
export function App() {
    const state = useEditor(useShallow(s => ({ Board: s.Board, EditTool: s.EditTool, MergeIds:s.MergeIds, MergeError:s.MergeError, Components:s.Components, Gesture:s.Gesture, Clipboard: s.Clipboard, LeftOpen: s.LeftOpen, RightOpen: s.RightOpen, PasteAnchor: !!s.PasteAnchor, PreviewValid: s.PreviewValid, Path: s.Path, Selection: s.Selection, Simulating: s.Simulating, Tiles: s.Tiles })));
    const [cursor, setCursor] = useState<Point>({ x: 0, y: 0 });
    const [zoom, setZoom] = useState(0.5);
    const [camera, setCamera] = useState<CameraCommand>({ action: 'none', sequence: 0 });
    const [library, setLibrary] = useState<'components' | 'clipboard' | 'blueprints'>('components');
    const [activityOpen, setActivityOpen] = useState(false);
    const [error, setError] = useState('');
    const [rate, setRate] = useState(1);
    const [fullSpeed, setFullSpeed] = useState(false);
    const [step, setStep] = useState(1);
    const [commandsOpen, setCommandsOpen] = useState(false);
    const [commandQuery, setCommandQuery] = useState('');
    const [helpOpen, setHelpOpen] = useState(false);
    const [blueprintFrom, setBlueprintFrom] = useState<boolean | null>(null);
    const [blueprintName, setBlueprintName] = useState('');
    const saveBlueprint = (fromClipboard: boolean) => { setBlueprintName(`Blueprint ${useEditor.getState().Blueprints.length + 1}`); setBlueprintFrom(fromClipboard); };
    const cursorRef = useRef(cursor);
    const updateCursor = useCallback((point: Point) => {
        cursorRef.current = point;
        setCursor(point);
    }, []);
    const report = useCallback((value: unknown) => {
        let message = String(value);
        try {
            const detail = JSON.parse(message);
            message = `${detail.errorReason}${detail.hasPosition ? ` at (${detail.errorX}, ${detail.errorY})` : ''}`;
        }
        catch { /* Native services may return an ordinary message. */ }
        setError(message);
        useEditor.getState().log(message);
    }, []);
    const simulation = useSimulation(report);
    const project = useCallback(async (action: () => Promise<unknown> | void) => {
        if (useEditor.getState().Simulating)
            await simulation.stop();
        try {
            useEditor.getState().cancel();
            await action();
        }
        catch (failure) {
            report(failure);
        }
    }, [simulation.stop, report]);
    const newProject = useCallback(() => void project(() => { useEditor.getState().load(newBoard()); useEditor.getState().log('Started a new circuit.'); }), [project]);
    const openProject = useCallback((path?: string) => void project(() => Native.chooseOpen(path)), [project]);
    const saveProject = useCallback((as = false) => void project(() => Native.chooseSave(as)), [project]);
    const changeCamera = (action: CameraCommand['action']) => setCamera(previous => ({ action, sequence: previous.sequence + 1 }));
    const changeRate = (value: number, commit = false) => {
        const next = Math.min(Math.max(1, Math.round(value)), Math.max(1, Math.floor(simulation.frame?.capacity ?? 1000000)));
        setRate(next);
        setFullSpeed(false);
        if (commit && simulation.frame?.running)
            void simulation.command('run', next);
    };
    const toggleSimulation = () => { if (state.Simulating)
        void simulation.stop();
    else
        void simulation.start(fullSpeed ? 0 : rate); };
    const openLibrary = (next: 'components' | 'clipboard' | 'blueprints') => { setLibrary(next); useEditor.setState({ LeftOpen: true }); };
    useEffect(() => { void Native.refreshRecent().catch(report); }, [report]);
    useEffect(() => { document.title = `${state.Path.split(/[\\/]/).at(-1) || 'Untitled circuit'} - OpenCircuitBoard`; }, [state.Path]);
    useEffect(() => {
        let previous = useEditor.getState().Clipboard;
        return useEditor.subscribe(next => {
            const changed = next.Clipboard !== previous;
            previous = next.Clipboard;
            if (changed && next.Clipboard.length && next.ClipboardOrigin === 'copy') {
                setLibrary('clipboard');
                useEditor.setState({ LeftOpen: true });
            }
        });
    }, []);
    useEffect(()=>{
        const keydown=(event:KeyboardEvent)=>{
            if(editorKeysBlocked(event.target))return;
            if(event.code==='Space'&&!event.ctrlKey&&!event.metaKey&&!event.altKey){event.preventDefault();editorInput.space(true);return;}
            const command=commandForKey(event);if(!command)return;
            event.preventDefault();if(event.repeat)return;
            switch(command) {
                case 'new':newProject();break;
                case 'open':openProject();break;
                case 'save':saveProject();break;
                case 'saveAs':saveProject(true);break;
                case 'commands':setCommandQuery('');setCommandsOpen(open=>!open);break;
                case 'fit':setCamera(previous=>({action:'fit',sequence:previous.sequence+1}));break;
                default:editorInput.execute(command,cursorRef.current);
            }
        };
        const keyup=(event:KeyboardEvent)=>{if(event.code==='Space')editorInput.space(false);};
        const blur=()=>{editorInput.space(false);if(useEditor.getState().Gesture!=='idle')editorInput.cancel();};
        window.addEventListener('keydown',keydown);window.addEventListener('keyup',keyup);window.addEventListener('blur',blur);
        return ()=>{window.removeEventListener('keydown',keydown);window.removeEventListener('keyup',keyup);window.removeEventListener('blur',blur);};
    },[newProject,openProject,saveProject]);
    const commands = [
        { label: 'New circuit', shortcut: shortcutFor('new'), icon: <FilePlus2 size={16}/>, run: newProject },
        { label: 'Open project', shortcut: shortcutFor('open'), icon: <FolderOpen size={16}/>, run: () => openProject() },
        { label: 'Save project', shortcut: shortcutFor('save'), icon: <Save size={16}/>, run: () => saveProject() },
        { label: 'Pointer tool', shortcut: shortcutFor('pointer'), icon: <MousePointer2 size={16}/>, run: () => useEditor.getState().selectTool('pointer') },
        { label: 'Draw with last ink', shortcut: shortcutFor('draw'), icon: <Layers3 size={16}/>, run: () => useEditor.getState().selectTool('draw') },
        { label: 'Merge components', shortcut: shortcutFor('merge'), icon: <Combine size={16}/>, run: () => useEditor.getState().selectTool('merge') },
        { label: 'Split components', shortcut: shortcutFor('split'), icon: <Scissors size={16}/>, run: () => useEditor.getState().selectTool('split') },
        { label: 'Show components', shortcut: '', icon: <Layers3 size={16}/>, run: () => openLibrary('components') },
        { label: 'Show blueprints', shortcut: '', icon: <BookOpen size={16}/>, run: () => openLibrary('blueprints') },
        { label: 'Show clipboard', shortcut: '', icon: <Clipboard size={16}/>, run: () => openLibrary('clipboard') },
        { label: 'Fit canvas', shortcut: shortcutFor('fit'), icon: <Maximize2 size={16}/>, run: () => changeCamera('fit') },
        { label: state.Simulating ? 'Back to design' : 'Run circuit', shortcut: '', icon: <Activity size={16}/>, run: toggleSimulation },
        { label: 'Keyboard shortcuts', shortcut: '', icon: <Keyboard size={16}/>, run: () => setHelpOpen(true) },
    ];
    const visibleCommands = commands.filter(command => command.label.toLowerCase().includes(commandQuery.toLowerCase()));
    const selectedLabel=selectionLabel(state);
    const toolLabel=state.EditTool==='pointer'?'Pointer: click to select, drag blank space to select components':state.EditTool==='draw'?'Draw: left-drag to paint | Right-click to return to pointer':state.EditTool==='merge'?'Merge: click adjacent components, then confirm':'Split: drag across a portion, then confirm';
    return <div className="editor-app">
    <WorkspaceToolbar frame={simulation.frame} starting={simulation.starting} rate={rate} fullSpeed={fullSpeed} step={step} onRate={changeRate} onFullSpeed={() => { setFullSpeed(!fullSpeed); if (simulation.frame?.running)
        void simulation.command('run', !fullSpeed ? 0 : rate); }} onStep={value => setStep(Math.max(1, Math.min(16, value)))} onCommand={(action, value) => void simulation.command(action, value)} onToggle={toggleSimulation} onNew={newProject} onOpen={openProject} onSave={saveProject} onSearch={() => { setCommandQuery(''); setCommandsOpen(true); }}/>
    <main className="editor-workspace">
      <nav className="workspace-rail" aria-label="Workspace panels"><div><Tooltip label="Components" position="right"><button type="button" aria-label="Show components" className={state.LeftOpen && library === 'components' ? 'active' : ''} onClick={() => openLibrary('components')}><Layers3 size={18}/></button></Tooltip><Tooltip label="Blueprints" position="right"><button type="button" aria-label="Show blueprints" className={state.LeftOpen && library === 'blueprints' ? 'active' : ''} onClick={() => openLibrary('blueprints')}><BookOpen size={18}/></button></Tooltip><Tooltip label="Clipboard" position="right"><button type="button" aria-label="Show clipboard" className={state.LeftOpen && library === 'clipboard' ? 'active' : ''} onClick={() => openLibrary('clipboard')}><Clipboard size={18}/>{state.Clipboard.length > 0 && <span className="rail-count">{state.Clipboard.length}</span>}</button></Tooltip><Tooltip label="Activity" position="right"><button type="button" aria-label="Toggle activity" className={activityOpen ? 'active' : ''} onClick={() => setActivityOpen(!activityOpen)}><Activity size={18}/></button></Tooltip></div><div><Tooltip label="Keyboard shortcuts" position="right"><button type="button" aria-label="Keyboard shortcuts" onClick={() => setHelpOpen(true)}><Keyboard size={18}/></button></Tooltip></div></nav>
      {state.LeftOpen && <aside className="library-panel" data-testid="left-dock">{library === 'components' ? <ComponentLibrary /> : library === 'blueprints' ? <BlueprintLibrary onCreate={saveBlueprint}/> : <ClipboardLibrary cursor={cursor} onSaveBlueprint={() => saveBlueprint(true)}/>}</aside>}
      <div className="canvas-workspace"><section className="canvas-surface"><BoardCanvas onCursor={updateCursor} onZoom={setZoom} cameraCommand={camera} onLatch={point => { const frame = simulation.frame; if (frame && state.Tiles.get(cellKey(point))?.toolId === 'latch')
        void simulation.command('toggle', (point.y - frame.originY) * frame.width + point.x - frame.originX); }}/>
        <div className="canvas-topline"><span className="canvas-label"><MousePointer2 size={12}/>{state.PasteAnchor ? 'Place your selection' : state.EditTool==='merge'||state.EditTool==='split'?toolLabel:state.Selection?selectedLabel:toolLabel}</span>{state.Simulating && <span className={`canvas-live ${simulation.frame?.running ? 'running' : ''}`}><span />{simulation.starting ? 'Compiling' : simulation.frame?.running ? 'Live simulation' : 'Paused'}</span>}</div>
        {!state.Tiles.size && !state.PasteAnchor && <div className="canvas-welcome"><div className="welcome-symbol"><Layers3 size={31} strokeWidth={1.3}/></div><span className="eyebrow">A LITTLE LOGIC. ENDLESS POSSIBILITIES.</span><h1>Start with a spark.</h1><p>Choose a component from the library<br />and bring your circuit to life.</p><span className="welcome-tip"><ArrowDownLeft size={14}/>Choose an ink to start drawing</span></div>}
        <div className="canvas-zoom"><IconControl label="Zoom out" onClick={() => changeCamera('out')}><Minus size={14}/></IconControl><button type="button" aria-label="Fit canvas" onClick={() => changeCamera('fit')}>{Math.round(zoom * 100)}%</button><IconControl label="Zoom in" onClick={() => changeCamera('in')}><Plus size={14}/></IconControl><span /><IconControl label="Fit board in view" onClick={() => changeCamera('fit')}><Maximize2 size={14}/></IconControl></div>
        {(state.EditTool==='merge'||state.EditTool==='split')&&<div className="canvas-actions" role="toolbar" aria-label="Pending operation">
          <span>{state.EditTool==='merge'?`${state.MergeIds.length} components picked`:'Local cells will become independent components'}</span>
          <Tooltip label={`${state.EditTool==='merge'?'Confirm merge':'Confirm split'} (${shortcutFor(state.EditTool)})`}><Button size="xs" aria-label={state.EditTool==='merge'?'Confirm merge':'Confirm split'} disabled={state.Gesture!=='idle'||(state.EditTool==='merge'?state.MergeIds.length<2:!canSplitSelection(state))} onClick={()=>state.EditTool==='merge'?useEditor.getState().confirmMerge():useEditor.getState().splitSelection()}>{state.EditTool==='merge'?'Confirm merge':'Confirm split'}</Button></Tooltip>
          <Tooltip label={`Cancel (${shortcutFor('cancel')})`}><Button size="xs" variant="default" onClick={()=>editorInput.cancel()}>Cancel</Button></Tooltip>
        </div>}
        {state.PasteAnchor && <div className={`canvas-context ${state.PreviewValid ? '' : 'invalid'}`}><Copy size={14}/><span>{state.PreviewValid ? 'Click to place' : 'Choose an empty area'}</span><kbd>Right-click / Q to cancel</kbd></div>}
      </section>{activityOpen && <ActivityPanel onClose={() => setActivityOpen(false)}/>}
      <footer className="workspace-status canvas-status"><span className="status-left"><span className={`status-indicator ${state.Simulating ? 'live' : ''}`}/>{state.Simulating ? simulation.frame?.running ? 'Simulating' : 'Paused' : 'Ready'}<span className="status-separator"/>{state.Tiles.size.toLocaleString()} cells</span><span className="status-right"><span>X {cursor.x} <span className="muted">Y</span> {cursor.y}</span>{simulation.frame ? <span>Tick {simulation.frame.tick.toLocaleString()}</span> : <span>{state.Board.grid.width} x {state.Board.grid.height}</span>}</span></footer></div>
      {state.RightOpen && <aside className="inspector-panel" data-testid="right-dock"><Inspector frame={simulation.frame} onSaveBlueprint={() => saveBlueprint(false)}/></aside>}
    </main>
    {error && <div className="error-toast"><Alert color="red" title="Something needs attention" withCloseButton onClose={() => setError('')}>{error}</Alert></div>}
    <Modal opened={blueprintFrom !== null} onClose={() => setBlueprintFrom(null)} title="Save blueprint" size="xs"><form onSubmit={event => { event.preventDefault(); if (blueprintFrom !== null && useEditor.getState().createBlueprint(blueprintName, blueprintFrom)) { setBlueprintFrom(null); openLibrary('blueprints'); } }}><TextInput data-autofocus aria-label="Blueprint name" value={blueprintName} onChange={event => setBlueprintName(event.currentTarget.value)}/><Button type="submit" fullWidth mt="md" disabled={!blueprintName.trim()}>Save blueprint</Button></form></Modal>
    <Modal opened={commandsOpen} onClose={() => setCommandsOpen(false)} withCloseButton={false} padding={0} size={480} classNames={{ content: 'command-modal' }} yOffset="18vh"><TextInput autoFocus aria-label="Search commands" variant="unstyled" placeholder="What would you like to do?" value={commandQuery} onChange={event => setCommandQuery(event.currentTarget.value)} leftSection={<Search size={17}/>} className="command-search" onKeyDown={event => { if (event.key === 'Enter' && visibleCommands[0]) {
        setCommandsOpen(false);
        visibleCommands[0].run();
    } }}/><div className="command-options">{visibleCommands.map(command => <button type="button" key={command.label} onClick={() => { setCommandsOpen(false); command.run(); }}>{command.icon}<span>{command.label}</span><kbd>{command.shortcut}</kbd></button>)}{!visibleCommands.length && <p>No commands found.</p>}</div><div className="command-hint"><span><kbd>Enter</kbd> to run the first result</span><span><kbd>Esc</kbd> to close</span></div></Modal>
    <Modal opened={helpOpen} onClose={() => setHelpOpen(false)} title="Make yourself at home" centered><div className="shortcut-list">{[...EditorShortcuts.map(item=>[item.label,item.key]),['Select components','Click / blank drag'],['Select local cells','Shift + drag'],['Cancel','Right-click'],['Pan / zoom','Space + drag / middle drag / wheel']].map(([label, shortcut]) => <div key={label}><span>{label}</span><kbd>{shortcut}</kbd></div>)}</div></Modal>
  </div>;
}
