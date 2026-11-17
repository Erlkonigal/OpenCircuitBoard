import { memo, useEffect, useMemo, useState } from 'react';
import { useShallow } from 'zustand/react/shallow';
import { ActionIcon, Badge, Button, Group, Modal, NumberInput, ScrollArea, SegmentedControl, TextInput, Tooltip } from '@mantine/core';
import { ArrowUpRight, Combine, Clipboard, Copy, Grid2X2, Layers3, MousePointer2, Paintbrush, Search, Scissors, Settings2, Trash2, X } from 'lucide-react';
import { shortcutFor } from './EditorShortcuts';
import { selectionCount, selectionSamples } from './Selection';
import { useEditor } from './EditorStore';
import { iconUrl, isDirectional, TraceToolIds, Inks, inkColor, paletteId, SelectableToolIds, type Grid, type Point, type Tile } from './Model';
import { inspectCell, type Frame } from './Native';
import { InkThumbnail } from './InkThumbnail';
export function ToolGlyph({ id, size = 18, direction = 0 }: {
    id: string;
    size?: number;
    direction?: number;
}) {
    return <span className="tool-glyph" aria-hidden style={{ width: size, height: size, backgroundColor: inkColor(id), maskImage: `url("${iconUrl(id)}")`, transform: `rotate(${direction * 90}deg)` }}/>;
}
export const ComponentLibrary = memo(function ComponentLibrary() {
    const editTool = useEditor(state => state.EditTool);
    const selected = useEditor(state => state.Board.selectedTool);
    const simulating = useEditor(state => state.Simulating);
    const direction = useEditor(state => state.DrawSettings.direction ?? 0);
    const [query, setQuery] = useState('');
    const categories = ['Space Optimization', 'Trace', 'Gates', 'General Components'];
    const names: Record<string, string> = { 'Space Optimization': 'Routing', Trace: 'Connections', Gates: 'Logic gates', 'General Components': 'Sources & output' };
    const matching = Inks.filter(ink => `${ink.title} ${ink.category}`.toLowerCase().includes(query.toLowerCase().trim()));
    const tools=[{Id:'pointer',Label:'Pointer',Icon:MousePointer2},{Id:'draw',Label:'Draw',Icon:Paintbrush},{Id:'merge',Label:'Merge',Icon:Combine},{Id:'split',Label:'Split',Icon:Scissors}] as const;
    const matchingTools=tools.filter(tool=>tool.Label.toLowerCase().includes(query.toLowerCase().trim()));
    return <>
    <div className="panel-heading"><div><span className="eyebrow">BUILD YOUR CIRCUIT</span><h2>Components</h2></div><Badge size="sm" variant="light" color="gray">{SelectableToolIds.length - 1}</Badge></div>
    <div className="library-search"><TextInput aria-label="Search components" placeholder="Find a component..." size="xs" leftSection={<Search size={14}/>} value={query} onChange={event => setQuery(event.currentTarget.value)}/></div>
    <ScrollArea className="panel-scroll" offsetScrollbars>
      <div className="component-groups">
        {matchingTools.length>0&&<section className="component-group"><h3>Tools</h3><div className="component-grid">
          {matchingTools.map(({Id,Label,Icon})=><Tooltip key={Id} label={`${Label} (${shortcutFor(Id)})`} position="right" openDelay={600}><button type="button" className={`component-button ${editTool===Id?'active':''}`} aria-label={Label} aria-pressed={editTool===Id} disabled={simulating} onClick={()=>useEditor.getState().selectTool(Id)}><Icon size={18}/><span>{Label}</span></button></Tooltip>)}
        </div></section>}
        {categories.map(category => {
            const inks = matching.filter(ink => ink.category === category);
            if (!inks.length)
                return null;
            return <section className="component-group" key={category}><h3>{names[category]}</h3><div className="component-grid">{inks.map(ink => {
                    const active = editTool === 'draw' && paletteId(selected) === ink.id;
                    return <Tooltip key={ink.id} label={ink.title} position="right" openDelay={600}><button type="button" className={`component-button ${active ? 'active' : ''}`} aria-label={ink.title} aria-pressed={active} disabled={simulating} onClick={() => useEditor.getState().selectTool(active ? selected : ink.id)}><ToolGlyph id={active ? selected : ink.id} direction={active && isDirectional(ink.id) ? direction : 0}/><span>{ink.title}</span>{active && <span className="component-active-dot"/>}</button></Tooltip>;
                })}</div></section>;
        })}
        {!matching.length && !matchingTools.length && <div className="panel-empty"><Search size={22}/><p>No matching components</p><small>Try a name such as clock or trace.</small></div>}
      </div>
    </ScrollArea>
    <div className="library-note"><MousePointer2 size={14}/><span>{({pointer:'Drag to select; drag selected components to move. Shift adds.',draw:'Drag to draw; Shift-drag fills a rectangle. Right-click for Pointer.',merge:'Click adjacent regions, then press G.',split:'Drag along grid edges. Release to split.'})[editTool]}</span></div>
  </>;
});
export function ClipboardLibrary({ cursor, onSaveBlueprint }: {
    onSaveBlueprint: () => void;
    cursor: Point;
}) {
    const entries = useEditor(state => state.Clipboard);
    const selected = useEditor(state => state.ClipboardIndex);
    const simulating = useEditor(state => state.Simulating);
    return <>
    <div className="panel-heading"><div><span className="eyebrow">REUSE & REPEAT</span><h2>Clipboard</h2></div><Badge size="sm" variant="light" color="gray">{entries.length}/4</Badge></div>
    <ScrollArea className="panel-scroll" offsetScrollbars><div className="clipboard-list">{entries.map((item, index) => <button type="button" className={`clipboard-entry ${selected === index ? 'active' : ''}`} key={index} aria-label={`Clipboard item ${index + 1}`} onClick={() => useEditor.setState({ ClipboardIndex: index })}><div className="clipboard-entry-title"><strong>{index === 0 ? 'Latest selection' : `Selection ${index + 1}`}</strong><span>{item.tiles.length} cells</span></div><InkThumbnail item={item}/><div className="clipboard-entry-meta"><span>{item.width} x {item.height}</span><span>{selected === index ? 'Ready to paste' : 'Select to use'}</span></div></button>)}{!entries.length && <div className="panel-empty"><Clipboard size={26}/><p>A place for your building blocks</p><small>Select cells and press Ctrl+C to keep a copy here.</small></div>}</div></ScrollArea>
    <div className="panel-bottom"><Button fullWidth mb="xs" size="xs" variant="default" disabled={selected < 0 || simulating} onClick={onSaveBlueprint}>Save as blueprint</Button><Button fullWidth size="xs" variant="light" leftSection={<Copy size={14}/>} disabled={selected < 0 || simulating} onClick={() => useEditor.getState().paste(cursor)}>Paste selection <kbd>Ctrl V</kbd></Button></div>
  </>;
}
export function BlueprintLibrary({ onCreate }: { onCreate: (fromClipboard: boolean) => void }) {
    const entries = useEditor(state => state.Blueprints);
    const simulating = useEditor(state => state.Simulating);
    const selection = useEditor(state => state.Selection);
    const clipboardIndex = useEditor(state => state.ClipboardIndex);
    const current = useEditor(state => state.Clipboard[state.ClipboardIndex]);
    const [query, setQuery] = useState('');
    const [renaming, setRenaming] = useState<string | null>(null);
    const [name, setName] = useState('');
    const matching = useMemo(() => entries.filter(item => item.name.toLowerCase().includes(query.trim().toLowerCase())), [entries, query]);
    const [scroll, setScroll] = useState(0);
    const rowHeight = 178, start = Math.max(0, Math.floor(scroll / rowHeight) - 2), end = Math.min(matching.length, start + 10);
    return <>
      <div className="panel-heading"><div><span className="eyebrow">SAVED IN THIS PROJECT</span><h2>Blueprints</h2></div><Badge size="sm" variant="light" color="gray">{entries.length}</Badge></div>
      <div className="library-search"><TextInput aria-label="Search blueprints" placeholder="Find a blueprint..." size="xs" leftSection={<Search size={14}/>} value={query} onChange={event => { setQuery(event.currentTarget.value); setScroll(0); }}/></div>
      <ScrollArea className="panel-scroll" onScrollPositionChange={({ y }) => setScroll(y)}><div className="blueprint-list" style={{ height: matching.length * rowHeight }}>
        {matching.slice(start, end).map((item, index) => <div className="blueprint-entry" key={item.id} style={{ position: 'absolute', top: (start + index) * rowHeight, height: rowHeight - 10 }}>
          <button type="button" className="blueprint-use" aria-pressed={current?.tiles === item.tiles} aria-label={`Copy blueprint ${item.name}`} disabled={simulating} onClick={() => useEditor.getState().useBlueprint(item.id)}><strong>{item.name}</strong><InkThumbnail item={item}/><span>{item.width} x {item.height} | {item.tiles.length.toLocaleString()} cells</span></button>
          <div className="blueprint-actions"><Tooltip label="Rename blueprint"><ActionIcon size="sm" variant="subtle" aria-label={`Rename blueprint ${item.name}`} disabled={simulating} onClick={() => { setRenaming(item.id); setName(item.name); }}><Settings2 size={13}/></ActionIcon></Tooltip><Tooltip label="Delete blueprint"><ActionIcon size="sm" variant="subtle" color="red" aria-label={`Delete blueprint ${item.name}`} disabled={simulating} onClick={() => useEditor.getState().deleteBlueprint(item.id)}><Trash2 size={13}/></ActionIcon></Tooltip></div>
        </div>)}
      </div>{!matching.length && <div className="panel-empty"><Layers3 size={24}/><p>{entries.length ? 'No matching blueprints' : 'Keep reusable circuits here'}</p><small>Save a selection or clipboard item, then select it and use Ctrl+V.</small></div>}</ScrollArea>
      <div className="panel-bottom"><Button fullWidth mb="xs" size="xs" disabled={!selection || simulating} onClick={() => onCreate(false)}>Save selection as blueprint</Button><Button fullWidth size="xs" variant="default" disabled={clipboardIndex < 0 || simulating} onClick={() => onCreate(true)}>Save clipboard as blueprint</Button></div>
      <Modal opened={!!renaming} onClose={() => setRenaming(null)} title="Rename blueprint" size="xs"><form onSubmit={event => { event.preventDefault(); if (renaming && name.trim()) { useEditor.getState().renameBlueprint(renaming, name); setRenaming(null); } }}><TextInput data-autofocus aria-label="Blueprint name" value={name} onChange={event => setName(event.currentTarget.value)}/><Button type="submit" mt="md" fullWidth disabled={!name.trim()}>Rename</Button></form></Modal>
    </>;
}
export function ToolSettings({id,selection=false}:{id:string;selection?:boolean}) {
    const state=useEditor(useShallow(s=>({Board:s.Board,DrawSettings:s.DrawSettings,Selection:s.Selection,Tiles:s.Tiles,Components:s.Components,Simulating:s.Simulating})));
    const samples=useMemo(()=>selection?selectionSamples(state):[],[selection,state.Selection,state.Tiles]);
    const first=selection?samples[0]:state.DrawSettings;
    const family=paletteId(id),configure=(patch:Partial<Tile>)=>useEditor.getState().configure(patch,selection);
    const settingValue = (tile: Partial<Tile> | undefined, field: keyof Tile) => tile?.[field] ?? (field === 'fixedDrive' ? undefined : field === 'defaultValue' ? false : 0);
    const mixed = (field: keyof Tile) => samples.some(tile => settingValue(tile, field) !== settingValue(samples[0], field));
    return <div className="field-stack">
      {isDirectional(id)&&<><label>Direction</label><SegmentedControl aria-label="Direction" size="xs" disabled={state.Simulating} value={mixed('direction')?'mixed':String(first?.direction??0)} data={[{label:'Right',value:'0'},{label:'Down',value:'1'},{label:'Left',value:'2'},{label:'Up',value:'3'}]} onChange={value=>configure({direction:Number(value)})}/><small>R rotates clockwise; Shift+R rotates back. The icon shows the connection direction.</small></>}
      {family==='clock'&&<NumberInput label="Clock hold" description={mixed('clockHoldTicks')?'Mixed values across selected components':'Ticks before switching state'} placeholder="Mixed" aria-label="Clock hold" min={1} max={2147483647} allowDecimal={false} size="xs" value={mixed('clockHoldTicks')?'':samples[0]?.clockHoldTicks??state.Board.clockHoldTicks} disabled={state.Simulating} onChange={value=>{if(typeof value==='number')configure({clockHoldTicks:value});}}/>}
      {family==='latch'&&<><label>Initial state</label><SegmentedControl fullWidth size="xs" disabled={state.Simulating} value={mixed('isOn')?'mixed':(samples[0]?.isOn??state.Board.latchInitialState)?'on':'off'} data={[{label:'On',value:'on'},{label:'Off',value:'off'}]} onChange={value=>configure({isOn:value==='on'})}/></>}
      {family==='trace'&&<><label>Signal color</label><div className="color-options">{TraceToolIds.map(variant=><Tooltip key={variant} label={variant.replace(/^trace/,'')||'Yellow'}><button type="button" className={'color-option '+(!mixed('toolId')&&(samples[0]?.toolId??state.Board.selectedTool)===variant?'active':'')} style={{'--signal-color':inkColor(variant)} as React.CSSProperties} aria-label={variant} aria-pressed={!mixed('toolId')&&(samples[0]?.toolId??state.Board.selectedTool)===variant} disabled={state.Simulating} onClick={()=>configure({toolId:variant})}/></Tooltip>)}</div>
        <label>Fixed drive</label><SegmentedControl aria-label="Fixed drive" size="xs" disabled={state.Simulating} value={mixed('fixedDrive')?'mixed':first?.fixedDrive===undefined?'none':first.fixedDrive?'1':'0'} data={[{label:'None',value:'none'},{label:'0',value:'0'},{label:'1',value:'1'}]} onChange={value=>configure({fixedDrive:value==='none'?undefined:value==='1'})}/>
        <label>Undriven default</label><SegmentedControl aria-label="Undriven default" size="xs" disabled={state.Simulating} value={mixed('defaultValue')?'mixed':first?.defaultValue?'1':'0'} data={['0','1']} onChange={value=>configure({defaultValue:value==='1'})}/><small>Defaults apply only when no connected source exists. A fixed 0 is a source. Multiple sources combine with OR.</small></>}
      {family==='cross'&&<><label>Join horizontal and vertical</label><div className="color-options">{TraceToolIds.map((variant,c)=><Tooltip key={variant} label={variant.replace(/^trace/,'')||'Yellow'}><button type="button" className={'color-option '+((first?.crossMask??0)&(1<<c)?'active':'')} style={{'--signal-color':inkColor(variant)} as React.CSSProperties} aria-label={'Join '+variant} aria-pressed={!!((first?.crossMask??0)&(1<<c))} disabled={state.Simulating} onClick={()=>configure({crossMask:(first?.crossMask??0)^(1<<c)})}/></Tooltip>)}</div><small>Selected colors join both axes. Other colors cross independently.</small></>}
      <p className="property-description">{({bus:'Eight independent colors. Multiple sources combine with OR. Attach colored Trace to connect components.',switch:'The two data terminals carry signals in either direction. The control connects or disconnects them one tick later.',buffer:'The input is opposite the output. One tick delay.',not:'Inverts the input opposite the output. One tick delay.',led:'Displays the input opposite its facing direction one tick later.',clock:'The output faces the selected direction. Toggles each configured hold interval.',latch:'Output only, facing the selected direction. Click during simulation to toggle its stored state.'} as Record<string,string>)[family]??(isDirectional(id)?'Output faces the selected direction. Other input sides accept independent traces. One tick delay.':'') }</p>
    </div>;
}
function NetworkValues({frame}:{frame:Frame|null}) {
    const tile=useEditor(s=>s.Selection?.ids.length===1?s.Components.sample(s.Selection.ids[0]):undefined);
    const [values,setValues]=useState<number[]>([]);
    useEffect(()=>{let current=true;setValues([]);if(frame&&tile&&['bus','cross'].includes(tile.toolId)){const cell=(tile.y-frame.originY)*frame.width+tile.x-frame.originX;void inspectCell(frame.session,cell).then(v=>{if(current)setValues(v);}).catch(()=>{});}return()=>{current=false;};},[frame?.session,frame?.sequence,tile]);
    return values.length?<section className="inspector-section"><h3>Connected signals</h3>{values.length===16&&<small>Horizontal / vertical</small>}{[0,...(values.length===16?[8]:[])].map(offset=><div key={offset} className="color-options">{TraceToolIds.map((tool,c)=><span key={tool} title={tool} style={{color:inkColor(tool)}}>{values[offset+c]}</span>)}</div>)}</section>:null;
}
function BoardProperties() {
    const grid = useEditor(state => state.Board.grid);
    const simulating = useEditor(state => state.Simulating);
    const [draft, setDraft] = useState(grid);
    const [error, setError] = useState('');
    useEffect(() => setDraft(grid), [grid]);
    const fields: [
        keyof Grid,
        string
    ][] = [['width', 'Width'], ['height', 'Height'], ['originX', 'Origin X'], ['originY', 'Origin Y']];
    const changed = fields.some(([field]) => draft[field] !== grid[field]);
    const apply = () => {
        if (!useEditor.getState().resize(draft)) {
            setError('Keep at least 4 x 4 cells and include all components.');
            return;
        }
        useEditor.getState().commit();
        setError('');
    };
    return <section className="inspector-section"><h3><Grid2X2 size={14}/>Canvas</h3><div className="property-grid">{fields.map(([field, label]) => <NumberInput key={field} label={label} aria-label={`Canvas ${label}`} size="xs" value={draft[field]} allowDecimal={false} min={field === 'width' || field === 'height' ? 4 : -2147483648} max={2147483647} disabled={simulating} onChange={value => { if (typeof value === 'number')
        setDraft(previous => ({ ...previous, [field]: value })); }}/>)}</div>{changed && <Button mt="sm" size="xs" fullWidth variant="light" disabled={simulating} onClick={apply}>Apply canvas size</Button>}{error && <p className="field-error">{error}</p>}</section>;
}
export function Inspector({frame,onSaveBlueprint}:{onSaveBlueprint:()=>void;frame:Frame|null}) {
    const state=useEditor(useShallow(s=>({Board:s.Board,DrawSettings:s.DrawSettings,Components:s.Components,EditTool:s.EditTool,MergeIds:s.MergeIds,MergeError:s.MergeError,SplitNotice:s.SplitNotice,Selection:s.Selection,Tiles:s.Tiles,Simulating:s.Simulating})));
    const samples=useMemo(()=>selectionSamples(state),[state.Selection,state.Tiles]);
    const componentSelection=!!state.Selection;
    const homogeneous=samples.length>0&&samples.every(tile=>paletteId(tile.toolId)===paletteId(samples[0].toolId));
    const id=homogeneous?samples[0].toolId:state.Board.selectedTool,title=Inks.find(ink=>ink.id===paletteId(id))?.title??id;
    const pending=state.EditTool==='merge'||state.EditTool==='split';
    return <>
      <div className="panel-heading inspector-heading"><div><span className="eyebrow">FINE TUNE</span><h2>Inspector</h2></div><Settings2 size={17}/></div>
      <ScrollArea className="panel-scroll" offsetScrollbars>
        <section className="inspector-section"><div className="section-topline"><h3>{pending?state.EditTool==='merge'?'Merge components':'Split components':componentSelection?'Selected components':state.EditTool==='draw'?'Draw defaults':'Pointer'}</h3>{state.Selection&&<Badge size="xs" variant="light" color="teal">{selectionCount(state)} cells</Badge>}</div>
          {pending?<>
            <div className="active-component"><div className="active-component-symbol">{state.EditTool==='merge'?<Combine size={23}/>:<Scissors size={23}/>}</div><div><strong>{state.EditTool==='merge'?`${state.MergeIds.length} regions picked`:'Grid-edge cut'}</strong><small>{state.EditTool==='merge'?'Confirm on the canvas action bar':'Release to split; continue with another line'}</small></div></div>
            <p className="property-description">{state.EditTool==='merge'?'Click whole adjacent components with the same ink and settings. Press G to confirm.':'Draw along cell edges and release to split components. Retrace the line to shorten it. Each resulting piece can be selected and edited independently.'}</p>
            {state.MergeError&&<p className="field-error" role="alert">{state.MergeError}</p>}
            <p className="property-description">{state.EditTool==='split'?'Right-click or Q returns to Pointer. Completed cuts are kept.':'Right-click or Q cancels and returns to Pointer.'}</p>
          </>:componentSelection||state.EditTool==='draw'?<>
            <div className="active-component"><div className="active-component-symbol"><ToolGlyph id={id} size={23} direction={isDirectional(id) ? componentSelection ? samples[0]?.direction ?? 0 : state.DrawSettings.direction ?? 0 : 0}/></div><div><strong>{componentSelection&&!homogeneous?'Mixed components':title}</strong><small>{componentSelection?`${samples.length} whole components`:'Settings for new strokes'}</small></div></div>
            {!componentSelection||homogeneous?<ToolSettings key={`${id}:${componentSelection}`} id={id} selection={componentSelection}/>:<p className="property-description">Select components of the same type to edit common properties.</p>}
          </>:<p className="property-description">Click a component to view its properties. Drag on blank space or an unselected component to select; drag selected components to move. Shift-click toggles components; Shift-drag adds them.</p>}
          {state.Selection&&!pending&&<Group mt="md" gap={6}><Button size="xs" variant="default" leftSection={<Copy size={12}/>} disabled={state.Simulating} onClick={()=>useEditor.getState().copy()}>Copy</Button><Button size="xs" variant="subtle" disabled={state.Simulating} onClick={onSaveBlueprint}>Save blueprint</Button><ActionIcon ml="auto" size="sm" variant="subtle" color="gray" aria-label="Clear selection" onClick={()=>useEditor.getState().selectComponents([])}><X size={13}/></ActionIcon></Group>}
        </section>
        <NetworkValues frame={frame}/>
        {frame&&<section className="inspector-section simulation-summary"><h3><Layers3 size={14}/>Live simulation</h3><div className="metric-grid"><div><span>Current tick</span><strong>{frame.tick.toLocaleString()}</strong></div><div><span>Throughput</span><strong>{Math.round(frame.tps).toLocaleString()}<small> TPS</small></strong></div></div><div className="capacity-row"><span>Measured capacity</span><span>{Math.round(frame.capacity).toLocaleString()} TPS</span></div></section>}
        <BoardProperties/>
        <section className="inspector-section inspector-tips"><h3>Keep your flow</h3><p>V selects. B draws. X deletes.<br/>Right-click or Q returns to Pointer.<br/>Space + drag pans. Scroll zooms.</p><span><ArrowUpRight size={13}/>Drag a canvas corner to resize.</span></section>
      </ScrollArea>
    </>;
}
export function ActivityPanel({ onClose }: {
    onClose: () => void;
}) {
    const events = useEditor(state => state.Events);
    return <section className="activity-panel" data-testid="activity-panel"><header><div><span className="activity-dot"/><strong>Activity</strong><span className="muted">{events.length} events</span></div><div><ActionIcon variant="subtle" size="sm" color="gray" aria-label="Clear activity" onClick={() => useEditor.setState({ Events: [] })}><Trash2 size={13}/></ActionIcon><ActionIcon variant="subtle" size="sm" color="gray" aria-label="Close activity" onClick={onClose}><X size={14}/></ActionIcon></div></header><ScrollArea className="activity-scroll">{events.length ? events.map((event, index) => <div className="activity-entry" key={index}>{event}</div>) : <div className="activity-empty">All quiet. Your project and simulation events will appear here.</div>}</ScrollArea></section>;
}
