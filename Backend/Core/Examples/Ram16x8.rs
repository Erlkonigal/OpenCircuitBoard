#![allow(non_snake_case, non_upper_case_globals, dead_code)]
#[path = "ExampleLayout.rs"]
mod ExampleLayout;
use ExampleLayout::{Layout, Node, Point, Wire, occupiedSize};
use ocb_core::{
    Project::{self, ProjectDocument},
    SimulationCore,
};
use std::path::PathBuf;
pub const Reset: usize = 14;
pub const Drive: usize = 15;
pub const Oe: usize = 12;
pub const We: usize = 13;
pub const SettleTicks: i32 = 8;
pub const ArrayOrigin: Point = (-48, -120);
pub const CellWidth: i32 = 12;
pub const CellHeight: i32 = 16;
pub const InvertedData: usize = 32;
pub const InvertedAddress: usize = 40;
pub const NotReset: usize = 44;

/// One five-gate bit cell. Both NOR feedback paths remain inside its 12x16 footprint.
fn memoryCell(
    layout: &mut Layout,
    origin: Point,
    row: usize,
    bit: usize,
    read: usize,
    write: usize,
) {
    let q = 200 + row * 32 + bit * 4;
    let qb = q + 1;
    let set = q + 2;
    let clear = q + 3;
    for (signal, color) in [(q, 0), (qb, 1), (set, 2), (clear, 3)] {
        layout.Colors.insert(signal, color);
    }
    for (kind, point, signal, direction) in [
        ("and", (4, 4), set, 0),
        ("and", (4, 8), clear, 0),
        ("nor", (8, 8), q, 2),
        ("nor", (8, 4), qb, 2),
        ("switch", (10, 11), 70_000 + row * 8 + bit, 0),
    ] {
        layout.deviceFacing(
            kind,
            (origin.0 + point.0, origin.1 + point.1),
            signal,
            direction,
            false,
        );
    }
    for (x, y) in [
        (0, 2),
        (2, 2),
        (2, 4),
        (6, 3),
        (8, 10),
        (2, 13),
        (8, 13),
        (10, 13),
        (0, 14),
        (2, 14),
        (8, 14),
        (0, 15),
        (2, 15),
    ] {
        layout.wire((origin.0 + x, origin.1 + y), Wire::Cross);
    }
    for (net, path) in [
        (bit, vec![(0, 0), (0, 15)]),
        (InvertedData + bit, vec![(2, 0), (2, 15)]),
        (bit, vec![(0, 4), (3, 4)]),
        (InvertedData + bit, vec![(2, 8), (3, 8)]),
        (write, vec![(4, 2), (4, 3)]),
        (write, vec![(6, 2), (6, 6), (4, 6), (4, 7)]),
        (set, vec![(5, 4), (5, 3), (8, 3)]),
        (clear, vec![(5, 8), (5, 7), (8, 7)]),
        (qb, vec![(7, 4), (7, 6), (9, 6), (9, 8)]),
        (q, vec![(7, 8), (7, 10), (11, 10), (11, 4), (9, 4)]),
        (q, vec![(9, 10), (9, 11)]),
        (Reset, vec![(8, 9), (8, 15)]),
        (read, vec![(10, 12), (10, 14)]),
        (bit, vec![(11, 11), (11, 13), (0, 13)]),
    ] {
        layout.localPath(origin, Wire::Trace(net), &path);
    }
}

