import type { ReactNode } from 'react';
import { useShallow } from 'zustand/react/shallow';
import { ActionIcon, Button, Menu, NumberInput, SegmentedControl, Slider, Tooltip } from '@mantine/core';
import { ChevronDown, Command, FilePlus2, FolderOpen, History, Layers3, PanelLeftClose, PanelLeftOpen, PanelRightClose, PanelRightOpen, Pause, Play, Redo2, RotateCcw, Save, Settings2, SkipBack, SkipForward, Undo2, Zap } from 'lucide-react';
import { useEditor } from './EditorStore';
import type { Frame } from './Native';
export function IconControl({ label, children, onClick, disabled = false, active = false }: {
    label: string;
    children: ReactNode;
    onClick: () => void;
    disabled?: boolean;
    active?: boolean;
}) {
    return <Tooltip label={label} openDelay={500}><ActionIcon variant={active ? 'light' : 'subtle'} color={active ? 'teal' : 'gray'} aria-label={label} size={29} disabled={disabled} onClick={onClick}>{children}</ActionIcon></Tooltip>;
}
interface Props {
    frame: Frame | null;
    starting: boolean;
    rate: number;
    fullSpeed: boolean;
    step: number;
    onRate: (rate: number, commit?: boolean) => void;
    onFullSpeed: () => void;
    onStep: (step: number) => void;
    onCommand: (action: string, value?: number) => void;
    onToggle: () => void;
    onNew: () => void;
    onOpen: (path?: string) => void;
    onSave: (as?: boolean) => void;
    onSearch: () => void;
}
export function WorkspaceToolbar(props: Props) {
    const state = useEditor(useShallow(s => ({ Path: s.Path, Recent: s.Recent, LeftOpen: s.LeftOpen, RightOpen: s.RightOpen, Undo: s.Undo, Redo: s.Redo, undo: s.undo, redo: s.redo, Simulating: s.Simulating, ComponentCount: s.Components.size, RenderMode: s.RenderMode, setRenderMode: s.setRenderMode })));
    const name = state.Path.split(/[\\/]/).at(-1) || 'Untitled circuit';
    const capacity = Math.max(2, Math.floor(props.frame?.capacity ?? 1000000));
    return <>
    <header className="workspace-header">
      <div className="workspace-brand"><div className="brand-symbol"><Layers3 size={21} strokeWidth={1.7}/></div><span>OpenCircuitBoard</span><span className="brand-beta">DESKTOP</span></div>
      <span className="header-divider"/>
      <Menu width={280} position="bottom-start"><Menu.Target><button className="project-switcher" type="button"><span className="project-marker"/><span>{name}</span><ChevronDown size={12}/></button></Menu.Target><Menu.Dropdown><Menu.Label>Project</Menu.Label><Menu.Item leftSection={<FilePlus2 size={15}/>} rightSection={<kbd>Ctrl N</kbd>} onClick={props.onNew}>New circuit</Menu.Item><Menu.Item leftSection={<FolderOpen size={15}/>} rightSection={<kbd>Ctrl O</kbd>} onClick={() => props.onOpen()}>Open project</Menu.Item><Menu.Item leftSection={<Save size={15}/>} rightSection={<kbd>Ctrl S</kbd>} onClick={() => props.onSave()}>Save project</Menu.Item><Menu.Item onClick={() => props.onSave(true)}>Save project as...</Menu.Item><Menu.Divider /><Menu.Label>Recent projects</Menu.Label>{state.Recent.length ? state.Recent.map(path => <Menu.Item key={path} leftSection={<History size={13}/>} onClick={() => props.onOpen(path)}>{path.split(/[\\/]/).at(-1)}</Menu.Item>) : <Menu.Item disabled>No recent projects</Menu.Item>}</Menu.Dropdown></Menu>
      <div className="header-space"/>
      <button className="command-trigger" type="button" onClick={props.onSearch}><Command size={13}/><span>Commands</span><kbd>Ctrl K</kbd></button>
      <IconControl label="Open project" onClick={() => props.onOpen()}><FolderOpen size={17}/></IconControl>
      <Button size="xs" variant="default" leftSection={<Save size={14}/>} onClick={() => props.onSave()} aria-label="Save project">Save</Button>
    </header>
    <div className="workspace-toolbar">
      <div className="toolbar-cluster"><IconControl label="Toggle component library" onClick={() => useEditor.setState({ LeftOpen: !state.LeftOpen })}>{state.LeftOpen ? <PanelLeftClose size={16}/> : <PanelLeftOpen size={16}/>}</IconControl><span className="toolbar-divider"/><IconControl label="Undo (Ctrl+Z)" disabled={!state.Undo.length || state.Simulating} onClick={state.undo}><Undo2 size={15}/></IconControl><IconControl label="Redo (Ctrl+U)" disabled={!state.Redo.length || state.Simulating} onClick={state.redo}><Redo2 size={15}/></IconControl></div>
      <div className="workspace-mode"><span className={state.Simulating ? 'mode-dot running' : 'mode-dot'}/>{state.Simulating ? 'Simulation' : 'Design'}<span className="mode-detail">{state.Simulating ? 'Circuit is read-only' : `${state.ComponentCount.toLocaleString()} components`}</span></div>
      <div className="toolbar-space"/>
      <SegmentedControl className="render-mode" aria-label="Render mode" size="xs" value={state.RenderMode} data={[{ value: '2d', label: '2D' }, { value: '2.5d', label: '2.5D' }]} onChange={value => state.setRenderMode(value as '2d' | '2.5d')}/>
      <span className="toolbar-divider"/>
      <div className="simulation-transport"><IconControl label="Previous tick" disabled={!props.frame || props.frame.running || props.frame.tick <= props.frame.first} onClick={() => props.onCommand('seek', Math.max(props.frame!.first, props.frame!.tick - props.step))}><SkipBack size={15}/></IconControl><IconControl label={props.frame?.running ? 'Pause simulation' : 'Run simulation'} disabled={!state.Simulating || props.starting} onClick={() => props.onCommand(props.frame?.running ? 'pause' : 'run', props.fullSpeed ? 0 : props.rate)}>{props.frame?.running ? <Pause size={15}/> : <Play size={15}/>}</IconControl><IconControl label="Next tick" disabled={!props.frame || props.frame.running} onClick={() => props.onCommand('step', props.step)}><SkipForward size={15}/></IconControl><NumberInput aria-label="Step length" size="xs" value={props.step} min={1} max={16} allowDecimal={false} className="step-count" disabled={!state.Simulating || !!props.frame?.running} onChange={value => { if (typeof value === 'number')
        props.onStep(value); }}/><IconControl label="Reset simulation" disabled={!state.Simulating} onClick={() => props.onCommand('reset')}><RotateCcw size={14}/></IconControl></div>
      <span className="toolbar-divider"/>
      <div className="rate-control"><span className="rate-label">Speed</span><Slider aria-label="Simulation frequency" min={0} max={Math.log10(capacity)} value={Math.min(Math.log10(props.rate), Math.log10(capacity))} step={0.01} label={value => `${Math.round(10 ** value).toLocaleString()} TPS`} onChange={value => props.onRate(Math.round(10 ** value))} onChangeEnd={value => props.onRate(Math.round(10 ** value), true)} size={3} color="teal"/><NumberInput aria-label="Ticks per second" value={props.rate} min={1} max={capacity} allowDecimal={false} hideControls size="xs" onChange={value => { if (typeof value === 'number')
        props.onRate(value); }} onBlur={() => props.onRate(props.rate, true)}/><Tooltip label="Run at full speed"><button className={`max-speed ${props.fullSpeed ? 'active' : ''}`} type="button" aria-label="Full speed" aria-pressed={props.fullSpeed} onClick={props.onFullSpeed}><Zap size={12}/>MAX</button></Tooltip></div>
      <Button size="xs" color={state.Simulating ? 'gray' : 'teal'} variant={state.Simulating ? 'default' : 'filled'} leftSection={state.Simulating ? <Settings2 size={13}/> : <Play size={13} fill="currentColor"/>} loading={props.starting} onClick={props.onToggle}>{state.Simulating ? 'Back to design' : 'Run circuit'}</Button>
      <span className="toolbar-divider"/><IconControl label="Toggle inspector" onClick={() => useEditor.setState({ RightOpen: !state.RightOpen })}>{state.RightOpen ? <PanelRightClose size={16}/> : <PanelRightOpen size={16}/>}</IconControl>
    </div>
  </>;
}
