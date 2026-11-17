#![allow(non_snake_case)]
use ocb_core::{
    Project,
    Session::{Action, Session},
    SimulationCore,
};
use std::{env, path::Path, time::Instant};
fn run() -> Result<(), String> {
    let args: Vec<_> = env::args().collect();
    let file = args.get(1).ok_or(
        "Usage: ocb-board-benchmark Project.ocb [--ticks N] [--samples N] [--editorProbe]",
    )?;
    let value = |flag: &str, default: u32| -> Result<u32, String> {
        args.windows(2)
            .find(|v| v[0] == flag)
            .map(|v| v[1].parse().map_err(|_| format!("Invalid {flag}")))
            .unwrap_or(Ok(default))
    };
    let ticks = value("--ticks", 1024)?.clamp(1, i32::MAX as u32);
    let samples = value("--samples", 5)?.clamp(1, 100);
    let board = Project::load(Path::new(file))?.Board;
    let (input, origin) = board.compileInput()?;
    let start = Instant::now();
    let mut core = SimulationCore::compile(input.clone()).map_err(|e| e.ErrorReason)?;
    let compile = start.elapsed().as_secs_f64();
    let mut rates = vec![];
    let start = Instant::now();
    let snapshot = core.capture();
    let capture = start.elapsed().as_secs_f64();
    let start = Instant::now();
    core.restore(&snapshot)?;
    let restore = start.elapsed().as_secs_f64();
    for _ in 0..samples {
        core.restore(&snapshot)?;
        let start = Instant::now();
        core.advanceSilent(ticks as i32);
        core.drain();
        rates.push(ticks as f64 / start.elapsed().as_secs_f64());
    }
    rates.sort_by(f64::total_cmp);
    println!(
        "Board: {file}, {}x{}, {} occupied cells, origin={origin:?}",
        input.Width,
        input.Height,
        board.Tiles.len()
    );
    println!(
        "compile={compile:.6}s, snapshot={capture:.6}s/{} bytes, restore={restore:.6}s, median={:.2} TPS",
        snapshot.byteCount(),
        rates[rates.len() / 2],
    );
    if args.iter().any(|v| v == "--editorProbe") {
        let session = Session::default();
        let start = Instant::now();
        let frame = session.request(Action::Compile(input, origin))?;
        let capacity = f64::from_le_bytes(frame[72..80].try_into().unwrap());
        println!(
            "Editor compile/probe={:.6}s, sampled capacity={capacity:.2} TPS",
            start.elapsed().as_secs_f64()
        );
    }
    Ok(())
}
fn main() {
    if let Err(error) = run() {
        eprintln!("{error}");
        std::process::exit(1);
    }
}
