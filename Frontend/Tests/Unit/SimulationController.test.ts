import { act, cleanup, renderHook } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { useSimulation } from '../../Source/SimulationController';
import { useEditor } from '../../Source/EditorStore';
import { newBoard } from '../../Source/Model';
import * as Native from '../../Source/Native';
vi.mock('../../Source/Native', async original => ({
    ...await original<typeof import('../../Source/Native')>(),
    compile: vi.fn(), simulation: vi.fn(), isDesktop: () => true
}));
const Animations = new Map<number, FrameRequestCallback>();
let animationId = 0, timestamp = 0, session = 0, sequence = 0, tick = 0, state = 0, running = false;
function frame(patch: Partial<Native.Frame> = {}): Native.Frame {
    return { session, sequence: ++sequence, tick, width: 2, height: 1, originX: 0, originY: 0,
        full: false, running, tps: 120, capacity: 10000, first: 0, last: tick, data: new Int32Array(), ...patch };
}
async function displayFrames(count = 1, rate = 60) {
    for (let i = 0; i < count; i++) await act(async () => {
        timestamp += 1000 / rate;
        const pending = [...Animations.values()]; Animations.clear();
        for (const callback of pending) callback(timestamp);
    });
}
async function started() {
    const report = vi.fn(), hook = renderHook(() => useSimulation(report));
    await act(async () => { await hook.result.current.start(120); });
    return { ...hook, report };
}
beforeEach(() => {
    vi.useFakeTimers(); Animations.clear(); animationId = 0; timestamp = 0; session = 0; sequence = 0; tick = 0; state = 0; running = false;
    useEditor.getState().load(newBoard());
    useEditor.setState({ Simulating: false, RuntimeGrid: null });
    vi.stubGlobal('requestAnimationFrame', (callback: FrameRequestCallback) => { const id = ++animationId; Animations.set(id, callback); return id; });
    vi.stubGlobal('cancelAnimationFrame', (id: number) => Animations.delete(id));
    vi.mocked(Native.compile).mockReset().mockImplementation(async () => { session++; sequence = 0; tick = 0; running = false; return frame({ full: true, data: new Uint8Array(2) }); });
    vi.mocked(Native.simulation).mockReset().mockImplementation(async action => {
        if (action === 'release') return null;
        if (action === 'run') running = true;
        if (action === 'pause') running = false;
        if (action === 'poll') tick++;
        if (action === 'toggle') { state = 1 - state; return frame({ data: new Int32Array([0, state]) }); }
        return frame();
    });
});
afterEach(() => { cleanup(); vi.unstubAllGlobals(); vi.useRealTimers(); });
const polls = () => vi.mocked(Native.simulation).mock.calls.filter(call => call[0] === 'poll');
describe('Display-driven simulation polling', () => {
    it.each([60, 120, 144])('samples each available display frame at %i Hz without the old timer ceiling', async rate => {
        const hook = await started();
        await displayFrames(rate, rate);
        expect(polls()).toHaveLength(rate);
        expect(hook.result.current.frame?.tick).toBe(rate);
        expect(hook.report).not.toHaveBeenCalled();
    });
    it('does not poll without display callbacks, resumes immediately and stops on pause', async () => {
        const hook = await started();
        await act(async () => { await vi.advanceTimersByTimeAsync(5000); });
        expect(polls()).toHaveLength(0);
        await displayFrames(); expect(polls()).toHaveLength(1);
        await act(async () => { await hook.result.current.command('pause'); });
        expect(Animations.size).toBe(0);
        await displayFrames(5); expect(polls()).toHaveLength(1);
        await act(async () => { await hook.result.current.command('run', 240); });
        await displayFrames(); expect(polls()).toHaveLength(2);
        expect(vi.mocked(Native.simulation).mock.calls).toContainEqual(['run', session, 240]);
    });
    it('bounds slow polling and acknowledges the latest control response when the next poll executes', async () => {
        const hook = await started();
        let finish!: (next: Native.Frame) => void;
        vi.mocked(Native.simulation).mockImplementationOnce(() => new Promise(resolve => { finish = resolve; }));
        await displayFrames(12);
        expect(polls()).toHaveLength(1);
        let toggle!: Promise<void>;
        act(() => { toggle = hook.result.current.command('toggle'); });
        await displayFrames(12);
        expect(polls()).toHaveLength(1);
        await act(async () => { finish(frame({ data: new Int32Array([1, 1]) })); await toggle; });
        expect(useEditor.getState().RuntimeGrid!.states).toEqual(new Uint8Array([1, 1]));
        const acknowledged = hook.result.current.frame!.sequence;
        await displayFrames();
        expect(polls()).toHaveLength(2);
        expect(polls()[1]).toEqual(['poll', session, acknowledged]);
    });
    it('reads the acknowledgement at execution time and cancels queued polling after pause', async () => {
        const hook = await started();
        let finish!: (next: Native.Frame) => void;
        vi.mocked(Native.simulation).mockImplementationOnce(() => new Promise(resolve => { finish = resolve; }));
        let toggle!: Promise<void>;
        act(() => { toggle = hook.result.current.command('toggle'); });
        await act(async () => {});
        await displayFrames(); // One poll is queued behind the control request.
        const next = frame({ data: new Int32Array([0, 1]) });
        await act(async () => { finish(next); await toggle; });
        expect(polls()[0]).toEqual(['poll', session, next.sequence]);
        let finishPause!: (next: Native.Frame) => void;
        vi.mocked(Native.simulation).mockImplementationOnce(() => new Promise(resolve => { finishPause = resolve; }));
        let pause!: Promise<void>;
        act(() => { pause = hook.result.current.command('pause'); });
        await act(async () => {}); await displayFrames(4);
        await act(async () => { running = false; finishPause(frame()); await pause; });
        expect(polls()).toHaveLength(1);
        expect(Animations.size).toBe(0);
    });
    it('rejects responses after stop and applies a newly compiled session independently', async () => {
        const hook = await started();
        let finish!: (next: Native.Frame) => void;
        vi.mocked(Native.simulation).mockImplementationOnce(() => new Promise(resolve => { finish = resolve; }));
        await displayFrames();
        let stop!: Promise<void>;
        act(() => { stop = hook.result.current.stop(); });
        await act(async () => { finish(frame({ data: new Int32Array([0, 1]) })); await stop; });
        expect(hook.result.current.frame).toBeNull(); expect(useEditor.getState().RuntimeGrid).toBeNull(); expect(Animations.size).toBe(0);
        await act(async () => { await hook.result.current.start(144); });
        expect(hook.result.current.frame!.session).toBe(2);
        expect(useEditor.getState().RuntimeGrid!.states).toEqual(new Uint8Array(2));
        hook.unmount(); expect(Animations.size).toBe(0);
    });
    it('clears the starting state when the run command fails', async () => {
        const error = Error('SimulationWorkerStopped');
        vi.mocked(Native.simulation).mockRejectedValueOnce(error);
        const hook = await started();
        expect(hook.report).toHaveBeenCalledExactlyOnceWith(error);
        expect(hook.result.current.starting).toBe(false); expect(hook.result.current.frame).toBeNull();
        expect(useEditor.getState().Simulating).toBe(false); expect(Animations.size).toBe(0);
    });
    it('does not accept a compile result that arrives after stop', async () => {
        let finish!: (next: Native.Frame) => void;
        vi.mocked(Native.compile).mockImplementationOnce(() => new Promise(resolve => { finish = resolve; }));
        const report = vi.fn(), hook = renderHook(() => useSimulation(report));
        let start!: Promise<void>;
        act(() => { start = hook.result.current.start(120); });
        await act(async () => {});
        await act(async () => { await hook.result.current.stop(); });
        await act(async () => { finish(frame({ session: 99, full: true, data: new Uint8Array([1, 1]) })); await start; });
        expect(hook.result.current.frame).toBeNull(); expect(hook.result.current.starting).toBe(false);
        expect(useEditor.getState().RuntimeGrid).toBeNull(); expect(Animations.size).toBe(0);
        expect(vi.mocked(Native.simulation).mock.calls.some(call => call[0] === 'run')).toBe(false);
    });
    it('ignores repeated and older sequences without applying their deltas', async () => {
        const hook = await started(); await displayFrames();
        const previous = hook.result.current.frame!, grid = useEditor.getState().RuntimeGrid;
        for (const sequence of [previous.sequence, previous.sequence - 1]) {
            vi.mocked(Native.simulation).mockResolvedValueOnce({ ...previous, sequence, data: new Int32Array([0, 1]) });
            await displayFrames();
            expect(hook.result.current.frame).toBe(previous); expect(useEditor.getState().RuntimeGrid).toBe(grid);
            expect(grid!.states).toEqual(new Uint8Array(2));
        }
    });
    it('retains every accepted delta and preserves the runtime grid on metadata-only frames', async () => {
        const hook = await started(), original = useEditor.getState().RuntimeGrid;
        await displayFrames(3);
        expect(useEditor.getState().RuntimeGrid).toBe(original);
        vi.mocked(Native.simulation).mockResolvedValueOnce(frame({ data: new Int32Array([0, 1]) }));
        await displayFrames();
        vi.mocked(Native.simulation).mockResolvedValueOnce(frame({ data: new Int32Array([1, 1]) }));
        await displayFrames();
        const grid = useEditor.getState().RuntimeGrid!;
        expect(grid.states).toEqual(new Uint8Array([1, 1])); expect(grid.chunkVersions![0]).toBe(3);
        vi.mocked(Native.simulation).mockResolvedValueOnce(frame({ data: new Int32Array([0, 1]) }));
        await displayFrames(); expect(useEditor.getState().RuntimeGrid).toBe(grid);
        expect(hook.result.current.frame!.tick).toBe(3);
    });
});
