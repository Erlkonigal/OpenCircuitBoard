#![allow(non_snake_case, non_upper_case_globals, dead_code)]
#[path = "ExampleLayout.rs"]
mod ExampleLayout;
use ExampleLayout::{Layout, Node, Point, Wire};
use ocb_core::Project::{self, ProjectDocument};
use std::path::PathBuf;
pub const Message: &str = "Hello, World!";
pub const DisplayOrigin: Point = (-22, -37);
pub const PixelPitch: i32 = 10;
pub const PixelSize: i32 = 4;
pub const StartupTicks: usize = 5;
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

pub fn buildProject() -> ProjectDocument {
    let mut layout = Layout::new();
    let mut nodes = vec![];
    for i in 0..104 {
        nodes.push(Node::gate(
            if i == 0 { "not" } else { "buffer" },
            16 + i,
            vec![16 + if i == 0 { 103 } else { i - 1 }],
        ));
    }
    for i in 0..13 {
        nodes.push(Node::gate(
            if i == 12 { "xnor" } else { "xor" },
            i,
            vec![16 + i * 8, 16 + ((i + 1) % 13) * 8],
        ));
    }
    nodes.push(Node {
        Kind: "latch",
        Output: 13,
        Inputs: vec![],
        On: true,
    });
    nodes.push(Node::gate("buffer", 120, vec![13]));
    nodes.push(Node::gate("buffer", 121, vec![120]));
    nodes.push(Node::gate("buffer", 122, vec![121]));
    let (_, bottom) = layout.bank(&nodes, -300, -140, 2, 0);
    assert!(bottom < -75);
    // Thirteen word lines cross forty bit lines. Only stored zeroes get a switch.
    let romLeft = -250;
    let romTop = -75;
    let ground = 9999;
    layout.Fixed.insert(ground, false);
    for pixel in 0..40 {
        let net = 200 + pixel;
        layout.Colors.insert(net, pixel / 5);
        layout.Defaults.insert(net);
        let x = romLeft + pixel as i32 * 5;
        for y in romTop - 1..=80 + (pixel % 5) as i32 * 2 {
            let rowCross = y >= romTop + 2 && y <= romTop + 50 && (y - romTop - 2) % 4 == 0;
            let collectorCross = y >= 80 && (y - 80) % 2 == 0 && (y - 80) / 2 < (pixel % 5) as i32;
            let own = y == 80 + (pixel % 5) as i32 * 2;
            layout.wire(
                (x, y),
                if rowCross || collectorCross {
                    Wire::Cross
                } else if own {
                    Wire::Bus(100 + pixel % 5)
                } else {
                    Wire::Trace(net)
                },
            );
        }
    }
    for (row, ch) in Message.chars().enumerate() {
        let y = romTop + row as i32 * 4;
        let group = row / 8;
        let spine = -300 - 3 * (2 - group) as i32;
        for x in spine + 1..romLeft + 40 * 5 {
            let isBit = x >= romLeft && (x - romLeft) % 5 == 0;
            let spineCross = group == 0 && x == -303;
            layout.wire(
                (x, y + 2),
                if isBit || spineCross {
                    Wire::Cross
                } else {
                    Wire::Trace(row)
                },
            );
        }
        for pixel in 0..40 {
            if glyph(ch)[pixel / 5].as_bytes()[pixel % 5] == b'.' {
                let x = romLeft + pixel as i32 * 5;
                layout.device(
                    "switch",
                    [(x + 2, y)],
                    10000 + (row * 40 + pixel) as i32,
                    false,
                );
                layout.wire((x + 1, y), Wire::Trace(200 + pixel));
                layout.wire((x + 3, y), Wire::Trace(ground));
                layout.wire((x + 2, y + 1), Wire::Trace(row));
            }
        }
    }
    // Extend the two global buses through the matrix; tap colors pick the word line.
    layout.globals(-300, &[-140], 2, romTop + 50);
    for row in 0..13 {
        let y = romTop + row as i32 * 4 + 2;
        let group = row / 8;
        let spine = -300 - 3 * (2 - group) as i32;
        // The Trace immediately next to the bus selects its color.
        assert!(layout.Wires.contains_key(&(spine, y)));
    }
    // Five display buses collect eight rows each; the display remains at its original position.
    for column in 0..5 {
        let y = 80 + column * 2;
        let bx = DisplayOrigin.0 + column * PixelPitch - 3;
        for x in romLeft..=bx {
            let verticalBit = x >= romLeft && x < romLeft + 200 && (x - romLeft) % 5 == 0;
            let pixel = ((x - romLeft) / 5) as usize;
            let cross = verticalBit && pixel % 5 > column as usize;
            if !layout.Wires.contains_key(&(x, y)) {
                layout.wire(
                    (x, y),
                    if cross {
                        Wire::Cross
                    } else {
                        Wire::Bus(100 + column as usize)
                    },
                );
            }
        }
        for sy in DisplayOrigin.1..y {
            layout.wire((bx, sy), Wire::Bus(100 + column as usize));
        }
        for row in 0..8 {
            let px = DisplayOrigin.0 + column * PixelPitch;
            let py = DisplayOrigin.1 + row * PixelPitch;
            let pixel = (row * 5 + column) as usize;
            // A compact directional AND masks startup and drives a full-size display LED.
            layout.device("and", [(px - 1, py)], 20000 + pixel as i32, false);
            layout.wire((px - 2, py), Wire::Trace(200 + pixel));
            layout.device(
                "led",
                (0..PixelSize).flat_map(|dy| (0..PixelSize).map(move |dx| (px + 1 + dx, py + dy))),
                21000 + pixel as i32,
                false,
            );
            layout.wire((px, py), Wire::Trace(500 + pixel));
        }
    }
    // Startup enable is distributed in its own trace, with isolated crossings at display buses.
    let enableX = DisplayOrigin.0 - 6;
    // Bring enable from its bank output using a separate local bus lane.
    let enablePin = layout.point(122);
    let tap = (enablePin.0 + 1, enablePin.1);
    // The bank maps 122 to a local bus; route from its output below the bank instead.
    let ey = -85;
    for x in tap.0.min(enableX)..=tap.0.max(enableX) {
        layout.wire((x, ey), Wire::Trace(122));
    }
    for y in tap.1 + 1..ey {
        layout.wire((tap.0, y), Wire::Trace(122));
    }
    for y in ey..DisplayOrigin.1 + 71 {
        layout.wire((enableX, y), Wire::Trace(122));
    }
    for row in 0..8 {
        let py = DisplayOrigin.1 + row * PixelPitch;
        let sy = py - 2;
        for x in enableX + 1..=DisplayOrigin.0 + 4 * PixelPitch - 1 {
            let isBus = (0..5).any(|c| x == DisplayOrigin.0 + c * PixelPitch - 3);
            layout.wire((x, sy), if isBus { Wire::Cross } else { Wire::Trace(122) });
        }
        for c in 0..5 {
            let px = DisplayOrigin.0 + c * PixelPitch;
            layout.wire((px - 1, py - 1), Wire::Trace(122));
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
                let x = DisplayOrigin.0 + 1 + column as i32 * PixelPitch;
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
    Project::save(&path, &project).unwrap();
    println!(
        "HelloWorld5x8: {}x{}, {} occupied cells",
        project.Board.Grid.Width,
        project.Board.Grid.Height,
        project.Board.Tiles.len()
    );
}
