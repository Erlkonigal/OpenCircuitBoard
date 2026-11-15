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
    let count = width * height;
    let mut input = CompileInput {
        Width: width,
        Height: height,
        Kinds: vec![0; count],
        InitialStates: vec![0; count],
        ClockHoldTicks: vec![1; count],
        MeshIds: vec![0; count],
    };
    for lane in 0..lanes {
        if unary {
            let y = lane * 2;
            input.Kinds[y * width] = 26;
            for stage in 0..(width - 1) / 4 {
                let x = 1 + stage * 4;
                for (d, k) in [15, 1, 16, 17].into_iter().enumerate() {
                    input.Kinds[y * width + x + d] = k;
                }
            }
            continue;
        }
        let y = lane * 4;
        let bottom = y + 2;
        input.Kinds[y * width] = 26;
        input.ClockHoldTicks[y * width] = 2 + (lane % 3) as i32;
        input.Kinds[y * width + 1] = 15;
        for x in 2..=width - 3 {
            input.Kinds[y * width + x] = 1;
        }
        input.Kinds[y * width + width - 2] = 15;
        input.Kinds[y * width + width - 1] = 26;
        input.ClockHoldTicks[y * width + width - 1] = 3 + ((lane / 3) % 4) as i32;
        input.Kinds[bottom * width] = 26;
        input.ClockHoldTicks[bottom * width] = 1 + (lane % 2) as i32;
        for stage in 0..(width - 4) / 4 {
            let x = 4 + stage * 4;
            let kind = [18, 22, 19, 23, 20, 24, 21, 17][stage % 8];
            for (d, k) in [15, 1, 16, kind].into_iter().enumerate() {
                input.Kinds[bottom * width + x - 3 + d] = k;
            }
            if kind != 21 && kind != 17 {
                input.Kinds[(y + 1) * width + x] = 16;
            }
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
