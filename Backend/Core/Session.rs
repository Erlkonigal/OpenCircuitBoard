use crate::{CompileInput, Simulation::Snapshot, SimulationCore};
use std::{
    collections::VecDeque,
    sync::mpsc::{self, Receiver, RecvTimeoutError, SyncSender},
    thread::{self, JoinHandle},
    time::{Duration, Instant},
};
#[derive(Clone)]
pub enum Action {
    Compile(CompileInput, (i32, i32)),
    Poll(u32, u32),
    Run(u32, f64),
    Pause(u32),
    Step(u32, i32),
    Seek(u32, u64),
    Toggle(u32, usize),
    Reset(u32),
    Release,
}
struct Request {
    Action: Action,
    Reply: SyncSender<Result<Vec<u8>, String>>,
}
pub struct Session {
    Sender: Option<SyncSender<Request>>,
    Worker: Option<JoinHandle<()>>,
}
impl Default for Session {
    fn default() -> Self {
        let (sender, receiver) = mpsc::sync_channel(64);
        Self {
            Sender: Some(sender),
            Worker: Some(
                thread::Builder::new()
                    .name("OcbSimulation".into())
                    .spawn(move || worker(receiver))
                    .expect("simulation thread"),
            ),
        }
    }
}
impl Session {
    pub fn request(&self, action: Action) -> Result<Vec<u8>, String> {
        let (reply, rx) = mpsc::sync_channel(1);
        self.Sender
            .as_ref()
            .ok_or("SimulationWorkerStopped")?
            .send(Request {
                Action: action,
                Reply: reply,
            })
            .map_err(|_| "SimulationWorkerStopped")?;
        rx.recv().map_err(|_| "SimulationWorkerStopped")?
    }
}
impl Drop for Session {
    fn drop(&mut self) {
        self.Sender.take();
        if let Some(worker) = self.Worker.take() {
            let _ = worker.join();
        }
    }
}
struct Runtime {
    Core: SimulationCore,
    Origin: (i32, i32),
    Id: u32,
    Sequence: u32,
    Running: bool,
    Rate: f64,
    Pending: Option<Vec<u8>>,
    Timeline: VecDeque<(u64, Snapshot)>,
    Bytes: usize,
    Tps: f64,
    Capacity: f64,
    ComputeSeconds: f64,
    Sample: Instant,
    SampleTicks: u64,
    Accumulator: f64,
    Last: Instant,
}
impl Runtime {
    fn check(&self, id: u32) -> Result<(), String> {
        if id != self.Id {
            Err("SimulationSessionExpired".into())
        } else {
            Ok(())
        }
    }
    fn snapshot(&mut self) {
        let value = self.Core.capture();
        self.Bytes += value.byteCount();
        self.Timeline.push_back((self.Core.Tick, value));
        while self.Timeline.len() > 256
            || (self.Bytes > 32 * 1024 * 1024 && self.Timeline.len() > 1)
        {
            self.Bytes -= self.Timeline.pop_front().unwrap().1.byteCount();
        }
    }
    fn pause(&mut self) {
        self.Running = false;
        self.Accumulator = 0.;
        if self.Timeline.is_empty() {
            self.snapshot();
        }
    }
    fn frame(&mut self, full: bool) -> Vec<u8> {
        let changes = self.Core.drain();
        let isFull = full || changes.len() * 4 > self.Core.Width * self.Core.Height / 8;
        self.Sequence = self.Sequence.wrapping_add(1).max(1);
        let mut bytes = Vec::with_capacity(
            80 + if isFull {
                self.Core.Width * self.Core.Height
            } else {
                changes.len() * 4
            },
        );
        for value in [
            0x4f434246,
            2,
            self.Id,
            self.Sequence,
            self.Core.Tick as u32,
            (self.Core.Tick >> 32) as u32,
            self.Core.Width as u32,
            self.Core.Height as u32,
            self.Origin.0 as u32,
            self.Origin.1 as u32,
            isFull as u32,
            self.Running as u32,
        ] {
            bytes.extend_from_slice(&value.to_le_bytes());
        }
        bytes.extend_from_slice(&self.Tps.to_le_bytes());
        bytes.extend_from_slice(
            &self
                .Timeline
                .front()
                .map_or(self.Core.Tick, |s| s.0)
                .to_le_bytes(),
        );
        bytes.extend_from_slice(
            &self
                .Timeline
                .back()
                .map_or(self.Core.Tick, |s| s.0)
                .to_le_bytes(),
        );
        bytes.extend_from_slice(&self.Capacity.to_le_bytes());
        if isFull {
            bytes.extend_from_slice(self.Core.states());
        } else {
            for change in changes {
                bytes.extend_from_slice(&change.to_le_bytes());
            }
        }
        self.Pending = Some(bytes.clone());
        bytes
    }
    fn handle(&mut self, action: Action) -> Result<Vec<u8>, String> {
        match action {
            Action::Poll(id, ack) => {
                self.check(id)?;
                if let Some(pending) = &self.Pending {
                    if ack != self.Sequence {
                        return Ok(pending.clone());
                    }
                }
                self.Pending = None;
                Ok(self.frame(false))
            }
            Action::Run(id, rate) => {
                self.check(id)?;
                if !rate.is_finite() || rate < 0. {
                    return Err("SimulationFrequencyInvalid".into());
                }
                self.Rate = rate;
                self.Running = true;
                self.Timeline.clear();
                self.Bytes = 0;
                self.Last = Instant::now();
                self.Accumulator = 0.;
                Ok(self.frame(true))
            }
            Action::Pause(id) => {
                self.check(id)?;
                self.pause();
                Ok(self.frame(true))
            }
            Action::Step(id, length) => {
                self.check(id)?;
                self.pause();
                for _ in 0..length.clamp(1, 16) {
                    let next = self.Core.Tick + 1;
                    if let Some((_, value)) = self.Timeline.iter().find(|s| s.0 == next) {
                        self.Core.restore(value)?;
                    } else {
                        self.Core.advanceSilent(1);
                        self.snapshot();
                    }
                }
                Ok(self.frame(true))
            }
            Action::Seek(id, tick) => {
                self.check(id)?;
                self.pause();
                let value = &self
                    .Timeline
                    .iter()
                    .find(|s| s.0 == tick)
                    .ok_or("SimulationTickUnavailable")?
                    .1;
                self.Core.restore(value)?;
                Ok(self.frame(true))
            }
            Action::Toggle(id, cell) => {
                self.check(id)?;
                self.Core.toggleLatch(cell)?;
                if !self.Running {
                    while self.Timeline.back().is_some_and(|s| s.0 >= self.Core.Tick) {
                        self.Bytes -= self.Timeline.pop_back().unwrap().1.byteCount();
                    }
                    self.snapshot();
                }
                Ok(self.frame(true))
            }
            Action::Reset(id) => {
                self.check(id)?;
                self.Core.resetSilent();
                self.Timeline.clear();
                self.Bytes = 0;
                if !self.Running {
                    self.snapshot();
                }
                Ok(self.frame(true))
            }
            _ => Err("SimulationCommandInvalid".into()),
        }
    }
    fn advance(&mut self) {
        if !self.Running {
            return;
        }
        let now = Instant::now();
        let elapsed = now.duration_since(self.Last).as_secs_f64();
        self.Last = now;
        self.Accumulator = (self.Accumulator + elapsed).min(0.25);
        let start = Instant::now();
        let mut advanced = 0u64;
        if self.Rate == 0. {
            while start.elapsed() < Duration::from_micros(2000) {
                self.Core.advanceSilent(64);
                advanced += 64;
            }
        } else {
            let ticks = (self.Accumulator * self.Rate).floor().min(i32::MAX as f64) as i32;
            let mut remaining = ticks;
            while remaining > 0 && start.elapsed() < Duration::from_micros(2000) {
                let batch = remaining.min(64);
                self.Core.advanceSilent(batch);
                remaining -= batch;
                advanced += batch as u64;
            }
            self.Accumulator = (self.Accumulator - advanced as f64 / self.Rate).max(0.);
        }
        if advanced > 0 {
            self.ComputeSeconds += start.elapsed().as_secs_f64();
        }
        self.SampleTicks += advanced;
        if self.Sample.elapsed() >= Duration::from_millis(250) {
            self.Tps = self.SampleTicks as f64 / self.Sample.elapsed().as_secs_f64();
            if self.SampleTicks > 0 && self.ComputeSeconds > 0. {
                let measured = self.SampleTicks as f64 / self.ComputeSeconds;
                self.Capacity = if measured < self.Capacity {
                    measured
                } else {
                    self.Capacity + (measured - self.Capacity) * 0.12
                };
            }
            self.ComputeSeconds = 0.;
            self.SampleTicks = 0;
            self.Sample = Instant::now();
        }
    }
}
fn worker(receiver: Receiver<Request>) {
    let mut runtime: Option<Runtime> = None;
    let mut nextId = 0u32;
    loop {
        let wait = runtime.as_ref().map_or(Duration::from_secs(3600), |r| {
            if r.Running && r.Rate == 0. {
                Duration::ZERO
            } else {
                Duration::from_millis(1)
            }
        });
        match receiver.recv_timeout(wait) {
            Ok(request) => {
                let result = match request.Action {
                    Action::Compile(input, origin) => {
                        nextId = nextId.wrapping_add(1).max(1);
                        match SimulationCore::compile(input) {
                            Ok(mut core) => {
                                let capacity = core.probeCapacity();
                                let now = Instant::now();
                                let mut r = Runtime {
                                    Core: core,
                                    Origin: origin,
                                    Id: nextId,
                                    Sequence: 0,
                                    Running: false,
                                    Rate: 1.,
                                    Pending: None,
                                    Timeline: VecDeque::new(),
                                    Bytes: 0,
                                    Tps: 0.,
                                    Capacity: capacity,
                                    ComputeSeconds: 0.,
                                    Sample: now,
                                    SampleTicks: 0,
                                    Accumulator: 0.,
                                    Last: now,
                                };
                                r.snapshot();
                                let frame = r.frame(true);
                                runtime = Some(r);
                                Ok(frame)
                            }
                            Err(mut e) => {
                                runtime = None;
                                if e.HasPosition {
                                    e.ErrorX += origin.0;
                                    e.ErrorY += origin.1;
                                }
                                Err(serde_json::to_string(&e).unwrap())
                            }
                        }
                    }
                    Action::Release => {
                        runtime = None;
                        Ok(vec![])
                    }
                    action => runtime
                        .as_mut()
                        .ok_or("SimulationNotCompiled".into())
                        .and_then(|r| r.handle(action)),
                };
                let _ = request.Reply.send(result);
            }
            Err(RecvTimeoutError::Disconnected) => break,
            Err(RecvTimeoutError::Timeout) => {}
        }
        if let Some(r) = runtime.as_mut() {
            r.advance();
        }
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    fn input() -> CompileInput {
        CompileInput {
            Width: 5,
            Height: 1,
            Kinds: vec![26, 15, 1, 16, 17],
            InitialStates: vec![0; 5],
            ClockHoldTicks: vec![1; 5],
            MeshIds: vec![1; 5],
        }
    }
    fn u32At(frame: &[u8], offset: usize) -> u32 {
        u32::from_le_bytes(frame[offset..offset + 4].try_into().unwrap())
    }
    #[test]
    fn sessionFramesAndTimeline() {
        let session = Session::default();
        let first = session.request(Action::Compile(input(), (-2, 0))).unwrap();
        let id = u32At(&first, 8);
        let sequence = u32At(&first, 12);
        assert_eq!(session.request(Action::Poll(id, 0)).unwrap(), first);
        let second = session.request(Action::Poll(id, sequence)).unwrap();
        assert_eq!(u32At(&second, 12), sequence + 1);
        let step = session.request(Action::Step(id, 2)).unwrap();
        assert_eq!(u32At(&step, 16), 2);
        let back = session.request(Action::Seek(id, 0)).unwrap();
        assert_eq!(u32At(&back, 16), 0);
        let stepAgain = session.request(Action::Step(id, 2)).unwrap();
        assert_eq!(&stepAgain[80..], &step[80..]);
        let replaced = session.request(Action::Compile(input(), (0, 0))).unwrap();
        assert_ne!(id, u32At(&replaced, 8));
        assert!(session.request(Action::Poll(id, 0)).is_err());
    }
    #[test]
    fn fullSpeedResponsiveAndShutdown() {
        let session = Session::default();
        let first = session.request(Action::Compile(input(), (0, 0))).unwrap();
        let id = u32At(&first, 8);
        session.request(Action::Run(id, 0.)).unwrap();
        thread::sleep(Duration::from_millis(30));
        let start = Instant::now();
        let pause = session.request(Action::Pause(id)).unwrap();
        assert!(start.elapsed() < Duration::from_secs(1));
        assert!(u32At(&pause, 16) > 0);
        assert_eq!(u32At(&pause, 44), 0);
    }
    #[test]
    fn compileErrorsUseBoardCoordinates() {
        let session = Session::default();
        let mut invalid = input();
        invalid.Kinds = vec![15, 0, 0, 0, 0];
        let error = session
            .request(Action::Compile(invalid, (-9, 4)))
            .unwrap_err();
        let detail: serde_json::Value = serde_json::from_str(&error).unwrap();
        assert_eq!(detail["errorX"], -9);
        assert_eq!(detail["errorY"], 4);
        assert_eq!(detail["hasPosition"], true);
        assert!(session.request(Action::Compile(input(), (0, 0))).is_ok());
    }
}
