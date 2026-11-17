#![allow(non_snake_case, non_upper_case_globals)]
#[path = "../Examples/HelloWorld5x8.rs"]
mod HelloWorld5x8;
use ocb_core::{Project, SimulationCore};
use std::path::PathBuf;

fn examplePath() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../Frontend/Assets/Examples/HelloWorld5x8.ocb")
}
fn pixels(core: &mut SimulationCore, origin: (i32, i32)) -> Vec<u8> {
    let width = core.Width;
    let states = core.states();
    (0..8)
        .flat_map(|row| (0..5).map(move |column| (column, row)))
        .map(|(column, row)| {
            let x =
                HelloWorld5x8::DisplayOrigin.0 + 1 + column * HelloWorld5x8::PixelPitch - origin.0;
            let y = HelloWorld5x8::DisplayOrigin.1 + row * HelloWorld5x8::PixelPitch - origin.1;
            states[y as usize * width + x as usize]
        })
        .collect()
}
#[test]
fn committedExampleMatchesGeneratorAndPlaysThreeCompleteLoops() {
    let project = Project::load(&examplePath()).expect("Load committed example");
    assert!(
        project == HelloWorld5x8::buildProject(),
        "Regenerate the committed archive with make examples"
    );
    HelloWorld5x8::verify(&project);
    let leds: std::collections::HashSet<_> = project
        .Board
        .Tiles
        .iter()
        .filter(|tile| tile.ToolId == "led")
        .map(|tile| tile.ComponentId)
        .collect();
    assert_eq!(leds.len(), 40);
    assert!(project.Board.Tiles.len() < 27_315);
    assert!(project.Board.Tiles.iter().any(|t| t.ToolId == "switch"));
    let clocks: Vec<_> = project
        .Board
        .Tiles
        .iter()
        .filter(|tile| tile.ToolId == "clock")
        .collect();
    assert_eq!(clocks.len(), 1);
    assert_eq!(clocks[0].ClockHoldTicks, Some(4));
    assert!(
        !project
            .Board
            .Tiles
            .iter()
            .any(|tile| matches!(tile.ToolId.as_str(), "xor" | "xnor"))
    );
    assert!(
        !project
            .Board
            .Tiles
            .iter()
            .any(|t| matches!(t.ToolId.as_str(), "read" | "write"))
    );
    assert!(project.Board.Tiles.iter().any(|tile| tile.ToolId == "bus"));
    for tool in [
        "trace",
        "traceRed",
        "traceGreen",
        "traceBlue",
        "traceCyan",
        "traceMagenta",
        "traceOrange",
        "traceWhite",
    ] {
        assert!(project.Board.Tiles.iter().any(|tile| tile.ToolId == tool));
    }
}
#[test]
fn recognizableFramesSurviveResetSnapshotAndArchiveRoundTrip() {
    let project = Project::load(&examplePath()).unwrap();
    let (input, origin) = project.Board.compileInput().unwrap();
    let mut core = SimulationCore::compile(input).unwrap();
    let h = "1000110001100011111110001100011000100000";
    let w = "1000110001100011010110101110111000100000";
    let comma = "0000000000000000000000000001100010001000";
    let exclamation = "0010000100001000010000100000000010000000";
    for (index, expected) in [
        (0, h),
        (5, comma),
        (6, "0000000000000000000000000000000000000000"),
        (7, w),
        (12, exclamation),
        (13, h),
    ] {
        core.resetSilent();
        core.advanceSilent((HelloWorld5x8::StartupTicks + index * 8) as i32);
        assert_eq!(
            pixels(&mut core, origin),
            expected
                .bytes()
                .map(|value| value - b'0')
                .collect::<Vec<_>>(),
            "Character slot {index}"
        );
    }
    let snapshot = core.capture();
    let before = pixels(&mut core, origin);
    core.advanceSilent(19);
    core.restore(&snapshot).unwrap();
    assert_eq!(pixels(&mut core, origin), before);
    core.advanceSilent(8);
    let next = pixels(&mut core, origin);
    core.restore(&snapshot).unwrap();
    core.advanceSilent(8);
    assert_eq!(pixels(&mut core, origin), next);
    core.resetSilent();
    assert_eq!(pixels(&mut core, origin), vec![0; 40]);
    let path = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join(format!(
        "../../build/HelloWorld5x8RoundTrip-{}.ocb",
        std::process::id()
    ));
    Project::save(&path, &project).unwrap();
    assert_eq!(Project::load(&path).unwrap(), project);
    std::fs::remove_file(path).unwrap();
}

#[path = "../Examples/Ram16x8.rs"]
mod Ram16x8;
#[test]
fn ramArchiveMatchesGeneratorAndSurvivesAllAddressPatterns() {
    let path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../Frontend/Assets/Examples/Ram16x8.ocb");
    let project = Project::load(&path).unwrap();
    assert_eq!(project, Ram16x8::buildProject());
    Ram16x8::verify(&project);
}

fn footprint<'a>(tiles: impl Iterator<Item = &'a Project::Tile>) -> (i64, i64) {
    let tiles: Vec<_> = tiles.collect();
    let width = tiles.iter().map(|tile| tile.X).max().unwrap() as i64
        - tiles.iter().map(|tile| tile.X).min().unwrap() as i64
        + 1;
    let height = tiles.iter().map(|tile| tile.Y).max().unwrap() as i64
        - tiles.iter().map(|tile| tile.Y).min().unwrap() as i64
        + 1;
    (width, height)
}