pub fn buildProject() -> ProjectDocument {
    let mut layout = Layout::new();
    for bit in 0..8 {
        layout.Colors.insert(bit, bit);
        layout.Colors.insert(InvertedData + bit, bit);
    }
    let (left, top) = ArrayOrigin;
    let decoderLeft = left - 24;
    let controlTop = top - 32;
    let mut controls = vec![];
    for net in 8..16 {
        controls.push(Node {
            Kind: "latch",
            Output: net,
            Inputs: vec![],
            On: net == Reset,
        });
    }
    for bit in 0..4 {
        controls.push(Node::gate("not", InvertedAddress + bit, vec![8 + bit]));
    }
    controls.push(Node::gate("not", NotReset, vec![Reset]));
    let controlBuses = vec![(1, (8..16).collect()), (2, (40..45).collect())];
    layout.compactBank(&controls, decoderLeft, controlTop, &controlBuses);
    let controlSpine = decoderLeft - 6;
    let inverseSpine = decoderLeft - 3;
    let lastY = top + 16 * CellHeight - 1;
    layout.path(
        Wire::Bus(1),
        &[(controlSpine, controlTop), (decoderLeft, controlTop)],
    );
    layout.path(
        Wire::Bus(1),
        &[(controlSpine, controlTop), (controlSpine, lastY)],
    );
    layout.path(
        Wire::Bus(2),
        &[
            (inverseSpine, controlTop + 2),
            (decoderLeft, controlTop + 2),
        ],
    );
    layout.path(
        Wire::Bus(2),
        &[(inverseSpine, controlTop + 2), (inverseSpine, lastY)],
    );

    // Data input, bidirectional Drive Switch, LED and shared inversion align with each bit column.
    for bit in 0..8 {
        let x = left + bit as i32 * CellWidth;
        for (kind, point, signal) in [
            ("latch", (x + 4, top - 12), 16 + bit),
            ("switch", (x + 7, top - 12), 50_000 + bit),
            ("led", (x + 4, top - 8), 60_000 + bit),
            ("not", (x + 3, top - 4), InvertedData + bit),
        ] {
            layout.deviceFacing(kind, point, signal, 0, false);
        }
        layout.wire((x + 8, top - 10), Wire::Cross);
        for (net, path) in [
            (16 + bit, vec![(x + 5, top - 12), (x + 6, top - 12)]),
            (Drive, vec![(x + 7, top - 11), (x + 7, top - 10)]),
            (
                bit,
                vec![
                    (x + 8, top - 12),
                    (x + 8, top - 6),
                    (x, top - 6),
                    (x, top - 8),
                    (x + 3, top - 8),
                ],
            ),
            (bit, vec![(x, top - 6), (x, top)]),
            (bit, vec![(x, top - 4), (x + 2, top - 4)]),
            (
                InvertedData + bit,
                vec![
                    (x + 4, top - 4),
                    (x + 4, top - 2),
                    (x + 2, top - 2),
                    (x + 2, top),
                ],
            ),
        ] {
            layout.path(Wire::Trace(net), &path);
        }
    }
    let right = left + 8 * CellWidth - 1;
    layout.wire((inverseSpine, top - 10), Wire::Cross);
    layout.path(
        Wire::Trace(Drive),
        &[(controlSpine + 1, top - 10), (right, top - 10)],
    );

    for row in 0..16 {
        let y = top + row as i32 * CellHeight;
        let selected = 100 + row * 3;
        let read = selected + 1;
        let write = selected + 2;
        let mut nodes = vec![Node::gate(
            "and",
            selected,
            (0..4)
                .map(|bit| {
                    if row & (1 << bit) != 0 {
                        8 + bit
                    } else {
                        InvertedAddress + bit
                    }
                })
                .collect(),
        )];
        nodes.push(Node::gate("and", read, vec![selected, Oe, NotReset]));
        nodes.push(Node::gate("and", write, vec![selected, We, NotReset]));
        let rowBus = 100 + row;
        let buses = vec![
            (1, (8..16).collect()),
            (2, (40..45).collect()),
            (rowBus, vec![selected, read, write]),
        ];
        let (decoderRight, _) = layout.compactBank(&nodes, decoderLeft, y, &buses);
        layout.wire((inverseSpine, y), Wire::Cross);
        layout.path(Wire::Bus(1), &[(controlSpine + 1, y), (decoderLeft, y)]);
        layout.path(
            Wire::Bus(2),
            &[(inverseSpine + 1, y + 2), (decoderLeft, y + 2)],
        );
        let rowSpine = decoderRight + 2;
        layout.path(
            Wire::Bus(rowBus),
            &[(decoderRight + 1, y + 4), (rowSpine, y + 4)],
        );
        layout.path(Wire::Bus(rowBus), &[(rowSpine, y + 2), (rowSpine, y + 14)]);
        for bit in 0..8 {
            memoryCell(
                &mut layout,
                (left + bit as i32 * CellWidth, y),
                row,
                bit,
                read,
                write,
            );
        }
        layout.path(Wire::Trace(write), &[(rowSpine + 1, y + 2), (right, y + 2)]);
        layout.path(
            Wire::Trace(read),
            &[(rowSpine + 1, y + 14), (right, y + 14)],
        );
        layout.wire((inverseSpine, y + 15), Wire::Cross);
        layout.path(
            Wire::Trace(Reset),
            &[(controlSpine + 1, y + 15), (right, y + 15)],
        );
    }
    layout.finish()
}
pub fn cell(project: &ProjectDocument, signal: usize, origin: (i32, i32), width: usize) -> usize {
    let tile = project
        .Board
        .Tiles
        .iter()
        .find(|t| t.ComponentId == signal as i32 + 1)
        .unwrap();
    (tile.Y - origin.1) as usize * width + (tile.X - origin.0) as usize
}
pub fn set(
    core: &mut SimulationCore,
    project: &ProjectDocument,
    origin: (i32, i32),
    signal: usize,
    on: bool,
) {
    let c = cell(project, signal, origin, core.Width);
    if core.states()[c] != (on as u8) {
        core.toggleLatch(c).unwrap();
    }
}
pub fn address(core: &mut SimulationCore, p: &ProjectDocument, o: (i32, i32), value: u8) {
    for bit in 0..4 {
        set(core, p, o, 8 + bit, value & (1 << bit) != 0);
    }
}
pub fn data(core: &mut SimulationCore, p: &ProjectDocument, o: (i32, i32), value: u8) {
    for bit in 0..8 {
        set(core, p, o, 16 + bit, value & (1 << bit) != 0);
    }
}
pub fn read(core: &mut SimulationCore, p: &ProjectDocument, o: (i32, i32)) -> u8 {
    let width = core.Width;
    (0..8).fold(0, |value, bit| {
        let c = cell(p, 60_000 + bit, o, width);
        value | (core.states()[c] << bit)
    })
}
pub fn verify(project: &ProjectDocument) {
    let (input, o) = project.Board.compileInput().unwrap();
    let mut core = SimulationCore::compile(input).unwrap();
    core.advanceSilent(SettleTicks);
    set(&mut core, project, o, Reset, false);
    core.advanceSilent(SettleTicks);
    for pattern in [0u8, 0xff, 0x5a] {
        for addr in 0..16 {
            address(&mut core, project, o, addr);
            data(&mut core, project, o, pattern ^ addr.wrapping_mul(13));
            set(&mut core, project, o, Drive, true);
            core.advanceSilent(SettleTicks);
            set(&mut core, project, o, We, true);
            core.advanceSilent(SettleTicks);
            set(&mut core, project, o, We, false);
            core.advanceSilent(SettleTicks);
            set(&mut core, project, o, Drive, false);
            core.advanceSilent(SettleTicks);
        }
        for addr in 0..16 {
            address(&mut core, project, o, addr);
            core.advanceSilent(SettleTicks);
            set(&mut core, project, o, Oe, true);
            core.advanceSilent(SettleTicks);
            assert_eq!(
                read(&mut core, project, o),
                pattern ^ addr.wrapping_mul(13),
                "RAM address {addr}"
            );
            set(&mut core, project, o, Oe, false);
            core.advanceSilent(SettleTicks);
        }
    }
    let snapshot = core.capture();
    set(&mut core, project, o, Reset, true);
    core.advanceSilent(SettleTicks);
    set(&mut core, project, o, Reset, false);
    set(&mut core, project, o, Oe, true);
    core.advanceSilent(SettleTicks);
    assert_eq!(read(&mut core, project, o), 0);
    core.restore(&snapshot).unwrap();
    set(&mut core, project, o, Oe, true);
    core.advanceSilent(SettleTicks);
    assert_eq!(read(&mut core, project, o), 0x5a ^ 15u8.wrapping_mul(13));
}
fn main() {
    let project = buildProject();
    verify(&project);
    let path = std::env::args_os()
        .nth(1)
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            PathBuf::from(env!("CARGO_MANIFEST_DIR"))
                .join("../../Frontend/Assets/Examples/Ram16x8.ocb")
        });
    Project::save(&path, &project).unwrap();
    let (width, height) = occupiedSize(project.Board.Tiles.iter());
    println!(
        "Ram16x8: board {}x{}, circuit {width}x{height}, {} occupied cells; all addresses verified",
        project.Board.Grid.Width,
        project.Board.Grid.Height,
        project.Board.Tiles.len()
    );
}
