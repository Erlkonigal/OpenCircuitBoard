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
pub const StartupTicks: usize = 13;
pub const CharacterTicks: usize = 8;
pub const AddressSignals: [usize; 4] = [16, 17, 18, 19];
pub const WordSignals: usize = 40;
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

// Complementary clock phases select input or buffered feedback, preserving one bit.
fn muxLatch(
    nodes: &mut Vec<Node>,
    data: usize,
    output: usize,
    input: usize,
    sample: usize,
    hold: usize,
    switchIdBase: usize,
) {
    nodes.push(Node::gate(
        "switch",
        switchIdBase,
        vec![data, input, sample],
    ));
    nodes.push(Node::gate(
        "switch",
        switchIdBase + 1,
        vec![output, input, hold],
    ));
    nodes.push(Node::gate("buffer", output, vec![input]));
}

pub fn buildProject() -> ProjectDocument {
    let mut layout = Layout::new();
    let mut nodes = vec![];
    let clock = 13;
    let phaseA = 14;
    let phaseB = 15;
    nodes.push(Node {
        Kind: "clock",
        Output: clock,
        Inputs: vec![],
        On: false,
    });
    nodes.push(Node::gate("buffer", phaseA, vec![clock]));
    nodes.push(Node::gate("not", phaseB, vec![clock]));
    nodes.push(Node::gate("nor", 30, (0..13).collect()));
    nodes.push(Node::gate("or", 31, vec![12, 30]));
    nodes.push(Node::gate("not", 32, vec![31]));
    for stage in 0..13 {
        let base = 1000 + stage * 4;
        let data = if stage == 0 { 31 } else { stage - 1 };
        let master = base;
        let masterInput = base + 1;
        let outputInput = base + 2;
        let switchId = 100_000 + stage * 4;
        muxLatch(
            &mut nodes,
            data,
            master,
            masterInput,
            phaseB,
            phaseA,
            switchId,
        );
        muxLatch(
            &mut nodes,
            master,
            stage,
            outputInput,
            phaseA,
            phaseB,
            switchId + 2,
        );
    }
    for bit in 0..4 {
        nodes.push(Node::gate(
            "or",
            AddressSignals[bit],
            (0..13).filter(|stage| stage & (1 << bit) != 0).collect(),
        ));
    }
    nodes.push(Node::gate("or", 20, (0..13).collect()));
    nodes.push(Node::gate("buffer", 21, vec![20]));
    nodes.push(Node::gate("buffer", 22, vec![21]));
    nodes.push(Node::gate("buffer", 23, vec![22]));
    let ringLeft = -300;
    let ringTop = -145;
    let (encoderRight, bottom) = layout.bank(&nodes, ringLeft, ringTop, 3, 0);
    let clockTile = layout
        .Tiles
        .values_mut()
        .find(|tile| tile.ToolId == "clock")
        .unwrap();
    clockTile.ClockHoldTicks = Some((CharacterTicks / 2) as i32);
    assert!(bottom < -75);
    // Thirteen word lines cross forty bit lines. Only stored zeroes get a switch.
    let romLeft = -250;
    let romTop = -75;
    let decoderLeft = ringLeft;
    let decoderTop = -102;
    let mut decoder = vec![];
    for bit in 0..4 {
        decoder.push(Node::gate("buffer", 60 + bit, vec![AddressSignals[bit]]));
        decoder.push(Node::gate("not", 64 + bit, vec![AddressSignals[bit]]));
    }
    for row in 0..13 {
        decoder.push(Node::gate(
            "and",
            WordSignals + row,
            (0..4)
                .map(|bit| {
                    if row & (1 << bit) != 0 {
                        60 + bit
                    } else {
                        64 + bit
                    }
                })
                .collect(),
        ));
    }
    let (decoderRight, _) = layout.bank(&decoder, decoderLeft, decoderTop, 3, 1);
    for group in 0..2 {
        let lane = 3 + group;
        let bus = 11_000 + lane;
        let spine = decoderLeft - 3 * (2 - group) as i32;
        let y = decoderTop + lane as i32 * 2;
        for sy in y..=romTop + 50 {
            layout.wire((spine, sy), Wire::Bus(bus));
        }
        for sx in spine + 1..decoderLeft {
            layout.wire((sx, y), Wire::Bus(bus));
        }
    }
    let addressBusY = decoderTop + 4;
    let addressTrunkX = encoderRight + 2;
    let ey = -85;
    for sx in encoderRight + 1..=addressTrunkX {
        layout.wire((sx, ringTop + 4), Wire::Bus(2));
    }
    for sy in ringTop + 4..=ey {
        let endpoint = sy == ringTop + 4 || sy == addressBusY;
        let crossesLane = sy % 2 == 0;
        layout.wire(
            (addressTrunkX, sy),
            if endpoint {
                Wire::Bus(2)
            } else if crossesLane {
                Wire::Cross
            } else {
                Wire::Bus(2)
            },
        );
    }
    for sx in decoderRight + 1..=addressTrunkX {
        layout.wire((sx, addressBusY), Wire::Bus(2));
    }
    let high = 9999;
    layout.source(high);
    for pixel in 0..40 {
        let net = 200 + pixel;
        layout.Colors.insert(net, pixel / 5);
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
        let spine = ringLeft - 3 * (2 - group) as i32;
        for x in spine + 1..romLeft + 40 * 5 {
            let isBit = x >= romLeft && (x - romLeft) % 5 == 0;
            let spineCross = group == 0 && x == ringLeft - 3;
            layout.wire(
                (x, y + 2),
                if isBit || spineCross {
                    Wire::Cross
                } else {
                    Wire::Trace(WordSignals + row)
                },
            );
        }
        for pixel in 0..40 {
            if glyph(ch)[pixel / 5].as_bytes()[pixel % 5] == b'#' {
                let x = romLeft + pixel as i32 * 5;
                layout.device(
                    "switch",
                    [(x + 2, y)],
                    10000 + (row * 40 + pixel) as i32,
                    false,
                );
                layout.wire((x + 1, y), Wire::Trace(200 + pixel));
                layout.wire((x + 3, y), Wire::Trace(high));
                layout.wire((x + 2, y + 1), Wire::Trace(WordSignals + row));
            }
        }
    }
    // Tap each decoded row from one of two local buses beside the ROM.
    for row in 0..13 {
        let y = romTop + row as i32 * 4 + 2;
        let group = row / 8;
        let spine = ringLeft - 3 * (2 - group) as i32;
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
    let enableX = DisplayOrigin.0 - 6;
    // Bus color 7 carries the settled nonempty-ring signal beside the address bits.
    for x in enableX..addressTrunkX {
        layout.wire((x, ey), Wire::Trace(23));
    }
    for y in ey..DisplayOrigin.1 + 71 {
        layout.wire((enableX, y), Wire::Trace(23));
    }
    for row in 0..8 {
        let py = DisplayOrigin.1 + row * PixelPitch;
        let sy = py - 2;
        for x in enableX + 1..=DisplayOrigin.0 + 4 * PixelPitch - 1 {
            let isBus = (0..5).any(|c| x == DisplayOrigin.0 + c * PixelPitch - 3);
            layout.wire((x, sy), if isBus { Wire::Cross } else { Wire::Trace(23) });
        }
        for c in 0..5 {
            let px = DisplayOrigin.0 + c * PixelPitch;
            layout.wire((px - 1, py - 1), Wire::Trace(23));
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
