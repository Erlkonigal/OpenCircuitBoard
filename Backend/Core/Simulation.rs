use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, HashMap, HashSet};

pub const MaximumCellCount: usize = 1_048_576;
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CompileInput {
    pub Width: usize,
    pub Height: usize,
    pub Kinds: Vec<i32>,
    pub InitialStates: Vec<i32>,
    pub ClockHoldTicks: Vec<i32>,
    pub ComponentIds: Vec<i32>,
    pub Directions: Vec<i32>,
    pub FixedDrives: Vec<i32>,
    pub DefaultValues: Vec<i32>,
    pub CrossMasks: Vec<i32>,
}
impl CompileInput {
    pub fn empty(width: usize, height: usize) -> Self {
        let count = width * height;
        Self {
            Width: width,
            Height: height,
            Kinds: vec![0; count],
            InitialStates: vec![0; count],
            ClockHoldTicks: vec![1; count],
            ComponentIds: vec![0; count],
            Directions: vec![0; count],
            FixedDrives: vec![-1; count],
            DefaultValues: vec![0; count],
            CrossMasks: vec![0; count],
        }
    }
}
#[derive(Clone, Debug, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CompileError {
    pub ErrorX: i32,
    pub ErrorY: i32,
    pub ErrorReason: String,
    pub HasPosition: bool,
}
impl CompileError {
    fn new(cell: Option<usize>, width: usize, reason: &str) -> Self {
        Self {
            ErrorX: cell.map_or(-1, |v| (v % width) as i32),
            ErrorY: cell.map_or(-1, |v| (v / width) as i32),
            ErrorReason: reason.into(),
            HasPosition: cell.is_some(),
        }
    }
}
#[derive(Default)]
struct DisjointSet {
    Parents: Vec<usize>,
}
impl DisjointSet {
    fn add(&mut self) -> usize {
        let n = self.Parents.len();
        self.Parents.push(n);
        n
    }
    fn find(&mut self, mut n: usize) -> usize {
        while self.Parents[n] != n {
            self.Parents[n] = self.Parents[self.Parents[n]];
            n = self.Parents[n];
        }
        n
    }
    fn unite(&mut self, a: usize, b: usize) {
        let a = self.find(a);
        let b = self.find(b);
        self.Parents[b] = a;
    }
}
pub fn isTrace(kind: i32) -> bool {
    matches!(kind, 1..=6 | 28..=29)
}
fn isDevice(kind: i32) -> bool {
    matches!(kind, 17..=27 | 30)
}
fn color(kind: i32) -> usize {
    match kind {
        1..=6 => kind as usize - 1,
        28..=29 => kind as usize - 22,
        _ => usize::MAX,
    }
}
fn unique(values: &mut Vec<usize>, n: usize) {
    if !values.contains(&n) {
        values.push(n);
    }
}
#[derive(Default)]
struct Device {
    Kind: i32,
    Initial: u8,
    Hold: i32,
    Output: usize,
    Inputs: Vec<usize>,
    Terminals: [usize; 3],
}
#[derive(Default)]
struct Network {
    Drivers: usize,
    High: usize,
    Value: u8,
    Domain: usize,
    Local: usize,
    Watchers: Vec<usize>,
    Cells: Vec<usize>,
}
#[derive(Default)]
struct Domain {
    Nets: Vec<usize>,
    Switches: Vec<usize>,
    Parents: Vec<usize>,
    Drivers: Vec<usize>,
    High: Vec<usize>,
}
/// Static conductors are compiled once. Only dirty potential-switch domains are resolved.
#[derive(Default)]
pub struct SimulationCore {
    pub Width: usize,
    pub Height: usize,
    pub Tick: u64,
    Devices: Vec<Device>,
    Networks: Vec<Network>,
    Domains: Vec<Domain>,
    States: Vec<u8>,
    Phases: Vec<i32>,
    Next: Vec<Option<u8>>,
    Scheduled: Vec<usize>,
    Clocks: Vec<usize>,
    DeviceCells: Vec<Vec<usize>>,
    CellDevices: Vec<usize>,
    CellNetworks: Vec<Vec<usize>>,
    Visible: Vec<u8>,
    Reported: Vec<u8>,
    DirtyDomains: HashSet<usize>,
    DirtyCells: HashSet<usize>,
    Signature: u64,
    Compiled: bool,
}
impl SimulationCore {
    pub fn compile(input: CompileInput) -> Result<Self, CompileError> {
        let (width, height) = (input.Width, input.Height);
        let fail = |cell, reason| CompileError::new(cell, width.max(1), reason);
        let count = width
            .checked_mul(height)
            .filter(|&n| n <= MaximumCellCount && n > 0)
            .ok_or_else(|| fail(None, "grid_too_large"))?;
        if width == 0 || height == 0 {
            return Err(fail(None, "invalid_grid_size"));
        }
        let arrays = [
            &input.Kinds,
            &input.InitialStates,
            &input.ClockHoldTicks,
            &input.ComponentIds,
            &input.Directions,
            &input.FixedDrives,
            &input.DefaultValues,
            &input.CrossMasks,
        ];
        if arrays.iter().any(|a| a.len() != count) {
            return Err(fail(None, "array_size_mismatch"));
        }
        let neighbor = |cell: usize, side: usize| -> Option<usize> {
            let (dx, dy) = [(1, 0), (0, 1), (-1, 0), (0, -1)][side];
            let x = (cell % width) as i32 + dx;
            let y = (cell / width) as i32 + dy;
            (x >= 0 && y >= 0 && x < width as i32 && y < height as i32)
                .then(|| y as usize * width + x as usize)
        };
        let mut groups: BTreeMap<i32, Vec<usize>> = BTreeMap::new();
        let mut signature = 1469598103934665603u64;
        for value in [width as i32, height as i32]
            .into_iter()
            .chain(arrays.iter().flat_map(|a| a.iter().copied()))
        {
            for b in value.to_le_bytes() {
                signature = (signature ^ b as u64).wrapping_mul(1099511628211);
            }
        }
        for cell in 0..count {
            let kind = input.Kinds[cell];
            if !matches!(kind, 0..=7 | 13 | 17..=30) {
                return Err(fail(Some(cell), "unknown_kind"));
            }
            if (kind == 0 && input.ComponentIds[cell] != 0)
                || (kind != 0 && input.ComponentIds[cell] <= 0)
            {
                return Err(fail(Some(cell), "invalid_component_id"));
            }
            if !(0..4).contains(&input.Directions[cell])
                || !(-1..=1).contains(&input.FixedDrives[cell])
                || !(0..=1).contains(&input.DefaultValues[cell])
                || !(0..=255).contains(&input.CrossMasks[cell])
                || !(0..=1).contains(&input.InitialStates[cell])
            {
                return Err(fail(Some(cell), "invalid_component_settings"));
            }
            if input.FixedDrives[cell] != -1
                || input.DefaultValues[cell] != 0
                || (kind != 13 && input.CrossMasks[cell] != 0)
                || (kind == 26 && input.ClockHoldTicks[cell] < 1)
            {
                return Err(fail(Some(cell), "invalid_component_settings"));
            }
            if kind != 0 {
                groups
                    .entry(input.ComponentIds[cell])
                    .or_default()
                    .push(cell);
            }
        }
        let mut seen = vec![false; count];
        for cells in groups.values() {
            let first = cells[0];
            let mut queue = vec![first];
            seen[first] = true;
            for &cell in cells {
                if input.Kinds[cell] != input.Kinds[first]
                    || input.Directions[cell] != input.Directions[first]
                    || input.CrossMasks[cell] != input.CrossMasks[first]
                    || (input.Kinds[cell] == 25
                        && input.InitialStates[cell] != input.InitialStates[first])
                    || (input.Kinds[cell] == 26
                        && input.ClockHoldTicks[cell] != input.ClockHoldTicks[first])
                {
                    return Err(fail(Some(cell), "incompatible_component"));
                }
            }
            let mut cursor = 0;
            while cursor < queue.len() {
                let cell = queue[cursor];
                cursor += 1;
                for side in 0..4 {
                    if let Some(n) = neighbor(cell, side) {
                        if !seen[n] && input.ComponentIds[n] == input.ComponentIds[first] {
                            seen[n] = true;
                            queue.push(n);
                        }
                    }
                }
            }
            if queue.len() != cells.len() {
                return Err(fail(Some(first), "disconnected_component"));
            }
        }
        let mut conductors = DisjointSet::default();
        let mut anchors: HashMap<i32, Vec<usize>> = HashMap::new();
        let mut crosses: HashMap<usize, Vec<usize>> = HashMap::new();
        let mut devices = vec![];
        let mut deviceCells = vec![];
        let mut cellDevices = vec![usize::MAX; count];
        for (&id, cells) in &groups {
            let kind = input.Kinds[cells[0]];
            if isTrace(kind) || kind == 7 {
                anchors.insert(
                    id,
                    (0..if kind == 7 { 8 } else { 1 })
                        .map(|_| conductors.add())
                        .collect(),
                );
            }
            if isDevice(kind) {
                deviceCells.push(cells.clone());
                let index = devices.len();
                let output = conductors.add();
                devices.push(Device {
                    Kind: kind,
                    Initial: (input.InitialStates[cells[0]] != 0) as u8,
                    Hold: input.ClockHoldTicks[cells[0]],
                    Output: output,
                    Terminals: std::array::from_fn(|_| conductors.add()),
                    ..Default::default()
                });
                for &cell in cells {
                    cellDevices[cell] = index;
                }
            }
            if kind == 13 {
                for &cell in cells {
                    crosses.insert(cell, (0..16).map(|_| conductors.add()).collect());
                }
            }
        }
        for cell in 0..count {
            let kind = input.Kinds[cell];
            for side in 0..4 {
                if let Some(n) = neighbor(cell, side) {
                    let nk = input.Kinds[n];
                    if isTrace(kind) && nk == 7 {
                        conductors.unite(
                            anchors[&input.ComponentIds[cell]][0],
                            anchors[&input.ComponentIds[n]][color(kind)],
                        );
                    }
                    if kind == 13 {
                        let axis = if side % 2 == 0 { 0 } else { 8 };
                        if isTrace(nk) {
                            conductors.unite(
                                crosses[&cell][axis + color(nk)],
                                anchors[&input.ComponentIds[n]][0],
                            );
                        }
                        if nk == 7 {
                            for c in 0..8 {
                                conductors.unite(
                                    crosses[&cell][axis + c],
                                    anchors[&input.ComponentIds[n]][c],
                                );
                            }
                        }
                        if nk == 13 && input.ComponentIds[cell] == input.ComponentIds[n] {
                            for c in 0..8 {
                                conductors.unite(crosses[&cell][axis + c], crosses[&n][axis + c]);
                            }
                        }
                    }
                }
            }
            if kind == 13 {
                for c in 0..8 {
                    if input.CrossMasks[cell] & (1 << c) != 0 {
                        conductors.unite(crosses[&cell][c], crosses[&cell][8 + c]);
                    }
                }
            }
        }
        let mut pins: Vec<BTreeMap<(usize, i32), usize>> =
            (0..devices.len()).map(|_| BTreeMap::new()).collect();
        for cell in 0..count {
            let id = cellDevices[cell];
            if id == usize::MAX {
                continue;
            }
            let kind = input.Kinds[cell];
            let direction = input.Directions[cell] as usize;
            for side in 0..4 {
                if let Some(n) = neighbor(cell, side) {
                    if !isTrace(input.Kinds[n]) {
                        continue;
                    }
                    let trace = anchors[&input.ComponentIds[n]][0];
                    let local = (side + 4 - direction) % 4;
                    if kind == 30 {
                        if let Some(terminal) = match local {
                            2 => Some(0),
                            0 => Some(1),
                            1 => Some(2),
                            _ => None,
                        } {
                            conductors.unite(devices[id].Terminals[terminal], trace);
                        }
                    } else if local == 0 && kind != 27 {
                        conductors.unite(devices[id].Output, trace);
                    } else if local != 0
                        && !matches!(kind, 25 | 26)
                        && (!matches!(kind, 17 | 21 | 27) || local == 2)
                    {
                        pins[id].insert((side, input.ComponentIds[n]), trace);
                    }
                }
            }
        }
        let mut roots = HashMap::new();
        let mut mapping = vec![];
        for anchor in 0..conductors.Parents.len() {
            let root = conductors.find(anchor);
            let next = roots.len();
            mapping.push(*roots.entry(root).or_insert(next));
        }
        let mut networks: Vec<Network> = (0..roots.len()).map(|_| Network::default()).collect();
        for (id, device) in devices.iter_mut().enumerate() {
            device.Output = mapping[device.Output];
            device.Terminals = device.Terminals.map(|a| mapping[a]);
            device.Inputs = if device.Kind == 30 {
                vec![device.Terminals[2]]
            } else {
                pins[id].values().map(|&a| mapping[a]).collect()
            };
            for &net in &device.Inputs {
                unique(&mut networks[net].Watchers, id);
            }
            if device.Kind != 30 && device.Kind != 27 {
                networks[device.Output].Drivers += 1;
            }
        }
        let mut cellNetworks = vec![vec![]; count];
        for cell in 0..count {
            let kind = input.Kinds[cell];
            if let Some(a) = anchors.get(&input.ComponentIds[cell]) {
                cellNetworks[cell] = a.iter().map(|&n| mapping[n]).collect();
            }
            if kind == 13 {
                cellNetworks[cell] = crosses[&cell].iter().map(|&n| mapping[n]).collect();
            }
            for &net in &cellNetworks[cell] {
                networks[net].Cells.push(cell);
            }
        }
        let mut potential = DisjointSet::default();
        for _ in &networks {
            potential.add();
        }
        for device in &devices {
            if device.Kind == 30 {
                potential.unite(device.Terminals[0], device.Terminals[1]);
            }
        }
        let mut domains: Vec<Domain> = vec![];
        let mut domainIds = HashMap::new();
        for (n, net) in networks.iter_mut().enumerate() {
            let root = potential.find(n);
            let next = domains.len();
            let id = *domainIds.entry(root).or_insert_with(|| {
                domains.push(Domain::default());
                next
            });
            net.Domain = id;
            net.Local = domains[id].Nets.len();
            domains[id].Nets.push(n);
        }
        for (id, d) in devices.iter().enumerate() {
            if d.Kind == 30 {
                domains[networks[d.Terminals[0]].Domain].Switches.push(id);
            }
        }
        for domain in &mut domains {
            let n = domain.Nets.len();
            domain.Parents = (0..n).collect();
            domain.Drivers = vec![0; n];
            domain.High = vec![0; n];
        }
        let clocks = devices
            .iter()
            .enumerate()
            .filter_map(|(id, d)| (d.Kind == 26).then_some(id))
            .collect();
        let deviceCount = devices.len();
        let mut core = Self {
            Width: width,
            Height: height,
            Devices: devices,
            Networks: networks,
            Domains: domains,
            States: vec![0; deviceCount],
            Phases: vec![0; deviceCount],
            Next: vec![None; deviceCount],
            Clocks: clocks,
            DeviceCells: deviceCells,
            CellDevices: cellDevices,
            CellNetworks: cellNetworks,
            Visible: vec![0; count],
            Reported: vec![0; count],
            Signature: signature,
            Compiled: true,
            ..Default::default()
        };
        core.resetSilent();
        Ok(core)
    }
    fn markOutput(&mut self, id: usize, value: u8) {
        let previous = self.States[id];
        if previous == value {
            return;
        }
        self.States[id] = value;
        let d = &self.Devices[id];
        if d.Kind == 30 {
            self.DirtyDomains
                .insert(self.Networks[d.Terminals[0]].Domain);
        } else if d.Kind != 27 {
            let net = &mut self.Networks[d.Output];
            net.High = net.High + value as usize - previous as usize;
            self.DirtyDomains.insert(net.Domain);
        }
        // Devices usually occupy few cells; use the compiled membership list below.
        for &cell in &self.DeviceCells[id] {
            self.DirtyCells.insert(cell);
        }
    }
    fn schedule(&mut self, id: usize, value: u8) {
        if self.Next[id].is_none() {
            self.Scheduled.push(id);
        }
        self.Next[id] = Some(value);
    }
    fn evaluate(&mut self, id: usize) {
        let d = &self.Devices[id];
        let high = d
            .Inputs
            .iter()
            .filter(|&&n| self.Networks[n].Value != 0)
            .count();
        let any = high > 0;
        let all = !d.Inputs.is_empty() && high == d.Inputs.len();
        let next = match d.Kind {
            17 | 19 | 27 | 30 => any as u8,
            18 => all as u8,
            20 => (high % 2) as u8,
            21 | 23 => (!any) as u8,
            22 => (!all) as u8,
            24 => (high % 2 == 0) as u8,
            _ => self.States[id],
        };
        if next != self.States[id] || self.Next[id].is_some() {
            self.schedule(id, next);
        }
    }
    fn resolve(&mut self) {
        let dirty: Vec<_> = self.DirtyDomains.drain().collect();
        let mut watchers = HashSet::new();
        for id in dirty {
            let domain = &mut self.Domains[id];
            for (i, p) in domain.Parents.iter_mut().enumerate() {
                *p = i;
            }
            fn root(parents: &mut [usize], mut i: usize) -> usize {
                while parents[i] != i {
                    parents[i] = parents[parents[i]];
                    i = parents[i];
                }
                i
            }
            for &switch in &domain.Switches {
                if self.States[switch] != 0 {
                    let d = &self.Devices[switch];
                    let a = root(&mut domain.Parents, self.Networks[d.Terminals[0]].Local);
                    let b = root(&mut domain.Parents, self.Networks[d.Terminals[1]].Local);
                    domain.Parents[b] = a;
                }
            }
            domain.Drivers.fill(0);
            domain.High.fill(0);
            for (local, &n) in domain.Nets.iter().enumerate() {
                let r = root(&mut domain.Parents, local);
                domain.Drivers[r] += self.Networks[n].Drivers;
                domain.High[r] += self.Networks[n].High;
            }
            for (local, &n) in domain.Nets.iter().enumerate() {
                let r = root(&mut domain.Parents, local);
                let value = (domain.Drivers[r] > 0 && domain.High[r] > 0) as u8;
                let net = &mut self.Networks[n];
                if value != net.Value {
                    net.Value = value;
                    watchers.extend(net.Watchers.iter().copied());
                    self.DirtyCells.extend(net.Cells.iter().copied());
                }
            }
        }
        for id in watchers {
            self.evaluate(id);
        }
    }
    pub fn advanceSilent(&mut self, ticks: i32) {
        if !self.Compiled {
            return;
        }
        for _ in 0..ticks.max(0) {
            let scheduled = std::mem::take(&mut self.Scheduled);
            for id in scheduled {
                if let Some(value) = self.Next[id].take() {
                    self.markOutput(id, value);
                }
            }
            for i in 0..self.Clocks.len() {
                let id = self.Clocks[i];
                self.Phases[id] += 1;
                if self.Phases[id] >= self.Devices[id].Hold {
                    self.Phases[id] = 0;
                    self.markOutput(id, 1 - self.States[id]);
                }
            }
            self.resolve();
            self.Tick = self.Tick.wrapping_add(1);
        }
    }
    pub fn advance(&mut self, ticks: i32) -> Vec<i32> {
        self.advanceSilent(ticks);
        self.drain()
    }
    pub fn toggleButton(&mut self, cell: usize) -> Result<(), String> {
        let &id = self.CellDevices.get(cell).ok_or("cell_out_of_bounds")?;
        if id == usize::MAX || self.Devices[id].Kind != 25 {
            return Err("not_button".into());
        }
        self.markOutput(id, 1 - self.States[id]);
        self.resolve();
        Ok(())
    }
    pub fn resetSilent(&mut self) {
        self.Tick = 0;
        self.Next.fill(None);
        self.Scheduled.clear();
        self.Phases.fill(0);
        for net in &mut self.Networks {
            net.High = 0;
            net.Value = 0;
        }
        for (id, d) in self.Devices.iter().enumerate() {
            self.States[id] = if d.Kind == 25 { d.Initial } else { 0 };
            if d.Kind != 30 && d.Kind != 27 {
                self.Networks[d.Output].High += self.States[id] as usize;
            }
        }
        self.DirtyDomains.extend(0..self.Domains.len());
        self.resolve();
        for id in 0..self.Devices.len() {
            self.evaluate(id);
        }
        self.DirtyCells.extend(0..self.Visible.len());
        self.materialize();
        self.Reported.copy_from_slice(&self.Visible);
    }
    fn materialize(&mut self) {
        for cell in self.DirtyCells.drain() {
            let id = self.CellDevices[cell];
            self.Visible[cell] = if id != usize::MAX {
                self.States[id]
            } else {
                self.CellNetworks[cell]
                    .iter()
                    .any(|&n| self.Networks[n].Value != 0) as u8
            };
        }
    }
    pub fn states(&mut self) -> &[u8] {
        self.materialize();
        &self.Visible
    }
    pub fn drain(&mut self) -> Vec<i32> {
        self.materialize();
        let mut changes = vec![];
        for (cell, (&value, old)) in self.Visible.iter().zip(&mut self.Reported).enumerate() {
            if value != *old {
                changes.push(cell as i32);
                changes.push(value as i32);
                *old = value;
            }
        }
        changes
    }
    pub fn inspect(&self, cell: usize) -> Vec<u8> {
        self.CellNetworks
            .get(cell)
            .into_iter()
            .flatten()
            .map(|&n| self.Networks[n].Value)
            .collect()
    }
    pub fn probeCapacity(&mut self) -> f64 {
        let snapshot = self.capture();
        let start = std::time::Instant::now();
        let mut ticks = 0;
        while start.elapsed().as_millis() < 20 && ticks < 1_048_576 {
            self.advanceSilent(16);
            ticks += 16;
        }
        let rate = ticks as f64 / start.elapsed().as_secs_f64();
        self.restore(&snapshot).expect("own snapshot");
        rate.max(1.)
    }
    pub fn capture(&self) -> Snapshot {
        Snapshot {
            Signature: self.Signature,
            Tick: self.Tick,
            States: self.States.clone(),
            Phases: self.Phases.clone(),
            Next: self.Next.clone(),
        }
    }
    pub fn restore(&mut self, snapshot: &Snapshot) -> Result<(), String> {
        if snapshot.Signature != self.Signature {
            return Err("snapshot_topology_mismatch".into());
        }
        self.resetSilent();
        self.Next = snapshot.Next.clone();
        self.Scheduled = self
            .Next
            .iter()
            .enumerate()
            .filter_map(|(i, v)| v.map(|_| i))
            .collect();
        self.Phases.clone_from(&snapshot.Phases);
        self.Tick = snapshot.Tick;
        for (id, &state) in snapshot.States.iter().enumerate() {
            self.markOutput(id, state);
        }
        // Reconstruct networks without changing the captured pending device updates.
        let next = self.Next.clone();
        let scheduled = self.Scheduled.clone();
        self.resolve();
        self.Next = next;
        self.Scheduled = scheduled;
        self.DirtyCells.extend(0..self.Visible.len());
        self.materialize();
        self.Reported.copy_from_slice(&self.Visible);
        Ok(())
    }
}
#[derive(Clone)]
pub struct Snapshot {
    Signature: u64,
    Tick: u64,
    States: Vec<u8>,
    Phases: Vec<i32>,
    Next: Vec<Option<u8>>,
}
impl Snapshot {
    pub fn byteCount(&self) -> usize {
        std::mem::size_of::<Self>()
            + self.States.len()
            + self.Phases.len() * std::mem::size_of::<i32>()
            + self.Next.len() * std::mem::size_of::<Option<u8>>()
    }
}
