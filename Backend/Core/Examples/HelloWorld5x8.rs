#![allow(non_snake_case, non_upper_case_globals)]
use ocb_core::Project::{self, Board, Grid, ProjectDocument, Tile};
use std::collections::{BTreeMap, HashSet, VecDeque};
use std::path::PathBuf;

type Point = (i32, i32);
pub const Message: &str = "Hello, World!";
pub const DisplayOrigin: Point = (-22, -37);
pub const PixelPitch: i32 = 10;
pub const PixelSize: i32 = 4;
pub const StartupTicks: usize = 4;
pub const CharacterTicks: usize = 8;

pub fn glyph(character: char) -> [&'static str; 8] {
    match character {
        'H' => [
            "#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#", ".....",
        ],
        'e' => [
            ".....", ".....", ".###.", "#...#", "#####", "#....", ".###.", ".....",
        ],
        'l' => [
            ".##..", "..#..", "..#..", "..#..", "..#..", "..#..", ".###.", ".....",
        ],
        'o' => [
            ".....", ".....", ".###.", "#...#", "#...#", "#...#", ".###.", ".....",
        ],
        ',' => [
            ".....", ".....", ".....", ".....", ".....", "..##.", "..#..", ".#...",
        ],
        ' ' => ["....."; 8],
        'W' => [
            "#...#", "#...#", "#...#", "#.#.#", "#.#.#", "##.##", "#...#", ".....",
        ],
        'r' => [
            ".....", ".....", "#.##.", "##..#", "#....", "#....", "#....", ".....",
        ],
        'd' => [
            "....#", "....#", ".##.#", "#..##", "#...#", "#...#", ".####", ".....",
        ],
        '!' => [
            "..#..", "..#..", "..#..", "..#..", "..#..", ".....", "..#..", ".....",
        ],
        _ => panic!("No 5x8 glyph for {character:?}"),
    }
}

struct Node {
    Kind: &'static str,
    Inputs: Vec<usize>,
}
#[derive(Clone, Copy, PartialEq)]
enum Wire {
    Trace(usize),
    Cross,
}
struct Layout {
    Tiles: BTreeMap<Point, Tile>,
    Wires: BTreeMap<Point, Wire>,
    NextId: i32,
}
impl Layout {
    fn new() -> Self {
        Self {
            Tiles: BTreeMap::new(),
            Wires: BTreeMap::new(),
            NextId: 1,
        }
    }
    fn device(&mut self, kind: &str, points: impl IntoIterator<Item = Point>, on: bool) {
        let id = self.NextId;
        self.NextId += 1;
        for (x, y) in points {
            assert!(
                !self.Tiles.contains_key(&(x, y)) && !self.Wires.contains_key(&(x, y)),
                "Device collision at {x},{y}"
            );
            self.Tiles.insert(
                (x, y),
                Tile {
                    X: x,
                    Y: y,
                    ToolId: kind.into(),
                    ComponentId: id,
                    IsOn: on,
                    ClockHoldTicks: None,
                },
            );
        }
    }
    fn wire(&mut self, point: Point, wire: Wire) {
        assert!(!self.Tiles.contains_key(&point));
        if let Some(previous) = self.Wires.insert(point, wire) {
            assert!(previous == wire, "Wire collision at {point:?}");
        }
    }
    fn finish(mut self) -> ProjectDocument {
        let mut remaining: HashSet<_> = self.Wires.keys().copied().collect();
        // Stable coordinate order makes regeneration reproducible. Every disconnected
        // trace segment and every four-connected Cross region gets a separate ID.
        for (&seed, &wire) in &self.Wires {
            if !remaining.remove(&seed) {
                continue;
            }
            let id = self.NextId;
            self.NextId += 1;
            let mut queue = VecDeque::from([seed]);
            while let Some((x, y)) = queue.pop_front() {
                let kind = if wire == Wire::Cross {
                    "cross"
                } else {
                    "trace"
                };
                self.Tiles.insert(
                    (x, y),
                    Tile {
                        X: x,
                        Y: y,
                        ToolId: kind.into(),
                        ComponentId: id,
                        IsOn: false,
                        ClockHoldTicks: None,
                    },
                );
                for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                    let neighbor = (x + dx, y + dy);
                    if self.Wires.get(&neighbor) == Some(&wire) && remaining.remove(&neighbor) {
                        queue.push_back(neighbor);
                    }
                }
            }
        }
        let minX = self.Tiles.keys().map(|p| p.0).min().unwrap() - 4;
        let minY = self.Tiles.keys().map(|p| p.1).min().unwrap() - 4;
        let maxX = self.Tiles.keys().map(|p| p.0).max().unwrap() + 5;
        let maxY = self.Tiles.keys().map(|p| p.1).max().unwrap() + 5;
        let mut project = ProjectDocument {
            Board: Board {
                SelectedTool: "led".into(),
                ClockHoldTicks: 1,
                LatchInitialState: true,
                Grid: Grid {
                    OriginX: minX,
                    OriginY: minY,
                    Width: maxX - minX,
                    Height: maxY - minY,
                },
                Tiles: self.Tiles.into_values().collect(),
            },
            Blueprints: vec![],
        };
        project.Board.Tiles.sort_by_key(|tile| (tile.Y, tile.X));
        project
            .validate()
            .expect("Generated example must be a valid v2 project");
        project
    }
}

