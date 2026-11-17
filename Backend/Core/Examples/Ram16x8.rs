#![allow(non_snake_case, non_upper_case_globals, dead_code)]
#[path = "ExampleLayout.rs"]
mod ExampleLayout;
use ExampleLayout::{Layout, Node};
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
fn gate(nodes: &mut Vec<Node>, next: &mut usize, kind: &'static str, inputs: Vec<usize>) -> usize {
    let id = *next;
    *next += 1;
    nodes.push(Node::gate(kind, id, inputs));
    id
}
pub fn buildProject() -> ProjectDocument {
    let mut layout = Layout::new();
    let mut controls = vec![];
    for net in 8..24 {
        controls.push(Node {
            Kind: "latch",
            Output: net,
            Inputs: vec![],
            On: net == Reset,
        });
    }
    for bit in 0..8 {
        controls.push(Node::gate(
            "switch",
            50_000 + bit,
            vec![16 + bit, bit, Drive],
        ));
        controls.push(Node::gate("led", 60_000 + bit, vec![bit]));
    }
    let left = -300;
    let mut tops = vec![-220];
    let (_, mut bottom) = layout.bank(&controls, left, tops[0], 3, 0);
    let mut next = 24;
    for row in 0..16 {
        let top = bottom + 3;
        tops.push(top);
        let mut nodes = vec![];
        let mut address = vec![];
        for bit in 0..4 {
            address.push(if row & (1 << bit) != 0 {
                8 + bit
            } else {
                gate(&mut nodes, &mut next, "not", vec![8 + bit])
            });
        }
        let selected = gate(&mut nodes, &mut next, "and", address);
        let notReset = gate(&mut nodes, &mut next, "not", vec![Reset]);
        let read = gate(&mut nodes, &mut next, "and", vec![selected, Oe, notReset]);
        let write = gate(&mut nodes, &mut next, "and", vec![selected, We, notReset]);
        for bit in 0..8 {
            let q = next;
            let qb = next + 1;
            next += 2;
            let inverted = gate(&mut nodes, &mut next, "not", vec![bit]);
            let set = gate(&mut nodes, &mut next, "and", vec![write, bit]);
            let clearWrite = gate(&mut nodes, &mut next, "and", vec![write, inverted]);
            let clear = gate(&mut nodes, &mut next, "or", vec![Reset, clearWrite]);
            nodes.push(Node::gate("nor", q, vec![clear, qb]));
            nodes.push(Node::gate("nor", qb, vec![set, q]));
            nodes.push(Node::gate(
                "switch",
                70_000 + row * 8 + bit,
                vec![q, bit, read],
            ));
        }
        (_, bottom) = layout.bank(&nodes, left, top, 3, row + 1);
    }
    layout.globals(left, &tops, 3, bottom - 5);
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
    println!(
        "Ram16x8: {}x{}, {} occupied cells; all addresses verified",
        project.Board.Grid.Width,
        project.Board.Grid.Height,
        project.Board.Tiles.len()
    );
}
