#![allow(dead_code)]
use ocb_core::Project::{Board, Grid, ProjectDocument, Tile};
use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet, VecDeque};
pub type Point = (i32, i32);
pub fn occupiedSize<'a>(mut tiles: impl Iterator<Item = &'a Tile>) -> (i32, i32) {
    let first = tiles.next().expect("Nonempty example layout");
    let (minX, minY, maxX, maxY) = tiles.fold(
        (first.X, first.Y, first.X, first.Y),
        |(minX, minY, maxX, maxY), tile| {
            (
                minX.min(tile.X),
                minY.min(tile.Y),
                maxX.max(tile.X),
                maxY.max(tile.Y),
            )
        },
    );
    (maxX - minX + 1, maxY - minY + 1)
}
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
    pub Sources: BTreeSet<usize>,
    pub NextId: i32,
}
impl Layout {
    pub fn new() -> Self {
        Self {
            Tiles: BTreeMap::new(),
            Wires: BTreeMap::new(),
            Colors: HashMap::new(),
            Sources: BTreeSet::new(),
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
    pub fn source(&mut self, net: usize) {
        self.Sources.insert(net);
    }
    pub fn point(&self, net: usize) -> Point {
        let tile = self
            .Tiles
            .values()
            .find(|t| t.ComponentId == net as i32 + 1)
            .unwrap();
        (tile.X, tile.Y)
    }
    pub fn deviceFacing(
        &mut self,
        kind: &str,
        point: Point,
        signal: usize,
        direction: i32,
        on: bool,
    ) {
        self.device(kind, [point], signal as i32 + 1, on);
        self.Tiles.get_mut(&point).unwrap().Direction = direction;
    }
    /// Draw an orthogonal polyline; crossings must be declared explicitly first.
    pub fn path(&mut self, wire: Wire, points: &[Point]) {
        for segment in points.windows(2) {
            let (a, b) = (segment[0], segment[1]);
            assert!(
                a.0 == b.0 || a.1 == b.1,
                "Non-orthogonal route {a:?} / {b:?}"
            );
            let step = ((b.0 - a.0).signum(), (b.1 - a.1).signum());
            let mut point = a;
            loop {
                self.wire(point, wire);
                if point == b {
                    break;
                }
                point = (point.0 + step.0, point.1 + step.1);
            }
        }
    }
    pub fn localPath(&mut self, origin: Point, wire: Wire, points: &[Point]) {
        self.path(
            wire,
            &points
                .iter()
                .map(|p| (origin.0 + p.0, origin.1 + p.1))
                .collect::<Vec<_>>(),
        );
    }
    /// Compact directional gates with explicit, independently colored local buses.
    /// Two-input gates use west/north inputs; a third input enters from the south.
    pub fn compactBank(
        &mut self,
        nodes: &[Node],
        left: i32,
        top: i32,
        buses: &[(usize, Vec<usize>)],
    ) -> (i32, i32) {
        let mut groups = HashMap::new();
        for (lane, (_, signals)) in buses.iter().enumerate() {
            assert!(signals.len() <= 8);
            for (color, &signal) in signals.iter().enumerate() {
                assert!(
                    groups.insert(signal, lane).is_none(),
                    "Repeated signal {signal}"
                );
                if let Some(previous) = self.Colors.insert(signal, color) {
                    assert_eq!(previous, color, "Inconsistent bus color for {signal}");
                }
            }
        }
        let gateY = top + buses.len() as i32 * 2 + 2;
        let mut columns = vec![];
        let mut x = left;
        for node in nodes {
            let output = node.Output;
            match node.Kind {
                "button" | "clock" => {
                    self.deviceFacing(node.Kind, (x, gateY), output, 0, node.On);
                    self.wire((x + 1, gateY), Wire::Trace(output));
                    columns.push((x + 1, output));
                    x += 3;
                }
                "buffer" | "not" | "led" => {
                    self.deviceFacing(node.Kind, (x + 1, gateY), output, 0, node.On);
                    self.wire((x, gateY), Wire::Trace(node.Inputs[0]));
                    columns.push((x, node.Inputs[0]));
                    if node.Kind != "led" {
                        self.wire((x + 2, gateY), Wire::Trace(output));
                        columns.push((x + 2, output));
                    }
                    x += 3;
                }
                "switch" => {
                    self.deviceFacing("switch", (x + 1, gateY), output, 0, false);
                    for (dx, signal) in [(0, node.Inputs[0]), (2, node.Inputs[1])] {
                        self.wire((x + dx, gateY), Wire::Trace(signal));
                        columns.push((x + dx, signal));
                    }
                    let control = node.Inputs[2];
                    self.path(
                        Wire::Trace(control),
                        &[
                            (x + 1, gateY + 1),
                            (x + 1, gateY + 2),
                            (x + 3, gateY + 2),
                            (x + 3, gateY),
                        ],
                    );
                    columns.push((x + 3, control));
                    x += 4;
                }
                _ => {
                    let count = node.Inputs.len();
                    assert!(count > 0);
                    let width = if count <= 3 { 1 } else { count as i32 - 1 };
                    self.device(
                        node.Kind,
                        (1..=width).map(|dx| (x + dx, gateY)),
                        output as i32 + 1,
                        node.On,
                    );
                    self.wire((x, gateY), Wire::Trace(node.Inputs[0]));
                    columns.push((x, node.Inputs[0]));
                    for (i, &signal) in node.Inputs.iter().enumerate().skip(1) {
                        if count == 3 && i == 2 {
                            self.path(
                                Wire::Trace(signal),
                                &[
                                    (x + 1, gateY + 1),
                                    (x + 1, gateY + 2),
                                    (x + 3, gateY + 2),
                                    (x + 3, gateY),
                                ],
                            );
                            columns.push((x + 3, signal));
                        } else {
                            columns.push((x + i as i32, signal));
                        }
                    }
                    self.wire((x + width + 1, gateY), Wire::Trace(output));
                    columns.push((x + width + 1, output));
                    x += if count == 3 { 4 } else { width + 2 };
                }
            }
        }
        let right = x;
        for (lane, (key, _)) in buses.iter().enumerate() {
            let y = top + lane as i32 * 2;
            for sx in left..=right {
                let crossing = columns
                    .iter()
                    .find(|p| p.0 == sx)
                    .is_some_and(|p| groups[&p.1] != lane);
                self.wire(
                    (sx, y),
                    if crossing {
                        Wire::Cross
                    } else {
                        Wire::Bus(*key)
                    },
                );
            }
        }
        for (sx, signal) in columns {
            assert!(groups.contains_key(&signal), "Unbound bank signal {signal}");
            for y in top..gateY {
                if (y - top) % 2 != 0 || y >= top + buses.len() as i32 * 2 {
                    self.wire((sx, y), Wire::Trace(signal));
                }
            }
        }
        (right, gateY + 4)
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
        for net in self.Sources.iter().copied() {
            let traceWire = Wire::Trace(net);
            let mut remaining: BTreeSet<_> = self
                .Wires
                .iter()
                .filter_map(|(&point, &wire)| (wire == traceWire).then_some(point))
                .collect();
            while let Some(seed) = remaining.pop_first() {
                let mut queue = VecDeque::from([seed]);
                let mut source = None;
                while let Some(trace) = queue.pop_front() {
                    for (direction, (dx, dy)) in
                        [(1, 0), (0, 1), (-1, 0), (0, -1)].into_iter().enumerate()
                    {
                        let point = (trace.0 - dx, trace.1 - dy);
                        if source.is_none()
                            && !self.Wires.contains_key(&point)
                            && !self.Tiles.contains_key(&point)
                        {
                            source = Some((point, direction as i32));
                        }
                        let neighbor = (trace.0 + dx, trace.1 + dy);
                        if self.Wires.get(&neighbor) == Some(&traceWire)
                            && remaining.remove(&neighbor)
                        {
                            queue.push_back(neighbor);
                        }
                    }
                }
                let (point, direction) =
                    source.expect("Constant source must have an available trace endpoint");
                let id = self.NextId;
                self.NextId += 1;
                self.Tiles.insert(
                    point,
                    Tile {
                        X: point.0,
                        Y: point.1,
                        ToolId: "button".into(),
                        ComponentId: id,
                        IsOn: true,
                        Direction: direction,
                        ..Default::default()
                    },
                );
            }
        }
        let mut remaining: HashSet<_> = self.Wires.keys().copied().collect();
        for (&seed, &wire) in &self.Wires {
            if !remaining.remove(&seed) {
                continue;
            }
            let id = self.NextId;
            self.NextId += 1;
            let mut queue = VecDeque::from([seed]);
            while let Some((x, y)) = queue.pop_front() {
                let kind = match wire {
                    Wire::Trace(n) => TraceTools[*self.Colors.get(&n).unwrap_or(&(n % 8))],
                    Wire::Bus(_) => "bus",
                    Wire::Cross => "cross",
                };
                self.Tiles.insert(
                    (x, y),
                    Tile {
                        X: x,
                        Y: y,
                        ToolId: kind.into(),
                        ComponentId: id,
                        IsOn: false,
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
