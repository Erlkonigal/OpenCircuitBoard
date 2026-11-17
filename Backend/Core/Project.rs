use crate::{CompileInput, Simulation::MaximumCellCount};
use serde::{Deserialize, Serialize};
use std::{
    fs::{self, File},
    io::{Read, Write},
    path::{Path, PathBuf},
};
use zip::{ZipArchive, ZipWriter, write::SimpleFileOptions};
fn one() -> i32 {
    1
}
fn zero(value: &i32) -> bool {
    *value == 0
}
fn no(value: &bool) -> bool {
    !*value
}
fn noMask(value: &u8) -> bool {
    *value == 0
}
fn yes() -> bool {
    true
}
fn defaultTool() -> String {
    "or".into()
}
pub fn toolKind(id: &str) -> Option<i32> {
    Some(match id {
        "trace" => 1,
        "traceRed" => 2,
        "traceGreen" => 3,
        "traceBlue" => 4,
        "traceCyan" => 5,
        "traceMagenta" => 6,
        "bus" => 7,
        "cross" => 13,
        "buffer" => 17,
        "and" => 18,
        "or" => 19,
        "xor" => 20,
        "not" => 21,
        "nand" => 22,
        "nor" => 23,
        "xnor" => 24,
        "latch" => 25,
        "clock" => 26,
        "led" => 27,
        "traceOrange" => 28,
        "traceWhite" => 29,
        "switch" => 30,
        _ => return None,
    })
}
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Grid {
    pub OriginX: i32,
    pub OriginY: i32,
    pub Width: i32,
    pub Height: i32,
}
impl Default for Grid {
    fn default() -> Self {
        Self {
            OriginX: -20,
            OriginY: -14,
            Width: 40,
            Height: 28,
        }
    }
}
#[derive(Clone, Debug, Default, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Tile {
    pub X: i32,
    pub Y: i32,
    pub ToolId: String,
    pub ComponentId: i32,
    #[serde(default = "yes")]
    pub IsOn: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub ClockHoldTicks: Option<i32>,
    #[serde(default, skip_serializing_if = "zero")]
    pub Direction: i32,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub FixedDrive: Option<bool>,
    #[serde(default, skip_serializing_if = "no")]
    pub DefaultValue: bool,
    #[serde(default, skip_serializing_if = "noMask")]
    pub CrossMask: u8,
}
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Board {
    pub CircuitModel: String,
    #[serde(default = "defaultTool")]
    pub SelectedTool: String,
    #[serde(default = "one")]
    pub ClockHoldTicks: i32,
    #[serde(default = "yes")]
    pub LatchInitialState: bool,
    #[serde(default)]
    pub Grid: Grid,
    #[serde(default)]
    pub Tiles: Vec<Tile>,
}
impl Default for Board {
    fn default() -> Self {
        Self {
            CircuitModel: "booleanSwitch".into(),
            SelectedTool: defaultTool(),
            ClockHoldTicks: 1,
            LatchInitialState: true,
            Grid: Grid::default(),
            Tiles: vec![],
        }
    }
}
#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct Archive {
    FormatVersion: u32,
    #[serde(flatten)]
    Project: ProjectDocument,
}
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Blueprint {
    pub Id: String,
    pub Name: String,
    pub Width: i32,
    pub Height: i32,
    pub Tiles: Vec<Tile>,
}
#[derive(Clone, Debug, Default, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ProjectDocument {
    pub Board: Board,
    #[serde(default)]
    pub Blueprints: Vec<Blueprint>,
}
impl ProjectDocument {
    pub fn validate(&self) -> Result<(), String> {
        self.Board.validate()?;
        let mut ids = std::collections::HashSet::new();
        for blueprint in &self.Blueprints {
            let mut cells = std::collections::HashSet::new();
            if blueprint.Id.trim().is_empty()
                || !ids.insert(&blueprint.Id)
                || blueprint.Name.trim().is_empty()
                || blueprint.Width < 1
                || blueprint.Height < 1
                || blueprint.Tiles.is_empty()
            {
                return Err("ProjectBlueprintInvalid".into());
            }
            for tile in &blueprint.Tiles {
                if tile.X < 0
                    || tile.Y < 0
                    || tile.X >= blueprint.Width
                    || tile.Y >= blueprint.Height
                    || !cells.insert((tile.X, tile.Y))
                    || toolKind(&tile.ToolId).is_none()
                    || (tile.ToolId == "clock" && tile.ClockHoldTicks.is_none_or(|v| v < 1))
                {
                    return Err("ProjectBlueprintInvalid".into());
                }
            }
            validateComponents(&blueprint.Tiles, 1, "ProjectBlueprintInvalid")?;
        }
        Ok(())
    }
}
impl Board {
    pub fn validate(&self) -> Result<(), String> {
        let g = &self.Grid;
        if self.CircuitModel != "booleanSwitch"
            || g.Width < 4
            || g.Height < 4
            || g.OriginX.checked_add(g.Width).is_none()
            || g.OriginY.checked_add(g.Height).is_none()
        {
            return Err("ProjectBoardInvalid".into());
        }
        if toolKind(&self.SelectedTool).is_none() || self.ClockHoldTicks < 1 {
            return Err("ProjectBoardInvalid".into());
        }
        let mut cells = std::collections::HashSet::new();
        for tile in &self.Tiles {
            if tile.X < g.OriginX
                || tile.Y < g.OriginY
                || tile.X >= g.OriginX + g.Width
                || tile.Y >= g.OriginY + g.Height
                || !cells.insert((tile.X, tile.Y))
                || toolKind(&tile.ToolId).is_none()
                || (tile.ToolId == "clock"
                    && tile.ClockHoldTicks.unwrap_or(self.ClockHoldTicks) < 1)
            {
                return Err("ProjectBoardInvalid".into());
            }
        }
        validateComponents(&self.Tiles, self.ClockHoldTicks, "ProjectBoardInvalid")
    }
    pub fn compileInput(&self) -> Result<(CompileInput, (i32, i32)), String> {
        self.validate()?;
        let minX = self
            .Tiles
            .iter()
            .map(|t| t.X)
            .min()
            .unwrap_or(self.Grid.OriginX);
        let minY = self
            .Tiles
            .iter()
            .map(|t| t.Y)
            .min()
            .unwrap_or(self.Grid.OriginY);
        let maxX = self.Tiles.iter().map(|t| t.X).max().unwrap_or(minX);
        let maxY = self.Tiles.iter().map(|t| t.Y).max().unwrap_or(minY);
        let width = (maxX as i64 - minX as i64 + 1) as usize;
        let height = (maxY as i64 - minY as i64 + 1) as usize;
        let _count = width
            .checked_mul(height)
            .filter(|&n| n <= MaximumCellCount)
            .ok_or("SimulationGridTooLarge")?;
        let mut input = CompileInput::empty(width, height);
        for t in &self.Tiles {
            let cell = (t.Y - minY) as usize * width + (t.X - minX) as usize;
            input.Kinds[cell] = toolKind(&t.ToolId).unwrap();
            input.ComponentIds[cell] = t.ComponentId;
            input.Directions[cell] = t.Direction;
            input.FixedDrives[cell] = t.FixedDrive.map_or(-1, |v| v as i32);
            input.DefaultValues[cell] = t.DefaultValue as i32;
            input.CrossMasks[cell] = t.CrossMask as i32;
            input.InitialStates[cell] = t.IsOn as i32;
            input.ClockHoldTicks[cell] = t.ClockHoldTicks.unwrap_or(self.ClockHoldTicks);
        }
        Ok((input, (minX, minY)))
    }
}
fn validateComponents(tiles: &[Tile], defaultHold: i32, error: &str) -> Result<(), String> {
    use std::collections::{HashMap, HashSet};
    let mut samples: HashMap<i32, &Tile> = HashMap::new();
    let mut cells = HashMap::with_capacity(tiles.len());
    for tile in tiles {
        if tile.ComponentId < 1
            || !(0..4).contains(&tile.Direction)
            || (!tile.ToolId.starts_with("trace")
                && (tile.FixedDrive.is_some() || tile.DefaultValue))
            || (tile.ToolId != "cross" && tile.CrossMask != 0)
        {
            return Err(error.into());
        }
        if let Some(first) = samples.get(&tile.ComponentId) {
            if first.ToolId != tile.ToolId
                || first.Direction != tile.Direction
                || first.FixedDrive != tile.FixedDrive
                || first.DefaultValue != tile.DefaultValue
                || first.CrossMask != tile.CrossMask
                || (tile.ToolId == "latch" && first.IsOn != tile.IsOn)
                || (tile.ToolId == "clock"
                    && first.ClockHoldTicks.unwrap_or(defaultHold)
                        != tile.ClockHoldTicks.unwrap_or(defaultHold))
            {
                return Err(error.into());
            }
        } else {
            samples.insert(tile.ComponentId, tile);
        }
        cells.insert((tile.X, tile.Y), tile);
    }
    let mut completed = HashSet::new();
    for seed in tiles {
        let point = (seed.X, seed.Y);
        if !cells.contains_key(&point) {
            continue;
        }
        if !completed.insert(seed.ComponentId) {
            return Err(error.into());
        }
        cells.remove(&point);
        let mut queue = vec![point];
        while let Some((x, y)) = queue.pop() {
            for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                let Some(nx) = x.checked_add(dx) else {
                    continue;
                };
                let Some(ny) = y.checked_add(dy) else {
                    continue;
                };
                if cells
                    .get(&(nx, ny))
                    .is_some_and(|t| t.ComponentId == seed.ComponentId)
                {
                    cells.remove(&(nx, ny));
                    queue.push((nx, ny));
                }
            }
        }
    }
    Ok(())
}
pub fn normalizePath(path: &Path) -> PathBuf {
    if path
        .extension()
        .is_some_and(|s| s.eq_ignore_ascii_case("ocb"))
    {
        path.to_owned()
    } else {
        PathBuf::from(format!("{}.ocb", path.display()))
    }
}
pub fn load(path: &Path) -> Result<ProjectDocument, String> {
    let file = File::open(path).map_err(|_| "ProjectFileMissing")?;
    let mut zip = ZipArchive::new(file).map_err(|_| "ProjectOpenFailed")?;
    let entry = zip
        .by_name("project.json")
        .map_err(|_| "ProjectEntryMissing")?;
    let mut text = String::new();
    entry
        .take(128 * 1024 * 1024 + 1)
        .read_to_string(&mut text)
        .map_err(|_| "ProjectFormatInvalid")?;
    if text.len() > 128 * 1024 * 1024 {
        return Err("ProjectFormatInvalid".into());
    }
    let value: serde_json::Value =
        serde_json::from_str(&text).map_err(|_| "ProjectFormatInvalid")?;
    if value.get("formatVersion").and_then(|v| v.as_u64()) != Some(2) {
        return Err("ProjectVersionUnsupported".into());
    }
    let source = value.get("board").ok_or("ProjectBoardInvalid")?;
    let board: Board = serde_json::from_value(source.clone()).map_err(|_| "ProjectBoardInvalid")?;
    let blueprints = match value.get("blueprints") {
        Some(value) => {
            serde_json::from_value(value.clone()).map_err(|_| "ProjectBlueprintInvalid")?
        }
        None => vec![],
    };
    let project = ProjectDocument {
        Board: board,
        Blueprints: blueprints,
    };
    project.validate()?;
    Ok(project)
}
pub fn save(path: &Path, project: &ProjectDocument) -> Result<PathBuf, String> {
    project.validate()?;
    let path = normalizePath(path);
    let parent = path.parent().unwrap_or(Path::new("."));
    let name = path
        .file_name()
        .ok_or("ProjectPathInvalid")?
        .to_string_lossy();
    let nonce = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_err(|_| "ProjectSaveOpenFailed")?
        .as_nanos();
    let temporary = parent.join(format!(".{name}.{}.{nonce}.tmp", std::process::id()));
    let write = (|| -> Result<(), String> {
        let file = File::options()
            .write(true)
            .create_new(true)
            .open(&temporary)
            .map_err(|_| "ProjectSaveOpenFailed")?;
        let mut zip = ZipWriter::new(file);
        zip.start_file(
            "project.json",
            SimpleFileOptions::default().compression_method(zip::CompressionMethod::Deflated),
        )
        .map_err(|_| "ProjectSaveWriteFailed")?;
        let mut canonical = project.clone();
        canonical.Board.Tiles.sort_by_key(|t| (t.Y, t.X));
        for blueprint in &mut canonical.Blueprints {
            blueprint.Tiles.sort_by_key(|t| (t.Y, t.X));
        }
        let text = serde_json::to_vec(&Archive {
            FormatVersion: 2,
            Project: canonical,
        })
        .map_err(|_| "ProjectFormatInvalid")?;
        if text.len() > 128 * 1024 * 1024 {
            return Err("ProjectFormatInvalid".into());
        }
        zip.write_all(&text).map_err(|_| "ProjectSaveWriteFailed")?;
        zip.finish()
            .map_err(|_| "ProjectSaveWriteFailed")?
            .sync_all()
            .map_err(|_| "ProjectSaveWriteFailed")?;
        fs::rename(&temporary, &path).map_err(|_| "ProjectSaveWriteFailed")?;
        Ok(())
    })();
    if write.is_err() {
        let _ = fs::remove_file(&temporary);
    }
    write?;
    Ok(path)
}
