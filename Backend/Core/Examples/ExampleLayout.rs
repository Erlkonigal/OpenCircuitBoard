#![allow(dead_code)]
use ocb_core::Project::{Board, Grid, ProjectDocument, Tile};
use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet, VecDeque};
pub type Point = (i32, i32);
pub const TraceTools: [&str; 8] = [
    "trace",
    "traceRed",
    "traceGreen",
    "traceBlue",
    "traceCyan",
    "traceMagenta",
    "traceOrange",
    "traceWhite",
];
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Wire {
    Trace(usize),
    Bus(usize),
    Cross,
}
#[derive(Clone)]
pub struct Node {
    pub Kind: &'static str,
    pub Output: usize,
    pub Inputs: Vec<usize>,
    pub On: bool,
}
impl Node {
    pub fn gate(kind: &'static str, output: usize, inputs: Vec<usize>) -> Self {
        Self {
            Kind: kind,
            Output: output,
            Inputs: inputs,
            On: false,
        }
    }
}
pub struct Layout {
    pub Tiles: BTreeMap<Point, Tile>,
    pub Wires: BTreeMap<Point, Wire>,
    pub Colors: HashMap<usize, usize>,
    pub Fixed: HashMap<usize, bool>,
    pub Defaults: HashSet<usize>,
    pub NextId: i32,
}
impl Layout {
    pub fn new() -> Self {
        Self {
            Tiles: BTreeMap::new(),
            Wires: BTreeMap::new(),
            Colors: HashMap::new(),
            Fixed: HashMap::new(),
            Defaults: HashSet::new(),
            NextId: 1_000_000,
        }
    }
    pub fn device(
        &mut self,
        kind: &str,
        points: impl IntoIterator<Item = Point>,
        id: i32,
        on: bool,
    ) {
        for (x, y) in points {
            assert!(
                !self.Tiles.contains_key(&(x, y)) && !self.Wires.contains_key(&(x, y)),
                "Device collision {x},{y}"
            );
            self.Tiles.insert(
                (x, y),
                Tile {
                    X: x,
                    Y: y,
                    ToolId: kind.into(),
                    ComponentId: id,
                    IsOn: on,
                    ..Default::default()
                },
            );
        }
    }
    pub fn wire(&mut self, p: Point, w: Wire) {
        assert!(!self.Tiles.contains_key(&p), "Wire/device collision {p:?}");
        if let Some(old) = self.Wires.insert(p, w) {
            if old != w {
                if old == Wire::Cross || w == Wire::Cross {
                    self.Wires.insert(p, Wire::Cross);
                } else {
                    panic!("Wire collision {p:?}: {old:?} / {w:?}");
                }
            }
        }
    }
    pub fn point(&self, net: usize) -> Point {
        let tile = self
            .Tiles
            .values()
            .find(|t| t.ComponentId == net as i32 + 1)
            .unwrap();
        (tile.X, tile.Y)
    }
    /// Place arbitrary gates with their actual directional pins above a local bus bank.
    pub fn bank(
        &mut self,
        nodes: &[Node],
        left: i32,
        top: i32,
        globals: usize,
        bank: usize,
    ) -> (i32, i32) {
        let mut signals = BTreeSet::new();
        for n in nodes {
            if n.Kind != "switch" && n.Kind != "led" {
                signals.insert(n.Output);
            }
            signals.extend(n.Inputs.iter().copied());
        }
        let mut groups = HashMap::new();
        for net in 0..globals * 8 {
            groups.insert(net, (net / 8, net % 8));
            self.Colors.insert(net, net % 8);
        }
        for (i, net) in signals
            .into_iter()
            .filter(|&n| n >= globals * 8)
            .enumerate()
        {
            groups.insert(net, (globals + i / 8, i % 8));
            self.Colors.insert(net, i % 8);
        }
        let lanes = groups.values().map(|p| p.0).max().unwrap_or(0) + 1;
        let gateY = top + lanes as i32 * 2 + 2;
        let mut columns = vec![];
        let mut x = left;
        for n in nodes {
            if n.Kind == "switch" {
                columns.extend([(x, n.Inputs[0]), (x + 2, n.Inputs[1]), (x + 4, n.Inputs[2])]);
                self.device("switch", [(x + 1, gateY)], n.Output as i32 + 1, false);
                for p in [(x, gateY), (x + 2, gateY)] {
                    let net = if p.0 == x { n.Inputs[0] } else { n.Inputs[1] };
                    self.wire(p, Wire::Trace(net));
                }
                self.wire((x + 1, gateY + 1), Wire::Trace(n.Inputs[2]));
                for sx in x + 1..=x + 4 {
                    self.wire((sx, gateY + 2), Wire::Trace(n.Inputs[2]));
                }
                for sy in gateY..gateY + 2 {
                    self.wire((x + 4, sy), Wire::Trace(n.Inputs[2]));
                }
                x += 6;
            } else if n.Kind == "clock" {
                columns.push((x + 2, n.Output));
                self.device(n.Kind, [(x + 1, gateY)], n.Output as i32 + 1, n.On);
                self.wire((x + 2, gateY), Wire::Trace(n.Output));
                x += 4;
            } else if matches!(n.Kind, "buffer" | "not" | "led") {
                columns.push((x, n.Inputs[0]));
                self.wire((x, gateY), Wire::Trace(n.Inputs[0]));
                self.device(n.Kind, [(x + 1, gateY)], n.Output as i32 + 1, n.On);
                if n.Kind != "led" {
                    columns.push((x + 2, n.Output));
                    self.wire((x + 2, gateY), Wire::Trace(n.Output));
                }
                x += 4;
            } else {
                let width = (n.Inputs.len().saturating_sub(1) * 2 + 1) as i32;
                for (i, &net) in n.Inputs.iter().enumerate() {
                    columns.push((x + i as i32 * 2, net));
                }
                self.device(
                    n.Kind,
                    (x..x + width).map(|sx| (sx, gateY)),
                    n.Output as i32 + 1,
                    n.On,
                );
                columns.push((x + width, n.Output));
                self.wire((x + width, gateY), Wire::Trace(n.Output));
                x += width + 3;
            }
        }
        let right = x.max(left + 2);
        for lane in 0..lanes {
            let y = top + lane as i32 * 2;
            for sx in left..=right {
                let crossing = columns
                    .iter()
                    .find(|(cx, _)| *cx == sx)
                    .is_some_and(|(_, net)| groups[net].0 != lane);
                let key = if lane < globals {
                    lane
                } else {
                    10_000 + bank * 1000 + lane
                };
                self.wire(
                    (sx, y),
                    if crossing {
                        Wire::Cross
                    } else {
                        Wire::Bus(key)
                    },
                );
            }
        }
        for &(sx, net) in &columns {
            for y in top..gateY {
                if (y - top) % 2 != 0 || y >= top + lanes as i32 * 2 {
                    self.wire((sx, y), Wire::Trace(net));
                }
            }
        }
        (right, gateY + 4)
    }
    /// Connect global banks at the left, preserving independent horizontal/vertical buses.
    pub fn globals(&mut self, left: i32, tops: &[i32], count: usize, bottom: i32) {
        for group in 0..count {
            let sx = left - 3 * (count - group) as i32;
            for y in tops[0] + group as i32 * 2..=bottom {
                let cross = tops
                    .iter()
                    .enumerate()
                    .flat_map(|(_, top)| (0..count).map(move |g| (*top + g as i32 * 2, g)))
                    .any(|(ly, g)| ly == y && g < group);
                self.wire((sx, y), if cross { Wire::Cross } else { Wire::Bus(group) });
            }
            for &top in tops {
                let y = top + group as i32 * 2;
                for x in sx + 1..left {
                    let cross = (group + 1..count).any(|g| x == left - 3 * (count - g) as i32);
                    self.wire((x, y), if cross { Wire::Cross } else { Wire::Bus(group) });
                }
            }
        }
    }
    pub fn finish(mut self) -> ProjectDocument {
        let mut remaining: HashSet<_> = self.Wires.keys().copied().collect();
        for (&seed, &wire) in &self.Wires {
            if !remaining.remove(&seed) {
                continue;
            }
            let id = self.NextId;
            self.NextId += 1;
            let mut queue = VecDeque::from([seed]);
            while let Some((x, y)) = queue.pop_front() {
                let (kind, net) = match wire {
                    Wire::Trace(n) => (
                        TraceTools[*self.Colors.get(&n).unwrap_or(&(n % 8))],
                        Some(n),
                    ),
                    Wire::Bus(_) => ("bus", None),
                    Wire::Cross => ("cross", None),
                };
                self.Tiles.insert(
                    (x, y),
                    Tile {
                        X: x,
                        Y: y,
                        ToolId: kind.into(),
                        ComponentId: id,
                        IsOn: false,
                        FixedDrive: net.and_then(|n| self.Fixed.get(&n).copied()),
                        DefaultValue: net.is_some_and(|n| self.Defaults.contains(&n)),
                        ..Default::default()
                    },
                );
                for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                    let n = (x + dx, y + dy);
                    if self.Wires.get(&n) == Some(&wire) && remaining.remove(&n) {
                        queue.push_back(n);
                    }
                }
            }
        }
        let minX = self.Tiles.keys().map(|p| p.0).min().unwrap() - 4;
        let minY = self.Tiles.keys().map(|p| p.1).min().unwrap() - 4;
        let maxX = self.Tiles.keys().map(|p| p.0).max().unwrap() + 5;
        let maxY = self.Tiles.keys().map(|p| p.1).max().unwrap() + 5;
        let mut tiles: Vec<_> = self.Tiles.into_values().collect();
        tiles.sort_by_key(|t| (t.Y, t.X));
        let project = ProjectDocument {
            Board: Board {
                Grid: Grid {
                    OriginX: minX,
                    OriginY: minY,
                    Width: maxX - minX,
                    Height: maxY - minY,
                },
                Tiles: tiles,
                ..Default::default()
            },
            Blueprints: vec![],
        };
        project.validate().expect("Valid generated project");
        project
    }
}
