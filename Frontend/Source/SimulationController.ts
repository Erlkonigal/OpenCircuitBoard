import { useCallback, useEffect, useRef, useState } from 'react';
import { useEditor } from './EditorStore';
import * as Native from './Native';
export function useSimulation(report: (error: unknown) => void) {
    const [frame, setFrame] = useState<Native.Frame | null>(null);
    const [starting, setStarting] = useState(false);
    const latest = useRef<Native.Frame | null>(null);
    const generation = useRef(0);
    const queue = useRef(Promise.resolve());
    const simulating = useEditor(state => state.Simulating);
    const accept = useCallback((next: Native.Frame | null) => {
        if (!next)
            return;
        const previous = latest.current;
        if (previous && previous.session === next.session && next.sequence <= previous.sequence)
            return;
        latest.current = next;
        setFrame(next);
        Native.applyFrame(next);
    }, []);
    const command = useCallback((action: string, value = 0) => {
        const token = generation.current;
        queue.current = queue.current.then(async () => {
            if (token !== generation.current || !latest.current)
                return;
            try {
                const next = await Native.simulation(action, latest.current.session, value);
                if (token === generation.current)
                    accept(next);
            }
            catch (error) {
                if (token !== generation.current)
                    return;
                generation.current++;
                latest.current = null;
                setFrame(null);
                useEditor.setState({ Simulating: false, Runtime: new Map(), RuntimeGrid: null });
                report(error);
                await Native.simulation('release', 0).catch(() => { });
            }
        });
        return queue.current;
    }, [accept, report]);
    const stop = useCallback(async () => {
        generation.current++;
        latest.current = null;
        setFrame(null);
        useEditor.setState({ Simulating: false, Runtime: new Map(), RuntimeGrid: null });
        await queue.current;
        if (Native.isDesktop())
            await Native.simulation('release', 0).catch(report);
    }, [report]);
    const start = useCallback(async (rate: number) => {
        if (useEditor.getState().Simulating)
            return;
        setStarting(true);
        const token = ++generation.current;
        useEditor.getState().cancel();
        useEditor.setState({ Simulating: true });
        try {
            await queue.current;
            const result = await Native.compile(useEditor.getState().export());
            if (token !== generation.current)
                return;
            latest.current = null;
            accept(result);
            useEditor.getState().log('Circuit compiled. Simulation ready.');
            await command('run', rate);
        }
        catch (error) {
            if (token === generation.current) {
                useEditor.setState({ Simulating: false, Runtime: new Map(), RuntimeGrid: null });
                report(error);
            }
        }
        finally {
            setStarting(false);
        }
    }, [accept, command, report]);
    useEffect(() => {
        if (!simulating)
            return;
        let cancelled = false;
        let timer: number;
        const poll = async () => {
            await command('poll', latest.current?.sequence ?? 0);
            if (!cancelled)
                timer = window.setTimeout(poll, 100);
        };
        timer = window.setTimeout(poll, 100);
        return () => { cancelled = true; window.clearTimeout(timer); };
    }, [simulating, command]);
    useEffect(() => () => {
        generation.current++;
        if (Native.isDesktop())
            void Native.simulation('release', 0).catch(() => { });
    }, []);
    return { frame, starting, command, start, stop };
}
