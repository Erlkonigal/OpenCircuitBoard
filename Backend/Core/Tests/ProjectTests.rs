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
fn fixedZeroOverridesDefaultsAndSeparateIdsStayIsolated() {
    let mut source = tile(0, 0, "trace", 1);
    source.FixedDrive = Some(false);
    source.DefaultValue = true;
    let mut neighbor = tile(1, 0, "trace", 2);
    neighbor.DefaultValue = true;
    let (mut core, origin) = compile(&board(vec![source.clone(), neighbor.clone()]));
    assert_eq!(state(&mut core, origin, 0, 0), 0);
    assert_eq!(state(&mut core, origin, 1, 0), 1);
    neighbor.ComponentId = 1;
    neighbor.FixedDrive = Some(false);
    let (mut core, origin) = compile(&board(vec![source, neighbor]));
    assert_eq!(state(&mut core, origin, 1, 0), 0);
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
    tiles[7].FixedDrive = Some(true);
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
        let mut source = tile(-1, 0, "trace", 1);
        source.FixedDrive = Some(true);
        let mut cross = tile(0, 0, "cross", 2);
        cross.CrossMask = mask;
        let (mut core, o) = compile(&board(vec![
            source,
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
fn switchDelayBidirectionalityDefaultsAndSnapshots() {
    let mut left = tile(-1, 0, "trace", 1);
    left.FixedDrive = Some(false);
    let mut right = tile(1, 0, "traceRed", 3);
    right.DefaultValue = true;
    let mut control = tile(0, 2, "latch", 5);
    control.Direction = 3;
    let b = board(vec![
        left,
        tile(0, 0, "switch", 2),
        right,
        tile(0, 1, "traceBlue", 4),
        control,
    ]);
    let (mut core, o) = compile(&b);
    assert_eq!(state(&mut core, o, 1, 0), 1);
    let controlCell = (2 - o.1) as usize * core.Width + (0 - o.0) as usize;
    core.toggleLatch(controlCell).unwrap();
    assert_eq!(state(&mut core, o, 1, 0), 1);
    let pending = core.capture();
    core.advanceSilent(1);
    assert_eq!(state(&mut core, o, 1, 0), 0);
    core.toggleLatch(controlCell).unwrap();
    core.advanceSilent(1);
    assert_eq!(state(&mut core, o, 1, 0), 1);
    core.restore(&pending).unwrap();
    core.advanceSilent(1);
    assert_eq!(state(&mut core, o, 1, 0), 0);
    // Drive from the right: a closed switch must carry the original source back to the left.
    let mut b = b;
    b.Tiles[0].FixedDrive = None;
    b.Tiles[0].DefaultValue = false;
    b.Tiles[2].FixedDrive = Some(true);
    let (mut core, o) = compile(&b);
    core.toggleLatch((2 - o.1) as usize * core.Width + (0 - o.0) as usize)
        .unwrap();
    core.advanceSilent(1);
    assert_eq!(state(&mut core, o, -1, 0), 1);
    core.toggleLatch((2 - o.1) as usize * core.Width + (0 - o.0) as usize)
        .unwrap();
    core.advanceSilent(1);
    assert_eq!(state(&mut core, o, -1, 0), 0);
}
#[test]
fn directionAndGateTruthTables() {
    for kind in ["and", "or", "xor", "nand", "nor", "xnor"] {
        for a in [false, true] {
            for b in [false, true] {
                let mut left = tile(-1, 0, "trace", 1);
                left.FixedDrive = Some(a);
                let mut top = tile(0, -1, "traceRed", 2);
                top.FixedDrive = Some(b);
                let (mut core, o) = compile(&board(vec![
                    left,
                    top,
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
    let mut source = tile(0, -1, "trace", 1);
    source.FixedDrive = Some(true);
    let mut gate = tile(0, 0, "buffer", 2);
    gate.Direction = 1;
    let (mut core, o) = compile(&board(vec![
        source,
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
    let mut t = tile(0, 0, "traceWhite", 1);
    t.FixedDrive = Some(false);
    t.DefaultValue = true;
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
            1 => project.Board.Tiles[1].FixedDrive = Some(true),
            2 => project.Board.Tiles[1].CrossMask = 1,
            _ => {
                let mut extra = project.Board.Tiles[0].clone();
                extra.X = 3;
                project.Board.Tiles.push(extra);
            }
        }
        assert!(project.validate().is_err());
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
}
#[test]
fn switchCyclesReleaseWithdrawnDriversAndFanOutWithoutAddedDelay() {
    let mut tiles = vec![tile(-3, 0, "latch", 1), tile(-2, 0, "trace", 2)];
    for y in 0..5 {
        tiles.push(tile(-1, y, "trace", 2));
        tiles.push(tile(1, y, "traceRed", 3));
    }
    for (index, y) in [0, 2, 4].into_iter().enumerate() {
        tiles.push(tile(0, y, "switch", 4 + index as i32 * 2));
        let mut control = tile(0, y + 1, "traceGreen", 5 + index as i32 * 2);
        control.FixedDrive = Some(true);
        tiles.push(control);
    }
    let (mut core, origin) = compile(&board(tiles.clone()));
    core.advanceSilent(1);
    let source = (-origin.1) as usize * core.Width + (-3 - origin.0) as usize;
    core.toggleLatch(source).unwrap();
    assert_eq!(state(&mut core, origin, 1, 4), 1);
    let connected = core.capture();
    core.toggleLatch(source).unwrap();
    assert_eq!(
        state(&mut core, origin, 1, 4),
        0,
        "A switch cycle must not retain a removed high"
    );
    core.restore(&connected).unwrap();
    core.toggleLatch(source).unwrap();
    assert_eq!(state(&mut core, origin, 1, 4), 0);
    // Split the far side into three independent destinations supplied by one source.
    tiles.retain(|t| !(t.X == 1 && t.Y % 2 == 1));
    for t in tiles.iter_mut().filter(|t| t.X == 1) {
        t.ComponentId = 20 + t.Y;
    }
    let (mut core, origin) = compile(&board(tiles));
    core.advanceSilent(1);
    let source = (-origin.1) as usize * core.Width + (-3 - origin.0) as usize;
    core.toggleLatch(source).unwrap();
    for y in [0, 2, 4] {
        assert_eq!(state(&mut core, origin, 1, y), 1);
    }
    core.toggleLatch(source).unwrap();
    for y in [0, 2, 4] {
        assert_eq!(state(&mut core, origin, 1, y), 0);
    }
}

#[test]
fn defaultsFollowConnectivityWithoutBecomingDrivers() {
    let mut left = tile(-1, 0, "trace", 1);
    left.DefaultValue = true;
    let mut control = tile(0, 1, "traceGreen", 4);
    control.FixedDrive = Some(true);
    let mut tiles = vec![
        left,
        tile(0, 0, "switch", 2),
        tile(1, 0, "traceRed", 3),
        control,
    ];
    let (mut core, origin) = compile(&board(tiles.clone()));
    assert_eq!(state(&mut core, origin, 1, 0), 0);
    core.advanceSilent(1);
    assert_eq!(state(&mut core, origin, 1, 0), 1);
    tiles.push(tile(2, 0, "latch", 5));
    tiles.last_mut().unwrap().Direction = 2;
    let (mut core, origin) = compile(&board(tiles));
    core.advanceSilent(1);
    assert_eq!(
        state(&mut core, origin, -1, 0),
        0,
        "A connected active zero suppresses defaults everywhere"
    );
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