pub fn buildProject() -> ProjectDocument {
    let mut nodes = vec![];
    // The two complementary half-cycles of the odd-inversion delay ring produce
    // the same thirteen-character sequence through XOR boundary detection.
    for index in 0..104 {
        nodes.push(Node {
            Kind: if index == 0 { "not" } else { "buffer" },
            Inputs: vec![if index == 0 { 103 } else { index - 1 }],
        });
    }
    let phases = nodes.len();
    for index in 0..13 {
        nodes.push(Node {
            Kind: if index == 12 { "xnor" } else { "xor" },
            Inputs: vec![index * 8, ((index + 1) % 13) * 8],
        });
    }
    let rom = nodes.len();
    for row in 0..8 {
        for column in 0..5 {
            nodes.push(Node {
                Kind: "or",
                Inputs: Message
                    .chars()
                    .enumerate()
                    .filter_map(|(index, character)| {
                        (glyph(character)[row].as_bytes()[column] == b'#').then_some(phases + index)
                    })
                    .collect(),
            });
        }
    }
    let enable = nodes.len();
    nodes.push(Node {
        Kind: "latch",
        Inputs: vec![],
    });
    nodes.push(Node {
        Kind: "buffer",
        Inputs: vec![enable],
    });
    nodes.push(Node {
        Kind: "buffer",
        Inputs: vec![enable + 1],
    });
    let outputs = nodes.len();
    for pixel in 0..40 {
        nodes.push(Node {
            Kind: "and",
            Inputs: vec![rom + pixel, enable + 2],
        });
    }

    let mut layout = Layout::new();
    let mut columns = vec![];
    let mut deviceColumns = vec![];
    for (index, node) in nodes.iter().enumerate() {
        let first = columns.len();
        columns.extend(node.Inputs.iter().copied());
        columns.push(index);
        deviceColumns.push((first, columns.len() - 1));
    }
    let right = -32;
    let left = right - (columns.len() as i32 - 1) * 2;
    let top = DisplayOrigin.1;
    let bottom = top + 80 + (outputs as i32 - 1);
    let rowNets: Vec<_> = (outputs..outputs + 40).chain(0..outputs).collect();
    let rowY = |row: usize| {
        top + if row < 40 {
            row as i32 / 5 * PixelPitch + PixelSize + row as i32 % 5
        } else {
            80 + row as i32 - 40
        }
    };
    // Each device has dedicated vertical input and output columns. Horizontal
    // signal rows meet their own columns through trace junctions; all other
    // intersections are directional Cross cells, preserving independent inputs.
    for (row, &net) in rowNets.iter().enumerate() {
        let y = rowY(row);
        let nextY = if row + 1 < rowNets.len() {
            rowY(row + 1)
        } else {
            y + 1
        };
        for (column, &verticalNet) in columns.iter().enumerate() {
            let x = left + column as i32 * 2;
            layout.wire(
                (x, y),
                if net == verticalNet {
                    Wire::Trace(net)
                } else {
                    Wire::Cross
                },
            );
            if x < right {
                layout.wire((x + 1, y), Wire::Trace(net));
            }
            for gapY in y + 1..nextY {
                layout.wire((x, gapY), Wire::Trace(verticalNet));
            }
        }
    }
    for (index, node) in nodes.iter().enumerate() {
        let (first, last) = deviceColumns[index];
        let startX = left + first as i32 * 2;
        let endX = left + last as i32 * 2;
        layout.device(
            node.Kind,
            (startX..=endX).map(|x| (x, bottom + 3)),
            node.Kind == "latch",
        );
        for column in first..=last {
            let x = left + column as i32 * 2;
            layout.wire((x, bottom + 1), Wire::Trace(columns[column]));
            layout.device(
                if column == last { "read" } else { "write" },
                [(x, bottom + 2)],
                false,
            );
        }
    }
    // Five nested leads below each pixel row avoid crossings near the display.
    for row in 0..8 {
        for column in 0..5 {
            let pixel = row * 5 + column;
            let net = outputs + pixel;
            let x = DisplayOrigin.0 + column as i32 * PixelPitch;
            let y = DisplayOrigin.1 + row as i32 * PixelPitch;
            layout.device(
                "led",
                (0..PixelSize).flat_map(|dy| (0..PixelSize).map(move |dx| (x + dx, y + dy))),
                false,
            );
            layout.device("write", [(x - 1, y)], false);
            let laneY = rowY(pixel);
            for sx in right + 1..=x - 2 {
                layout.wire((sx, laneY), Wire::Trace(net));
            }
            for sy in y..laneY {
                layout.wire((x - 2, sy), Wire::Trace(net));
            }
        }
    }
    layout.finish()
}

