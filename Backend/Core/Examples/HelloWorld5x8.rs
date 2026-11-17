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
    Bus(usize),
    Cross,
}
const InternalSignalCount: usize = 160;
const TraceTools: [&str; 8] = [
    "trace",
    "traceRed",
    "traceGreen",
    "traceBlue",
    "traceCyan",
    "traceMagenta",
    "traceOrange",
    "traceWhite",
];
fn signal(net: usize) -> (usize, usize) {
    if net < InternalSignalCount {
        (net / 8, net % 8)
    } else {
        let pixel = net - InternalSignalCount;
        (20 + pixel % 5, pixel / 5)
    }
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
        // trace/Bus segment and every four-connected Cross region gets a separate ID.
        for (&seed, &wire) in &self.Wires {
            if !remaining.remove(&seed) {
                continue;
            }
            let id = self.NextId;
            self.NextId += 1;
            let mut queue = VecDeque::from([seed]);
            while let Some((x, y)) = queue.pop_front() {
                let kind = match wire {
                    Wire::Cross => "cross",
                    Wire::Bus(_) => "bus",
                    Wire::Trace(net) => TraceTools[signal(net).1],
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

    assert_eq!(outputs, InternalSignalCount);
    let mut layout = Layout::new();
    // Balance whole gates by their port count. These cuts keep the widest bank
    // at 185 ports while preserving the original logical node order.
    let cuts = [0, 92, 143, nodes.len()];
    let banks: Vec<Vec<usize>> = (0..3)
        .map(|bank| {
            (cuts[bank]..cuts[bank + 1])
                .flat_map(|index| {
                    nodes[index]
                        .Inputs
                        .iter()
                        .copied()
                        .chain(std::iter::once(index))
                })
                .collect()
        })
        .collect();
    let maximumColumns = banks.iter().map(Vec::len).max().unwrap();
    let right = -90;
    let left = right - (maximumColumns as i32 - 1) * 2;
    let laneY = |bank: usize, group: usize| {
        -101 + bank as i32 * 64
            + if bank % 2 == 0 {
                group as i32 * 2
            } else {
                (24 - group) as i32 * 2
            }
    };
    for (bank, columns) in banks.iter().enumerate() {
        let top = -101 + bank as i32 * 64;
        for group in 0..25 {
            let y = laneY(bank, group);
            for column in 0..maximumColumns {
                let x = left + column as i32 * 2;
                layout.wire(
                    (x, y),
                    match columns.get(column) {
                        Some(&net) if signal(net).0 != group => Wire::Cross,
                        _ => Wire::Bus(group),
                    },
                );
                if x < right {
                    layout.wire((x + 1, y), Wire::Bus(group));
                }
            }
        }
        for (column, &net) in columns.iter().enumerate() {
            let x = left + column as i32 * 2;
            for offset in (1..48).step_by(2) {
                layout.wire((x, top + offset), Wire::Trace(net));
            }
            layout.wire((x, top + 49), Wire::Trace(net));
        }
        let mut first = 0;
        for index in cuts[bank]..cuts[bank + 1] {
            let node = &nodes[index];
            let last = first + node.Inputs.len();
            layout.device(
                node.Kind,
                (left + first as i32 * 2..=left + last as i32 * 2).map(|x| (x, top + 51)),
                node.Kind == "latch",
            );
            for column in first..=last {
                layout.device(
                    if column == last { "read" } else { "write" },
                    [(left + column as i32 * 2, top + 50)],
                    false,
                );
            }
            first = last + 1;
        }
    }
    // Reverse the lane order at each fold, so all 25 nested turns stay separate.
    for bank in 0..2 {
        for group in 0..25 {
            let (edge, turn, direction) = if bank == 0 {
                (right, right + 2 * (25 - group) as i32, 1)
            } else {
                (left, left - 2 * (group + 1) as i32, -1)
            };
            let (startY, endY) = (laneY(bank, group), laneY(bank + 1, group));
            let mut x = edge + direction;
            loop {
                layout.wire((x, startY), Wire::Bus(group));
                layout.wire((x, endY), Wire::Bus(group));
                if x == turn {
                    break;
                }
                x += direction;
            }
            for y in startY.min(endY)..=startY.max(endY) {
                layout.wire((turn, y), Wire::Bus(group));
            }
        }
    }
    // Each display column receives one Bus. Its eight colors select the rows.
    for column in 0..5 {
        let x = DisplayOrigin.0 + column * PixelPitch;
        let group = 20 + column as usize;
        let bottom = laneY(2, group);
        for sx in right + 1..=x - 3 {
            layout.wire((sx, bottom), Wire::Bus(group));
        }
        for y in DisplayOrigin.1..=bottom {
            layout.wire((x - 3, y), Wire::Bus(group));
        }
        for row in 0..8 {
            let y = DisplayOrigin.1 + row * PixelPitch;
            layout.device(
                "led",
                (0..PixelSize).flat_map(|dy| (0..PixelSize).map(move |dx| (x + dx, y + dy))),
                false,
            );
            layout.device("write", [(x - 1, y)], false);
            layout.wire(
                (x - 2, y),
                Wire::Trace(outputs + (row * 5 + column) as usize),
            );
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