#[test]
fn compactMemoryReducesActualFootprintsRatherThanOnlyCanvasMargins() {
    let hello = Project::load(&examplePath()).unwrap();
    let (width, height) = footprint(hello.Board.Tiles.iter());
    assert!(
        width * height <= 567 * 234 * 3 / 5,
        "Hello World actual footprint {width}x{height}"
    );
    assert!(width < 567 && height <= 234);
    assert!(
        i64::from(hello.Board.Grid.Width) * i64::from(hello.Board.Grid.Height) <= 575 * 242 * 3 / 5
    );
    let (width, height) = footprint(
        hello
            .Board
            .Tiles
            .iter()
            .filter(|tile| tile.Y < HelloWorld5x8::DecoderTop),
    );
    assert!(
        width * height <= 561 * 43 / 2,
        "Register actual footprint {width}x{height}"
    );
    assert!(hello.Board.Tiles.len() < 24_313);
    let ram = Project::load(
        &PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../../Frontend/Assets/Examples/Ram16x8.ocb"),
    )
    .unwrap();
    let (width, height) = footprint(ram.Board.Tiles.iter());
    assert!(
        width * height <= 376 * 475 / 4,
        "RAM actual footprint {width}x{height}"
    );
    assert!(width < 376 && height < 475);
    assert!(i64::from(ram.Board.Grid.Width) * i64::from(ram.Board.Grid.Height) <= 384 * 483 / 4);
    assert!(ram.Board.Tiles.len() < 98_916 / 2);
}

fn writeRam(
    core: &mut SimulationCore,
    project: &Project::ProjectDocument,
    origin: (i32, i32),
    address: u8,
    value: u8,
) {
    Ram16x8::address(core, project, origin, address);
    Ram16x8::data(core, project, origin, value);
    Ram16x8::set(core, project, origin, Ram16x8::Drive, true);
    core.advanceSilent(Ram16x8::SettleTicks);
    Ram16x8::set(core, project, origin, Ram16x8::We, true);
    core.advanceSilent(Ram16x8::SettleTicks);
    Ram16x8::set(core, project, origin, Ram16x8::We, false);
    core.advanceSilent(Ram16x8::SettleTicks);
    Ram16x8::set(core, project, origin, Ram16x8::Drive, false);
    core.advanceSilent(Ram16x8::SettleTicks);
}
fn readRam(
    core: &mut SimulationCore,
    project: &Project::ProjectDocument,
    origin: (i32, i32),
    address: u8,
) -> u8 {
    Ram16x8::address(core, project, origin, address);
    core.advanceSilent(Ram16x8::SettleTicks);
    Ram16x8::set(core, project, origin, Ram16x8::Oe, true);
    core.advanceSilent(Ram16x8::SettleTicks);
    let value = Ram16x8::read(core, project, origin);
    Ram16x8::set(core, project, origin, Ram16x8::Oe, false);
    core.advanceSilent(Ram16x8::SettleTicks);
    assert_eq!(
        Ram16x8::read(core, project, origin),
        0,
        "Disabled output must release shared bit lines"
    );
    value
}
#[test]
fn compactRamIsolatesWalkingBitsAndRowsAndResetMasksWrites() {
    let project = Ram16x8::buildProject();
    let (input, origin) = project.Board.compileInput().unwrap();
    let mut core = SimulationCore::compile(input).unwrap();
    core.advanceSilent(Ram16x8::SettleTicks);
    Ram16x8::set(&mut core, &project, origin, Ram16x8::Reset, false);
    core.advanceSilent(Ram16x8::SettleTicks);
    let mut expected = [0u8; 16];
    for address in 0..16 {
        expected[address] = if address < 8 {
            1 << address
        } else {
            !(1 << (address - 8))
        };
        writeRam(
            &mut core,
            &project,
            origin,
            address as u8,
            expected[address],
        );
    }
    // Overwriting adjacent rows must preserve every other row and bit.
    for (address, value) in [(7, 0x96), (8, 0x69)] {
        expected[address] = value;
        writeRam(&mut core, &project, origin, address as u8, value);
    }
    Ram16x8::data(&mut core, &project, origin, 0xff);
    core.advanceSilent(128);
    for address in 0..16 {
        assert_eq!(
            readRam(&mut core, &project, origin, address as u8),
            expected[address],
            "Walking bits at address {address}"
        );
    }
    Ram16x8::set(&mut core, &project, origin, Ram16x8::Reset, true);
    core.advanceSilent(Ram16x8::SettleTicks);
    Ram16x8::set(&mut core, &project, origin, Ram16x8::Drive, true);
    Ram16x8::set(&mut core, &project, origin, Ram16x8::We, true);
    core.advanceSilent(32);
    Ram16x8::set(&mut core, &project, origin, Ram16x8::We, false);
    Ram16x8::set(&mut core, &project, origin, Ram16x8::Drive, false);
    core.advanceSilent(Ram16x8::SettleTicks);
    Ram16x8::set(&mut core, &project, origin, Ram16x8::Reset, false);
    core.advanceSilent(Ram16x8::SettleTicks);
    for address in 0..16 {
        assert_eq!(
            readRam(&mut core, &project, origin, address),
            0,
            "Reset must clear address {address} and mask writes"
        );
    }
}
