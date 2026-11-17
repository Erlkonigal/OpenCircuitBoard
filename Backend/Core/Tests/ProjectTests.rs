#![allow(non_snake_case)]
use ocb_core::{
    CompileInput,
    Project::{self, Blueprint, Board, Grid, ProjectDocument, Tile},
    SimulationCore,
};
fn tile(x: i32, y: i32, kind: &str, id: i32) -> Tile {
    Tile {
        X: x,
        Y: y,
        ToolId: kind.into(),
        ComponentId: id,
        ..Default::default()
    }
}
fn button(x: i32, y: i32, id: i32, on: bool, direction: i32) -> Tile {
    let mut tile = tile(x, y, "latch", id);
    tile.IsOn = on;
    tile.Direction = direction;
    tile
}
fn board(tiles: Vec<Tile>) -> Board {
    Board {
        Grid: Grid {
            OriginX: -20,
            OriginY: -20,
            Width: 40,
            Height: 40,
        },
        Tiles: tiles,
        ..Default::default()
    }
}
fn compile(board: &Board) -> (SimulationCore, (i32, i32)) {
    let (input, origin) = board.compileInput().unwrap();
    (SimulationCore::compile(input).unwrap(), origin)
}
fn state(core: &mut SimulationCore, origin: (i32, i32), x: i32, y: i32) -> u8 {
    let cell = (y - origin.1) as usize * core.Width + (x - origin.0) as usize;
    core.states()[cell]
}
#[test]
fn stableToolsAndRejectedArchives() {
    for (id, kind) in [
        ("trace", 1),
        ("bus", 7),
        ("cross", 13),
        ("buffer", 17),
        ("latch", 25),
        ("led", 27),
        ("traceOrange", 28),
        ("traceWhite", 29),
        ("switch", 30),
    ] {
        assert_eq!(Project::toolKind(id), Some(kind));
    }
    for id in ["read", "write", "empty", "busRed"] {
        assert!(Project::toolKind(id).is_none());
    }
    let mut b = Board::default();
    b.CircuitModel = String::new();
    assert!(b.validate().is_err());
    let file = std::env::temp_dir().join(format!("OcbOld-{}.ocb", std::process::id()));
    let mut writer = zip::ZipWriter::new(std::fs::File::create(&file).unwrap());
    writer
        .start_file("project.json", zip::write::SimpleFileOptions::default())
        .unwrap();
    use std::io::Write;
    writer
        .write_all(br#"{"formatVersion":2,"board":{"tiles":[]}}"#)
        .unwrap();
    writer.finish().unwrap();
    assert!(Project::load(&file).is_err());
    std::fs::remove_file(file).unwrap();
}
#[test]
fn tracesDefaultLowAndButtonsDriveConstants() {
    let (mut core, origin) = compile(&board(vec![tile(0, 0, "trace", 1)]));
    assert_eq!(state(&mut core, origin, 0, 0), 0);

    let (mut core, origin) = compile(&board(vec![
        button(-1, 0, 2, false, 0),
        tile(0, 0, "trace", 1),
    ]));
    assert_eq!(state(&mut core, origin, 0, 0), 0);
    core.toggleLatch((0 - origin.1) as usize * core.Width + (-1 - origin.0) as usize)
        .unwrap();
    assert_eq!(state(&mut core, origin, 0, 0), 1);
}
#[test]
fn busSourcesOrIndependentlyWithoutPortInks() {
    let mut tiles = vec![
        tile(-2, 0, "latch", 1),
        tile(-1, 0, "traceRed", 2),
        tile(0, 0, "bus", 3),
        tile(0, 1, "bus", 3),
        tile(0, 2, "bus", 3),
        tile(1, 2, "traceRed", 4),
        tile(2, 2, "latch", 5),
        tile(1, 0, "traceGreen", 6),
    ];
    tiles[6].Direction = 2;
    tiles.push(button(2, 0, 7, true, 2));
    let b = board(tiles);
    let (mut core, o) = compile(&b);
    assert_eq!(
        core.inspect((0 - o.1) as usize * core.Width + (0 - o.0) as usize)[2],
        1
    );
    core.toggleLatch((0 - o.1) as usize * core.Width + (-2 - o.0) as usize)
        .unwrap();
    assert_eq!(state(&mut core, o, 1, 2), 1);
    core.toggleLatch((2 - o.1) as usize * core.Width + (2 - o.0) as usize)
        .unwrap();
    core.toggleLatch((0 - o.1) as usize * core.Width + (-2 - o.0) as usize)
        .unwrap();
    assert_eq!(state(&mut core, o, 1, 2), 1);
    core.toggleLatch((2 - o.1) as usize * core.Width + (2 - o.0) as usize)
        .unwrap();
    assert_eq!(state(&mut core, o, 1, 2), 0);
}
#[test]
fn crossJoinsOnlySelectedColors() {
    for mask in [0, 1] {
        let source = button(-2, 0, 6, true, 0);
        let mut cross = tile(0, 0, "cross", 2);
        cross.CrossMask = mask;
        let (mut core, o) = compile(&board(vec![
            source,
            tile(-1, 0, "trace", 1),
            cross,
            tile(0, 1, "trace", 3),
            tile(1, 0, "trace", 4),
            tile(0, -1, "traceRed", 5),
        ]));
        assert_eq!(state(&mut core, o, 1, 0), 1);
        assert_eq!(state(&mut core, o, 0, 1), if mask == 0 { 0 } else { 1 });
        assert_eq!(state(&mut core, o, 0, -1), 0);
    }
}
#[test]
fn switchDelayBidirectionalityAndSnapshots() {
    let b = board(vec![
        button(-2, 0, 1, false, 0),
        tile(-1, 0, "trace", 2),
        tile(0, 0, "switch", 3),
        tile(1, 0, "traceRed", 4),
        tile(0, 1, "traceBlue", 5),
        button(0, 2, 6, false, 3),
    ]);
    let (mut core, o) = compile(&b);
    assert_eq!(state(&mut core, o, 1, 0), 0);
    let left = (0 - o.1) as usize * core.Width + (-2 - o.0) as usize;
    let control = (0 - o.1) as usize * core.Width + (0 - o.0) as usize + core.Width * 2;
    core.toggleLatch(left).unwrap();
    assert_eq!(state(&mut core, o, 1, 0), 0);
    core.toggleLatch(control).unwrap();
    assert_eq!(state(&mut core, o, 1, 0), 0);
    let pending = core.capture();
    core.advanceSilent(1);
    assert_eq!(state(&mut core, o, 1, 0), 1);
    core.toggleLatch(control).unwrap();
    core.advanceSilent(1);
    assert_eq!(state(&mut core, o, 1, 0), 0);
    core.restore(&pending).unwrap();
    core.advanceSilent(1);
    assert_eq!(state(&mut core, o, 1, 0), 1);

    let b = board(vec![
        tile(-1, 0, "trace", 1),
        tile(0, 0, "switch", 2),
        tile(1, 0, "traceRed", 3),
        button(2, 0, 4, true, 2),
        tile(0, 1, "traceBlue", 5),
        button(0, 2, 6, false, 3),
    ]);
    let (mut core, o) = compile(&b);
    assert_eq!(state(&mut core, o, -1, 0), 0);
    let control = (0 - o.1) as usize * core.Width + (0 - o.0) as usize + core.Width * 2;
    core.toggleLatch(control).unwrap();
    core.advanceSilent(1);
    assert_eq!(state(&mut core, o, -1, 0), 1);
}
#[test]
fn directionAndGateTruthTables() {
    for kind in ["and", "or", "xor", "nand", "nor", "xnor"] {
        for a in [false, true] {
            for b in [false, true] {
                let left = tile(-1, 0, "trace", 1);
                let leftButton = button(-2, 0, 5, a, 0);
                let top = tile(0, -1, "traceRed", 2);
                let topButton = button(0, -2, 6, b, 1);
                let (mut core, o) = compile(&board(vec![
                    left,
                    leftButton,
                    top,
                    topButton,
                    tile(0, 0, kind, 3),
                    tile(1, 0, "traceBlue", 4),
                ]));
                core.advanceSilent(1);
                let expected = match kind {
                    "and" => a && b,
                    "or" => a || b,
                    "xor" => a ^ b,
                    "nand" => !(a && b),
                    "nor" => !(a || b),
                    _ => !(a ^ b),
                };
                assert_eq!(state(&mut core, o, 1, 0), expected as u8, "{kind} {a} {b}");
            }
        }
    }
    let source = tile(0, -1, "trace", 1);
    let mut gate = tile(0, 0, "buffer", 2);
    gate.Direction = 1;
    let (mut core, o) = compile(&board(vec![
        source,
        button(0, -2, 5, true, 1),
        gate,
        tile(0, 1, "trace", 3),
        tile(1, 0, "trace", 4),
    ]));
    core.advanceSilent(1);
    assert_eq!(state(&mut core, o, 0, 1), 1);
    assert_eq!(state(&mut core, o, 1, 0), 0);
}
#[test]
fn archivesAndBlueprintsPreserveSettingsAndRejectMalformedComponents() {
    let t = tile(0, 0, "traceWhite", 1);
    let mut switch = tile(1, 0, "switch", 2);
    switch.Direction = 3;
    let project = ProjectDocument {
        Board: board(vec![t.clone(), switch.clone()]),
        Blueprints: vec![Blueprint {
            Id: "s".into(),
            Name: "Switch".into(),
            Width: 2,
            Height: 1,
            Tiles: vec![t, switch],
        }],
    };
    let file = std::env::temp_dir().join(format!("OcbSwitch-{}.ocb", std::process::id()));
    Project::save(&file, &project).unwrap();
    assert_eq!(Project::load(&file).unwrap(), project);
    std::fs::remove_file(file).unwrap();
    for bad in 0..4 {
        let mut project = project.clone();
        match bad {
            0 => project.Board.Tiles[0].Direction = 4,
            1 => project.Board.Tiles[1].CrossMask = 1,
            2 => {
                let mut extra = project.Board.Tiles[0].clone();
                extra.X = 3;
                project.Board.Tiles.push(extra);
            }
            _ => project.Board.Tiles[0].ToolId = "missing".into(),
        }
        assert!(project.validate().is_err());
    }
}
#[test]
fn archivesRejectUnknownTileFields() {
    use std::io::Write;
    let cases = [
        (
            "board",
            "ProjectBoardInvalid",
            r#"{"formatVersion":2,"board":{"circuitModel":"booleanSwitch","tiles":[{"x":0,"y":0,"toolId":"trace","componentId":1,"unexpected":false}]}}"#,
        ),
        (
            "blueprint",
            "ProjectBlueprintInvalid",
            r#"{"formatVersion":2,"board":{"circuitModel":"booleanSwitch","tiles":[]},"blueprints":[{"id":"unknown","name":"Unknown","width":1,"height":1,"tiles":[{"x":0,"y":0,"toolId":"trace","componentId":1,"isOn":true,"unexpected":false}]}]}"#,
        ),
    ];
    for (name, error, json) in cases {
        let file =
            std::env::temp_dir().join(format!("OcbUnknownTile-{name}-{}.ocb", std::process::id()));
        let mut writer = zip::ZipWriter::new(std::fs::File::create(&file).unwrap());
        writer
            .start_file("project.json", zip::write::SimpleFileOptions::default())
            .unwrap();
        writer.write_all(json.as_bytes()).unwrap();
        writer.finish().unwrap();
        assert_eq!(Project::load(&file).unwrap_err(), error);
        std::fs::remove_file(file).unwrap();
    }
}

#[test]
fn malformedCompileInputsAreRejected() {
    let mut input = CompileInput::empty(1, 1);
    input.Kinds[0] = 15;
    input.ComponentIds[0] = 1;
    assert_eq!(
        SimulationCore::compile(input).err().unwrap().ErrorReason,
        "unknown_kind"
    );
    let mut input = CompileInput::empty(1, 1);
    input.Directions.clear();
    assert_eq!(
        SimulationCore::compile(input).err().unwrap().ErrorReason,
        "array_size_mismatch"
    );

    for (fixedDrive, defaultValue) in [(0, 0), (-1, 1)] {
        let mut input = CompileInput::empty(1, 1);
        input.Kinds[0] = 1;
        input.ComponentIds[0] = 1;
        input.FixedDrives[0] = fixedDrive;
        input.DefaultValues[0] = defaultValue;
        assert_eq!(
            SimulationCore::compile(input).err().unwrap().ErrorReason,
            "invalid_component_settings"
        );
    }
}
#[test]
fn switchCyclesReleaseWithdrawnDriversAndFanOutWithoutAddedDelay() {
    let mut tiles = vec![button(-3, 0, 1, true, 0)];
    for y in 0..5 {
        tiles.push(tile(-2, y, "trace", 2));
    }
    for (index, y) in [0, 2, 4].into_iter().enumerate() {
        let destination = 30 + index as i32;
        let control = 10 + index as i32;
        tiles.push(tile(-1, y, "trace", 2));
        tiles.push(tile(0, y, "switch", 20 + index as i32));
        tiles.push(tile(1, y, "traceRed", destination));
        tiles.push(tile(2, y, "traceRed", destination));
        tiles.push(tile(0, y + 1, "traceGreen", control));
        tiles.push(button(1, y + 1, 40 + index as i32, true, 2));
    }
    let (mut core, origin) = compile(&board(tiles));
    core.advanceSilent(1);
    let source = (-origin.1) as usize * core.Width + (-3 - origin.0) as usize;
    for y in [0, 2, 4] {
        assert_eq!(state(&mut core, origin, 2, y), 1);
    }
    let connected = core.capture();
    core.toggleLatch(source).unwrap();
    for y in [0, 2, 4] {
        assert_eq!(
            state(&mut core, origin, 2, y),
            0,
            "A switch cycle must not retain a removed high"
        );
    }
    core.restore(&connected).unwrap();
    for y in [0, 2, 4] {
        assert_eq!(state(&mut core, origin, 2, y), 1);
    }
    core.toggleLatch(source).unwrap();
    for y in [0, 2, 4] {
        assert_eq!(state(&mut core, origin, 2, y), 0);
    }
}

#[test]
fn retiredToolsAndInvalidSavesNeverReplaceValidArchives() {
    let path = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join(format!(
        "../../build/BooleanArchive-{}.ocb",
        std::process::id()
    ));
    let mut project = ProjectDocument {
        Board: board(vec![tile(0, 0, "latch", 1)]),
        Blueprints: vec![],
    };
    Project::save(&path, &project).unwrap();
    for id in ["read", "write", "busRed", "module", "empty"] {
        let mut invalid = project.clone();
        invalid.Board.Tiles[0].ToolId = id.into();
        assert!(invalid.validate().is_err());
        assert!(invalid.Board.compileInput().is_err());
        assert!(Project::save(&path, &invalid).is_err());
        assert_eq!(Project::load(&path).unwrap(), project);
    }
    project.Board.Tiles[0].IsOn = true;
    Project::save(&path, &project).unwrap();
    assert_eq!(Project::load(&path).unwrap(), project);
    std::fs::remove_file(path).unwrap();
}

#[test]
fn compileCropsSparseBoardsAndRejectsOversizedOccupiedBounds() {
    let mut b = board(vec![tile(-3, 2, "clock", 1), tile(-2, 2, "traceOrange", 2)]);
    b.ClockHoldTicks = 7;
    let (input, origin) = b.compileInput().unwrap();
    assert_eq!(origin, (-3, 2));
    assert_eq!((input.Width, input.Height), (2, 1));
    assert_eq!(input.Kinds, [26, 28]);
    assert_eq!(input.ClockHoldTicks, [7, 7]);
    b.Grid.Width = i32::MAX;
    b.Grid.OriginX = 0;
    assert!(b.validate().is_err());
    b.Grid = Grid {
        OriginX: 0,
        OriginY: 0,
        Width: 2048,
        Height: 2048,
    };
    b.Tiles[0].X = 0;
    b.Tiles[0].Y = 0;
    b.Tiles[1].X = 2047;
    b.Tiles[1].Y = 2047;
    assert_eq!(b.compileInput().unwrap_err(), "SimulationGridTooLarge");
}

#[test]
fn latchOnlyDrivesItsRotatedOutputAndRetainsManualState() {
    let neighbors = [(1, 0), (0, 1), (-1, 0), (0, -1)];
    let colors = ["trace", "traceRed", "traceGreen", "traceBlue"];
    for direction in 0..4 {
        for initial in [false, true] {
            let mut latch = tile(0, 0, "latch", 1);
            latch.Direction = direction as i32;
            latch.IsOn = initial;
            let mut tiles = vec![latch];
            for (side, &(dx, dy)) in neighbors.iter().enumerate() {
                tiles.push(tile(dx, dy, colors[side], 10 + side as i32));
                if side != direction {
                    let mut clock = tile(dx * 2, dy * 2, "clock", 20 + side as i32);
                    clock.Direction = ((side + 2) % 4) as i32;
                    clock.ClockHoldTicks = Some(1 + side as i32);
                    tiles.push(clock);
                }
            }
            let (mut core, origin) = compile(&board(tiles));
            let output = neighbors[direction];
            for _ in 0..12 {
                core.advanceSilent(1);
                assert_eq!(state(&mut core, origin, 0, 0), initial as u8);
                assert_eq!(state(&mut core, origin, output.0, output.1), initial as u8);
            }
            let latchCell = (-origin.1) as usize * core.Width + (-origin.0) as usize;
            core.toggleLatch(latchCell).unwrap();
            assert_eq!(
                state(&mut core, origin, output.0, output.1),
                (!initial) as u8
            );
            let snapshot = core.capture();
            core.advanceSilent(7);
            assert_eq!(
                state(&mut core, origin, output.0, output.1),
                (!initial) as u8
            );
            core.toggleLatch(latchCell).unwrap();
            core.restore(&snapshot).unwrap();
            core.advanceSilent(5);
            assert_eq!(
                state(&mut core, origin, output.0, output.1),
                (!initial) as u8
            );
            core.resetSilent();
            assert_eq!(state(&mut core, origin, output.0, output.1), initial as u8);
            let (mut other, _) = compile(&board(vec![tile(0, 0, "trace", 1)]));
            assert_eq!(
                other.restore(&snapshot).unwrap_err(),
                "snapshot_topology_mismatch"
            );
        }
    }
}
