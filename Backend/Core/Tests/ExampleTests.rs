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
            let x = HelloWorld5x8::DisplayOrigin.0 + column * HelloWorld5x8::PixelPitch - origin.0;
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
        core.advanceSilent((4 + index * 8) as i32);
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
