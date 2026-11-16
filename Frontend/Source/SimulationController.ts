import { useCallback, useEffect, useRef, useState } from 'react';
import { useEditor } from './EditorStore';
import * as Native from './Native';
export function useSimulation(report: (error: unknown) => void) {
    const [frame, setFrame] = useState<Native.Frame | null>(null);
    const [starting, setStarting] = useState(false);
    const latest = useRef<Native.Frame | null>(null);
    const generation = useRef(0);
    const queue = useRef(Promise.resolve());
    const polling = useRef(false);
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
        if (action === 'poll') {
            if (polling.current)
                return queue.current;
            polling.current = true;
        }
        const token = generation.current;
        queue.current = queue.current.then(async () => {
            if (token !== generation.current || !latest.current || (action === 'poll' && !latest.current.running))
                return;
            try {
                const next = await Native.simulation(action, latest.current.session, action === 'poll' ? latest.current.sequence : value);
                if (token === generation.current)
                    accept(next);
            }
            catch (error) {
                if (token !== generation.current)
                    return;
                generation.current++;
                setStarting(false);
                latest.current = null;
                setFrame(null);
                useEditor.setState({ Simulating: false, Runtime: new Map(), RuntimeGrid: null });
                report(error);
                await Native.simulation('release', 0).catch(() => { });
            }
        }).finally(() => {
            if (action === 'poll')
                polling.current = false;
        });
        return queue.current;
    }, [accept, report]);
    const stop = useCallback(async () => {
        generation.current++;
        setStarting(false);
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
                latest.current = null;
                setFrame(null);
                useEditor.setState({ Simulating: false, Runtime: new Map(), RuntimeGrid: null });
                report(error);
            }
        }
        finally {
            if (token === generation.current)
                setStarting(false);
        }
    }, [accept, command, report]);
    const running = frame?.running ?? false;
    useEffect(() => {
        if (!simulating || !running)
            return;
        let animation = 0;
        const poll = () => {
            // Commands share one serial queue; at most one poll may wait or run.
            void command('poll');
            animation = requestAnimationFrame(poll);
        };
        animation = requestAnimationFrame(poll);
        return () => cancelAnimationFrame(animation);
    }, [simulating, running, command]);
    useEffect(() => () => {
        generation.current++;
        if (Native.isDesktop())
            void Native.simulation('release', 0).catch(() => { });
    }, []);
    return { frame, starting, command, start, stop };
}
