#![allow(non_snake_case)]
use ocb_core::Project::*;
use std::{fs, io::Write, path::PathBuf};
use zip::{ZipWriter, write::SimpleFileOptions};
fn path(name: &str) -> PathBuf {
    std::env::temp_dir().join(format!("OcbProjectTest-{}-{name}.ocb", std::process::id()))
}
fn archive(path: &std::path::Path, value: &serde_json::Value) {
    let mut zip = ZipWriter::new(fs::File::create(path).unwrap());
    zip.start_file("project.json", SimpleFileOptions::default())
        .unwrap();
    zip.write_all(serde_json::to_string(value).unwrap().as_bytes())
        .unwrap();
    zip.finish().unwrap();
}
#[test]
fn roundTripAndAtomicOverwrite() {
    let file = path("roundtrip");
    let mut board = Board::default();
    board.Tiles = vec![
        Tile {
            X: -2,
            Y: 1,
            ToolId: "clock".into(),
            IsOn: true,
            ClockHoldTicks: Some(4),
        },
        Tile {
            X: 0,
            Y: 0,
            ToolId: "latch".into(),
            IsOn: false,
            ClockHoldTicks: None,
        },
    ];
    save(
        &file,
        &ProjectDocument {
            Board: board.clone(),
            Blueprints: vec![],
        },
    )
    .unwrap();
    board.Tiles.sort_by_key(|t| (t.Y, t.X));
    assert_eq!(load(&file).unwrap().Board, board);
    board.LatchInitialState = false;
    save(
        &file,
        &ProjectDocument {
            Board: board.clone(),
            Blueprints: vec![],
        },
    )
    .unwrap();
    assert_eq!(load(&file).unwrap().Board, board);
    fs::remove_file(file).unwrap();
}
#[test]
fn versionAndLegacyDefaults() {
    let file = path("legacy");
    archive(
        &file,
        &serde_json::json!({"formatVersion":2,"board":{"selectedTool":"or","clockHoldTicks":4,"tiles":[{"x":0,"y":0,"toolId":"clock"}]}}),
    );
    let board = load(&file).unwrap().Board;
    assert_eq!(board.Grid, Grid::default());
    assert_eq!(board.Tiles[0].ClockHoldTicks, Some(4));
    archive(&file, &serde_json::json!({"formatVersion":1,"board":{}}));
    assert_eq!(load(&file).unwrap_err(), "ProjectVersionUnsupported");
    fs::remove_file(file).unwrap();
}
#[test]
fn invalidBoardDoesNotReplaceExistingFile() {
    let file = path("invalid");
    let mut board = Board::default();
    save(
        &file,
        &ProjectDocument {
            Board: board.clone(),
            Blueprints: vec![],
        },
    )
    .unwrap();
    let before = fs::read(&file).unwrap();
    board.Tiles = vec![Tile {
        X: 100,
        Y: 0,
        ToolId: "or".into(),
        IsOn: true,
        ClockHoldTicks: None,
    }];
    assert!(
        save(
            &file,
            &ProjectDocument {
                Board: board.clone(),
                Blueprints: vec![]
            }
        )
        .is_err()
    );
    assert_eq!(fs::read(&file).unwrap(), before);
    fs::remove_file(file).unwrap();
}
#[test]
fn malformedZipAndMissingEntry() {
    let file = path("malformed");
    fs::write(&file, "bad zip").unwrap();
    assert_eq!(load(&file).unwrap_err(), "ProjectOpenFailed");
    let writer = ZipWriter::new(fs::File::create(&file).unwrap());
    writer.finish().unwrap();
    assert_eq!(load(&file).unwrap_err(), "ProjectEntryMissing");
    fs::remove_file(file).unwrap();
}
#[test]
fn inputCropsToOccupiedBoundsAndKeepsKindIds() {
    let mut board = Board::default();
    board.Tiles = vec![
        Tile {
            X: -3,
            Y: 2,
            ToolId: "latch".into(),
            IsOn: false,
            ClockHoldTicks: None,
        },
        Tile {
            X: 1,
            Y: 2,
            ToolId: "clock".into(),
            IsOn: true,
            ClockHoldTicks: Some(5),
        },
    ];
    let (input, origin) = board.compileInput().unwrap();
    assert_eq!(origin, (-3, 2));
    assert_eq!(input.Width, 5);
    assert_eq!(input.Kinds, vec![25, 0, 0, 0, 26]);
    assert_eq!(input.ClockHoldTicks[4], 5);
}

#[test]
fn missingTileStatesInheritLegacyDefaults() {
    let file = path("legacy-latch");
    archive(
        &file,
        &serde_json::json!({"formatVersion":2,"board":{"latchInitialState":false,"tiles":[{"x":0,"y":0,"toolId":"latch"},{"x":1,"y":0,"toolId":"latch"}]}}),
    );
    let board = load(&file).unwrap().Board;
    assert!(!board.Tiles[0].IsOn);
    assert!(!board.Tiles[1].IsOn);
    fs::remove_file(file).unwrap();
}