pub fn verify(project: &ProjectDocument) {
    let (input, (minX, minY)) = project.Board.compileInput().expect("Compile example input");
    let mut core = ocb_core::SimulationCore::compile(input).expect("Compile example circuit");
    let width = core.Width;
    for tick in 0..StartupTicks + Message.len() * CharacterTicks * 3 {
        let states = core.states();
        let expected = if tick < StartupTicks {
            glyph(' ')
        } else {
            glyph(
                Message.as_bytes()[((tick - StartupTicks) / CharacterTicks) % Message.len()]
                    as char,
            )
        };
        for (row, pattern) in expected.iter().enumerate() {
            for (column, value) in pattern.bytes().enumerate() {
                let x = DisplayOrigin.0 + column as i32 * PixelPitch;
                let y = DisplayOrigin.1 + row as i32 * PixelPitch;
                for dy in 0..PixelSize {
                    for dx in 0..PixelSize {
                        let actual =
                            states[(y + dy - minY) as usize * width + (x + dx - minX) as usize];
                        assert_eq!(
                            actual,
                            u8::from(value == b'#'),
                            "Tick {tick}, pixel {column},{row}"
                        );
                    }
                }
            }
        }
        core.advanceSilent(1);
    }
}

#[allow(dead_code)]
fn main() {
    let path = std::env::args_os()
        .nth(1)
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            PathBuf::from(env!("CARGO_MANIFEST_DIR"))
                .join("../../Frontend/Assets/Examples/HelloWorld5x8.ocb")
        });
    let project = buildProject();
    verify(&project);
    std::fs::create_dir_all(path.parent().unwrap()).expect("Create example directory");
    let saved = Project::save(&path, &project).expect("Save example archive");
    println!(
        "Generated {} ({} occupied cells); verified three complete loops. Run at 16 TPS for 0.5 seconds per character.",
        saved.display(),
        project.Board.Tiles.len()
    );
}
