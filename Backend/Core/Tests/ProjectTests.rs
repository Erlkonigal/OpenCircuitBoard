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
            MeshId: None,
        },
        Tile {
            X: 0,
            Y: 0,
            ToolId: "mesh".into(),
            IsOn: false,
            ClockHoldTicks: None,
            MeshId: Some(17),
        },
    ];
    save(&file, &board).unwrap();
    board.Tiles.sort_by_key(|t| (t.Y, t.X));
    assert_eq!(load(&file).unwrap(), board);
    board.LatchInitialState = false;
    save(&file, &board).unwrap();
    assert_eq!(load(&file).unwrap(), board);
    fs::remove_file(file).unwrap();
}
#[test]
fn versionAndLegacyDefaults() {
    let file = path("legacy");
    archive(
        &file,
        &serde_json::json!({"formatVersion":2,"board":{"selectedTool":"or","clockHoldTicks":4,"meshId":7,"tiles":[{"x":0,"y":0,"toolId":"clock"}]}}),
    );
    let board = load(&file).unwrap();
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
    save(&file, &board).unwrap();
    let before = fs::read(&file).unwrap();
    board.Tiles = vec![Tile {
        X: 100,
        Y: 0,
        ToolId: "or".into(),
        IsOn: true,
        ClockHoldTicks: None,
        MeshId: None,
    }];
    assert!(save(&file, &board).is_err());
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
            MeshId: None,
        },
        Tile {
            X: 1,
            Y: 2,
            ToolId: "clock".into(),
            IsOn: true,
            ClockHoldTicks: Some(5),
            MeshId: None,
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
        &serde_json::json!({"formatVersion":2,"board":{"latchInitialState":false,"tiles":[{"x":0,"y":0,"toolId":"latch"},{"x":1,"y":0,"toolId":"mesh"}]}}),
    );
    let board = load(&file).unwrap();
    assert!(!board.Tiles[0].IsOn);
    assert!(!board.Tiles[1].IsOn);
    fs::remove_file(file).unwrap();
}