#[test]
fn blueprintsRoundTripAndRejectInvalidSnapshots() {
    let file = path("blueprints");
    let mut project = ProjectDocument::default();
    project.Blueprints.push(Blueprint {
        Id: "clock-pair".into(),
        Name: "Clock pair".into(),
        Width: 3,
        Height: 2,
        IsolationEdges: vec![],
        Tiles: vec![
            Tile {
                X: 0,
                Y: 0,
                ToolId: "clock".into(),
                IsOn: false,
                ClockHoldTicks: Some(9),
            },
            Tile {
                X: 2,
                Y: 1,
                ToolId: "latch".into(),
                IsOn: false,
                ClockHoldTicks: None,
            },
        ],
    });
    save(&file, &project).unwrap();
    assert_eq!(load(&file).unwrap(), project);
    let original = fs::read(&file).unwrap();
    for invalid in 0..5 {
        let mut bad = project.clone();
        match invalid {
            0 => bad.Blueprints[0].Tiles[0].ClockHoldTicks = None,
            1 => bad.Blueprints[0].Tiles[0].X = -1,
            2 => bad.Blueprints[0].Name = " ".into(),
            3 => bad.Blueprints.push(bad.Blueprints[0].clone()),
            _ => {
                let tile = bad.Blueprints[0].Tiles[0].clone();
                bad.Blueprints[0].Tiles.push(tile);
            }
        }
        assert_eq!(save(&file, &bad).unwrap_err(), "ProjectBlueprintInvalid");
        assert_eq!(fs::read(&file).unwrap(), original);
    }
    archive(
        &file,
        &serde_json::json!({"formatVersion":2,"board":{},"blueprints":[{"id":"x","name":"Invalid","width":1,"height":1,"tiles":[]}]}),
    );
    assert_eq!(load(&file).unwrap_err(), "ProjectBlueprintInvalid");
    fs::remove_file(file).unwrap();
}

#[test]
fn isolationRoundTripsIncludingEmptySpaceAndBlueprintPerimeters() {
    let file = path("isolation");
    let mut project = ProjectDocument::default();
    let edge = IsolationEdge {
        X: -2,
        Y: 1,
        Axis: EdgeAxis::Vertical,
    };
    project.Board.IsolationEdges = vec![edge.clone(), edge.clone()];
    project.Blueprints.push(Blueprint {
        Id: "divider".into(),
        Name: "Divider".into(),
        Width: 1,
        Height: 2,
        Tiles: vec![],
        IsolationEdges: vec![IsolationEdge {
            X: 1,
            Y: 1,
            Axis: EdgeAxis::Vertical,
        }],
    });
    save(&file, &project).unwrap();
    project.Board.IsolationEdges.pop();
    assert_eq!(load(&file).unwrap(), project);
    project.Board.IsolationEdges.push(IsolationEdge {
        X: 20,
        Y: 14,
        Axis: EdgeAxis::Horizontal,
    });
    assert_eq!(save(&file, &project).unwrap_err(), "ProjectBoardInvalid");
    fs::remove_file(file).unwrap();
}
#[test]
fn isolationCompilesToCroppedCanonicalMasks() {
    let mut board = Board::default();
    board.Tiles = vec![
        Tile {
            X: -2,
            Y: -1,
            ToolId: "latch".into(),
            IsOn: false,
            ClockHoldTicks: None,
        },
        Tile {
            X: -1,
            Y: 0,
            ToolId: "latch".into(),
            IsOn: false,
            ClockHoldTicks: None,
        },
    ];
    board.IsolationEdges = vec![
        IsolationEdge {
            X: -1,
            Y: -1,
            Axis: EdgeAxis::Vertical,
        },
        IsolationEdge {
            X: -2,
            Y: 0,
            Axis: EdgeAxis::Horizontal,
        },
        IsolationEdge {
            X: 5,
            Y: 5,
            Axis: EdgeAxis::Vertical,
        },
    ];
    let (data, origin) = board.compileInput().unwrap();
    assert_eq!(origin, (-2, -1));
    assert_eq!(data.IsolationMasks, vec![3, 0, 0, 0]);
    assert_eq!(toolKind("read"), Some(15));
    assert_eq!(toolKind("latch"), Some(25));
}
#[test]
fn unknownModulesFailUniformlyInBoardsAndBlueprints() {
    let file = path("unknown");
    for kind in ["mesh", "undefined"] {
        archive(
            &file,
            &serde_json::json!({"formatVersion":2,"board":{"tiles":[{"x":0,"y":0,"toolId":kind}]}}),
        );
        assert_eq!(load(&file).unwrap_err(), "ProjectBoardInvalid");
        archive(
            &file,
            &serde_json::json!({"formatVersion":2,"board":{},"blueprints":[{"id":"x","name":"Bad","width":1,"height":1,"tiles":[{"x":0,"y":0,"toolId":kind,"isOn":false}]}]}),
        );
        assert_eq!(load(&file).unwrap_err(), "ProjectBlueprintInvalid");
    }
    fs::remove_file(file).unwrap();
}
