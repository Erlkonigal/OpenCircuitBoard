#![allow(non_snake_case)]
use ocb_core::{CompileInput, SimulationCore};
use std::{env, time::Instant};
fn main() {
    let args: Vec<_> = env::args().collect();
    let quick = args.iter().any(|s| s == "--quick");
    let unary = args
        .windows(2)
        .any(|s| s[0] == "--workload" && s[1] == "unary-buffer");
    let value = |flag: &str, default: usize| {
        args.windows(2)
            .find(|v| v[0] == flag)
            .map(|v| v[1].parse().expect("integer argument"))
            .unwrap_or(default)
    };
    let width = value("--width", if quick { 256 } else { 1024 });
    let height = value("--height", if quick { 256 } else { 1024 });
    let lanes = value("--pipelines", if quick { 64 } else { 256 });
    let warmup = value("--warmup", if quick { 256 } else { 512 });
    let ticks = value("--ticks", if quick { 4096 } else { 1024 });
    let samples = value("--samples", 5);
    let minimum = value("--minimum-tps", 0) as f64;
    if width < 8 || height < lanes * if unary { 2 } else { 4 } || samples == 0 {
        eprintln!("Invalid benchmark dimensions");
        std::process::exit(2);
    }
    let mut input = CompileInput::empty(width, height);
    let mut nextId = 1;
    for lane in 0..lanes {
        let y = lane * if unary { 2 } else { 4 };
        for x in 0..width {
            let cell = y * width + x;
            input.Kinds[cell] = if x == 0 {
                26
            } else if x % 2 == 1 {
                1
            } else {
                17
            };
            input.ComponentIds[cell] = nextId;
            input.ClockHoldTicks[cell] = 2 + (lane % 3) as i32;
            nextId += 1;
        }
    }
    let start = Instant::now();
    let mut core = SimulationCore::compile(input).unwrap();
    let compile = start.elapsed().as_secs_f64();
    let mut rates = vec![];
    let mut drains = vec![];
    let mut checksum = 0;
    for _ in 0..samples {
        core.resetSilent();
        core.advanceSilent(warmup as i32);
        core.drain();
        let start = Instant::now();
        core.advanceSilent(ticks as i32);
        let beforeDrain = Instant::now();
        std::hint::black_box(core.drain());
        let duration = start.elapsed().as_secs_f64();
        drains.push(beforeDrain.elapsed().as_secs_f64() * 1000.);
        rates.push(ticks as f64 / duration);
        checksum = core.states().iter().fold(1469598103934665603u64, |h, &s| {
            (h ^ (s as u64 + 1)).wrapping_mul(1099511628211)
        });
    }
    rates.sort_by(f64::total_cmp);
    drains.sort_by(f64::total_cmp);
    let median = rates[samples / 2];
    println!(
        "Rust SimulationCore: {width}x{height}, lanes={lanes}, median={median:.2} TPS, compile={compile:.3}s, drain={:.2}ms, checksum={checksum}, target100K={}",
        drains[samples / 2],
        median >= 100000.
    );
    if median < minimum {
        std::process::exit(1);
    }
}
