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
            ComponentId: 1,
            IsOn: true,
            ClockHoldTicks: Some(4),
        },
        Tile {
            X: 0,
            Y: 0,
            ToolId: "latch".into(),
            ComponentId: 2,
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
        &serde_json::json!({"formatVersion":2,"board":{"selectedTool":"or","clockHoldTicks":4,"tiles":[{"x":0,"y":0,"toolId":"clock","componentId":1}]}}),
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
        ComponentId: 3,
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
            ComponentId: 4,
            IsOn: false,
            ClockHoldTicks: None,
        },
        Tile {
            X: 1,
            Y: 2,
            ToolId: "clock".into(),
            ComponentId: 5,
            IsOn: true,
            ClockHoldTicks: Some(5),
        },
    ];
    let (input, origin) = board.compileInput().unwrap();
    assert_eq!(origin, (-3, 2));
    assert_eq!(input.Width, 5);
    assert_eq!(input.Kinds, vec![25, 0, 0, 0, 26]);
    assert_eq!(input.ClockHoldTicks[4], 5);
    assert_eq!(
        input.ComponentIds,
        vec![
            board.Tiles[0].ComponentId,
            0,
            0,
            0,
            board.Tiles[1].ComponentId
        ]
    );
}

#[test]
fn missingTileStatesInheritLegacyDefaults() {
    let file = path("legacy-latch");
    archive(
        &file,
        &serde_json::json!({"formatVersion":2,"board":{"latchInitialState":false,"tiles":[{"x":0,"y":0,"toolId":"latch","componentId":1},{"x":1,"y":0,"toolId":"latch","componentId":1}]}}),
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
        Tiles: vec![
            Tile {
                X: 0,
                Y: 0,
                ToolId: "clock".into(),
                ComponentId: 6,
                IsOn: false,
                ClockHoldTicks: Some(9),
            },
            Tile {
                X: 2,
                Y: 1,
                ToolId: "latch".into(),
                ComponentId: 7,
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
fn unknownModulesFailUniformlyInBoardsAndBlueprints() {
    let file = path("unknown");
    for kind in ["mesh", "undefined"] {
        archive(
            &file,
            &serde_json::json!({"formatVersion":2,"board":{"tiles":[{"x":0,"y":0,"toolId":kind,"componentId":1}]}}),
        );
        assert_eq!(load(&file).unwrap_err(), "ProjectBoardInvalid");
        archive(
            &file,
            &serde_json::json!({"formatVersion":2,"board":{},"blueprints":[{"id":"x","name":"Bad","width":1,"height":1,"tiles":[{"x":0,"y":0,"toolId":kind,"componentId":1,"isOn":false}]}]}),
        );
        assert_eq!(load(&file).unwrap_err(), "ProjectBlueprintInvalid");
    }
    fs::remove_file(file).unwrap();
}

#[test]
fn componentIdsRoundTripAndInvalidGroupsAreOrdinaryErrors() {
    let file = path("components");
    let valid = serde_json::json!({"formatVersion":2,"board":{"tiles":[
        {"x":0,"y":0,"toolId":"latch","componentId":7,"isOn":false},
        {"x":1,"y":0,"toolId":"latch","componentId":7,"isOn":false},
        {"x":0,"y":1,"toolId":"latch","componentId":8,"isOn":false}]}});
    archive(&file, &valid);
    let project = load(&file).unwrap();
    save(&file, &project).unwrap();
    assert_eq!(load(&file).unwrap(), project);
    for invalid in 0..5 {
        let mut bad = valid.clone();
        match invalid {
            0 => {
                bad["board"]["tiles"][0]
                    .as_object_mut()
                    .unwrap()
                    .remove("componentId");
            }
            1 => bad["board"]["tiles"][0]["componentId"] = serde_json::json!(0),
            2 => bad["board"]["tiles"][1]["x"] = serde_json::json!(3),
            3 => bad["board"]["tiles"][1]["isOn"] = serde_json::json!(true),
            _ => bad["board"]["tiles"][1]["toolId"] = serde_json::json!("clock"),
        }
        archive(&file, &bad);
        assert_eq!(load(&file).unwrap_err(), "ProjectBoardInvalid");
    }
    for id in [serde_json::Value::Null, serde_json::json!(0)] {
        archive(
            &file,
            &serde_json::json!({"formatVersion":2,"board":{},"blueprints":[{"id":"x","name":"Bad","width":1,"height":1,"tiles":[{"x":0,"y":0,"toolId":"latch","componentId":id}]}]}),
        );
        assert_eq!(load(&file).unwrap_err(), "ProjectBlueprintInvalid");
    }
    fs::remove_file(file).unwrap();
}

#[test]
fn eightTraceKindsRoundTripWithoutRenumberingExistingTools() {
    for (tool, kind) in [
        ("trace", 1),
        ("bus", 7),
        ("busRed", 8),
        ("cross", 13),
        ("read", 15),
        ("led", 27),
        ("traceOrange", 28),
        ("traceWhite", 29),
    ] {
        assert_eq!(toolKind(tool), Some(kind));
    }
    let file = path("eight-traces");
    let mut project = ProjectDocument::default();
    project.Board.Tiles = [
        "trace",
        "traceRed",
        "traceGreen",
        "traceBlue",
        "traceCyan",
        "traceMagenta",
        "traceOrange",
        "traceWhite",
    ]
    .iter()
    .enumerate()
    .map(|(index, tool)| Tile {
        X: index as i32,
        Y: 0,
        ToolId: (*tool).into(),
        ComponentId: index as i32 + 1,
        IsOn: false,
        ClockHoldTicks: None,
    })
    .collect();
    save(&file, &project).unwrap();
    let loaded = load(&file).unwrap();
    assert_eq!(loaded, project);
    assert_eq!(
        loaded.Board.compileInput().unwrap().0.Kinds,
        vec![1, 2, 3, 4, 5, 6, 28, 29]
    );
    fs::remove_file(file).unwrap();
}
#[test]
fn legacyBusColorsNormalizeInBoardsAndBlueprintsWhileKeepingIdentities() {
    let file = path("bus-aliases");
    let aliases = [
        "bus",
        "busRed",
        "busGreen",
        "busYellow",
        "busCyan",
        "busMagenta",
    ];
    let tiles: Vec<_> = aliases
        .iter()
        .enumerate()
        .map(|(index, tool)| {
            serde_json::json!({
                "x":index,"y":0,"toolId":tool,"componentId":index+1,"isOn":false
            })
        })
        .collect();
    archive(
        &file,
        &serde_json::json!({"formatVersion":2,
        "board":{"selectedTool":"busRed","tiles":tiles},
        "blueprints":[{"id":"b","name":"Bus","width":6,"height":1,"tiles":tiles}]}),
    );
    let project = load(&file).unwrap();
    assert_eq!(project.Board.SelectedTool, "bus");
    for group in [&project.Board.Tiles, &project.Blueprints[0].Tiles] {
        for (index, tile) in group.iter().enumerate() {
            assert_eq!(tile.ToolId, "bus");
            assert_eq!(tile.ComponentId, index as i32 + 1);
        }
    }
    let mut aliasProject = project.clone();
    aliasProject.Board.SelectedTool = "busGreen".into();
    aliasProject.Board.Tiles[0].ToolId = "busMagenta".into();
    aliasProject.Blueprints[0].Tiles[0].ToolId = "busYellow".into();
    save(&file, &aliasProject).unwrap();
    assert_eq!(load(&file).unwrap(), project);
    let mut zip = zip::ZipArchive::new(fs::File::open(&file).unwrap()).unwrap();
    let mut json = String::new();
    std::io::Read::read_to_string(&mut zip.by_name("project.json").unwrap(), &mut json).unwrap();
    let value: serde_json::Value = serde_json::from_str(&json).unwrap();
    assert_eq!(value["formatVersion"], 2);
    assert!(
        value["board"]["tiles"]
            .as_array()
            .unwrap()
            .iter()
            .all(|tile| tile["toolId"] == "bus")
    );
    drop(zip);
    fs::remove_file(file).unwrap();
}
