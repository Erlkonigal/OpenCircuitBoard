use crate::RuntimeArena::{Arena, Buffer};
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, HashMap};

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
            HasPosition: cell.is_some(),
            ErrorX: cell.map_or(-1, |v| (v % width) as i32),
            ErrorY: cell.map_or(-1, |v| (v / width) as i32),
            ErrorReason: reason.into(),
        }
    }
}
#[derive(Clone)]
struct DisjointSet {
    Parents: Vec<usize>,
    Ranks: Vec<u8>,
}
impl DisjointSet {
    fn new(count: usize) -> Self {
        Self {
            Parents: (0..count).collect(),
            Ranks: vec![0; count],
        }
    }
    fn add(&mut self) -> usize {
        let id = self.Parents.len();
        self.Parents.push(id);
        self.Ranks.push(0);
        id
    }
    fn find(&mut self, mut index: usize) -> usize {
        let mut root = index;
        while self.Parents[root] != root {
            root = self.Parents[root];
        }
        while self.Parents[index] != index {
            let next = self.Parents[index];
            self.Parents[index] = root;
            index = next;
        }
        root
    }
    fn unite(&mut self, left: usize, right: usize) {
        let (mut left, mut right) = (self.find(left), self.find(right));
        if left == right {
            return;
        }
        if self.Ranks[left] < self.Ranks[right] {
            std::mem::swap(&mut left, &mut right);
        }
        self.Parents[right] = left;
        if self.Ranks[left] == self.Ranks[right] {
            self.Ranks[left] += 1;
        }
    }
}
#[derive(Clone, Copy, Default)]
struct ComponentState {
    High: i32,
    Delta: i32,
    Rising: i32,
    Next: i32,
    Stamp: u32,
}
#[derive(Clone, Copy, Default)]
struct ConnectorState {
    High: i32,
    Delta: i32,
    Stamp: u32,
}
#[derive(Clone, Copy, Default)]
struct Component {
    Kind: u8,
    Hold: i32,
    Initial: u8,
}
#[derive(Default)]
struct Port {
    First: usize,
    Sources: Vec<usize>,
    Targets: Vec<usize>,
    Peers: Vec<usize>,
    TraceIds: Vec<usize>,
}
fn isTrace(kind: i32) -> bool {
    matches!(kind, 1..=6 | 28..=29)
}
fn isBus(kind: i32) -> bool {
    (7..=12).contains(&kind)
}
fn isDevice(kind: i32) -> bool {
    (17..=27).contains(&kind)
}
fn color(kind: i32) -> usize {
    match kind {
        1..=6 => kind as usize - 1,
        28..=29 => kind as usize - 22,
        _ => usize::MAX,
    }
}
fn unique(values: &mut Vec<usize>, value: usize) {
    if !values.contains(&value) {
        values.push(value);
    }
}
fn dedup(values: &mut [Vec<usize>]) {
    for value in values {
        value.sort_unstable();
        value.dedup();
    }
}
fn incoming(outgoing: &[Vec<usize>]) -> Vec<Vec<usize>> {
    let mut result = vec![vec![]; outgoing.len()];
    for (source, targets) in outgoing.iter().enumerate() {
        for &target in targets {
            result[target].push(source);
        }
    }
    result
}
fn flatten(adjacency: &[Vec<usize>]) -> (Vec<usize>, Vec<usize>) {
    let mut offsets = Vec::with_capacity(adjacency.len() + 1);
    let mut targets = Vec::new();
    for edges in adjacency {
        offsets.push(targets.len());
        targets.extend_from_slice(edges);
    }
    offsets.push(targets.len());
    (offsets, targets)
}
fn condense(count: usize, edges: &[(usize, usize)]) -> (Vec<usize>, usize) {
    let mut out = vec![vec![]; count];
    for &(a, b) in edges {
        out[a].push(b);
    }
    dedup(&mut out);
    let inc = incoming(&out);
    let mut visited = vec![false; count];
    let mut finish = Vec::with_capacity(count);
    for start in 0..count {
        if visited[start] {
            continue;
        }
        visited[start] = true;
        let mut stack = vec![(start, 0)];
        while let Some(&(node, cursor)) = stack.last() {
            if cursor < out[node].len() {
                stack.last_mut().unwrap().1 += 1;
                let target = out[node][cursor];
                if !visited[target] {
                    visited[target] = true;
                    stack.push((target, 0));
                }
            } else {
                finish.push(node);
                stack.pop();
            }
        }
    }
    let mut map = vec![usize::MAX; count];
    let mut minimum = vec![];
    for &start in finish.iter().rev() {
        if map[start] != usize::MAX {
            continue;
        }
        let id = minimum.len();
        let mut low = start;
        map[start] = id;
        let mut stack = vec![start];
        while let Some(node) = stack.pop() {
            low = low.min(node);
            for &source in &inc[node] {
                if map[source] == usize::MAX {
                    map[source] = id;
                    stack.push(source);
                }
            }
        }
        minimum.push(low);
    }
    let mut order: Vec<usize> = (0..minimum.len()).collect();
    order.sort_unstable_by_key(|&i| minimum[i]);
    let mut remap = vec![0; order.len()];
    for (id, old) in order.into_iter().enumerate() {
        remap[old] = id;
    }
    for id in &mut map {
        *id = remap[*id];
    }
    (map, minimum.len())
}

/// The worker owns the core. All tick buffers are allocated at compile time.
#[derive(Default)]
pub struct SimulationCore {
    pub Width: usize,
    pub Height: usize,
    pub Tick: u64,
    pub OrderingApplied: bool,
    pub LocalityScore: u64,
    SnapshotComponents: Buffer<usize>,
    Components: Vec<Component>,
    CellComponents: Buffer<usize>,
    Offsets: Buffer<usize>,
    Targets: Buffer<usize>,
    ComponentEnds: Buffer<isize>,
    CellOffsets: Buffer<usize>,
    CellNodes: Buffer<usize>,
    VisibleOffsets: Buffer<usize>,
    VisibleCells: Buffer<usize>,
    HasVisible: Buffer<bool>,
    States: Buffer<u8>,
    Visible: Buffer<u8>,
    Reported: Buffer<u8>,
    InputCounts: Buffer<i32>,
    Phases: Buffer<i32>,
    Clocks: Buffer<usize>,
    Modes: Buffer<u8>,
    NextWords: Buffer<u64>,
    CurrentWords: Buffer<u64>,
    NextSummary: Buffer<u64>,
    CurrentSummary: Buffer<u64>,
    NextStates: Buffer<u8>,
    CurrentStates: Buffer<u8>,
    NextActive: Vec<usize>,
    CurrentActive: Vec<usize>,
    ComponentRuntime: Buffer<ComponentState>,
    ConnectorRuntime: Buffer<ConnectorState>,
    PendingHeads: [usize; 8],
    PendingTails: [usize; 8],
    Stamp: u32,
    ConnectorWords: Buffer<u64>,
    ConnectorSummary: Buffer<u64>,
    Dirty: Vec<usize>,
    DirtyFlags: Buffer<bool>,
    DirtyInitial: Buffer<u8>,
    Changed: Vec<usize>,
    ChangedFlags: Buffer<bool>,
    CellFlags: Buffer<u32>,
    CellStamp: u32,
    Deferred: bool,
    Signature: u64,
    Compiled: bool,
}
impl SimulationCore {
    pub fn compile(input: CompileInput) -> Result<Self, CompileError> {
        Self::compileWithOrdering(input, true)
    }
    pub fn compileWithOrdering(input: CompileInput, ordering: bool) -> Result<Self, CompileError> {
        let (width, height) = (input.Width, input.Height);
        let count = width
            .checked_mul(height)
            .filter(|&n| n <= MaximumCellCount)
            .ok_or_else(|| CompileError::new(None, 1, "grid_too_large"))?;
        let fail = |cell, reason| CompileError::new(cell, width.max(1), reason);
        if width == 0 || height == 0 {
            return Err(fail(None, "invalid_grid_size"));
        }
        if [
            &input.Kinds,
            &input.InitialStates,
            &input.ClockHoldTicks,
            &input.ComponentIds,
        ]
        .iter()
        .any(|v| v.len() != count)
        {
            return Err(fail(None, "array_size_mismatch"));
        }
        let kinds = &input.Kinds;
        let mut signature = 1469598103934665603u64;
        let mut hash = |value: i32| {
            for b in value.to_le_bytes() {
                signature ^= b as u64;
                signature = signature.wrapping_mul(1099511628211);
            }
        };
        hash(width as i32);
        hash(height as i32);
        for cell in 0..count {
            if !matches!(kinds[cell], 0..=13 | 15..=29) {
                return Err(fail(Some(cell), "unknown_kind"));
            }
            if kinds[cell] == 26 && input.ClockHoldTicks[cell] <= 0 {
                return Err(fail(Some(cell), "invalid_clock_hold_ticks"));
            }
            if (kinds[cell] == 0 && input.ComponentIds[cell] != 0)
                || (kinds[cell] != 0 && input.ComponentIds[cell] <= 0)
            {
                return Err(fail(Some(cell), "invalid_component_id"));
            }
            hash(kinds[cell]);
            hash(input.InitialStates[cell]);
            hash(input.ClockHoldTicks[cell]);
            hash(input.ComponentIds[cell]);
        }
        let neighbor = |cell: usize, dx: i32, dy: i32| -> Option<usize> {
            let x = (cell % width) as i32 + dx;
            let y = (cell / width) as i32 + dy;
            if x < 0 || y < 0 || x >= width as i32 || y >= height as i32 {
                None
            } else {
                Some(y as usize * width + x as usize)
            }
        };
        // IDs cannot join disconnected cells or incompatible ink settings.
        let mut samples: HashMap<i32, usize> = HashMap::new();
        let mut visited = vec![false; count];
        for cell in 0..count {
            if kinds[cell] == 0 || visited[cell] {
                continue;
            }
            let id = input.ComponentIds[cell];
            if samples.insert(id, cell).is_some() {
                return Err(fail(Some(cell), "disconnected_component"));
            }
            visited[cell] = true;
            let mut queue = vec![cell];
            while let Some(current) = queue.pop() {
                if kinds[current] != kinds[cell]
                    || (kinds[cell] == 25
                        && (input.InitialStates[current] != 0) != (input.InitialStates[cell] != 0))
                    || (kinds[cell] == 26
                        && input.ClockHoldTicks[current] != input.ClockHoldTicks[cell])
                {
                    return Err(fail(Some(current), "incompatible_component"));
                }
                for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                    if let Some(n) = neighbor(current, dx, dy) {
                        if !visited[n] && input.ComponentIds[n] == id {
                            visited[n] = true;
                            queue.push(n);
                        }
                    }
                }
            }
        }
        drop(samples);
        drop(visited);
        let directions = [(-1, 0), (1, 0), (0, -1), (0, 1)];
        let mut deviceSet = DisjointSet::new(count);
        let mut ports = DisjointSet::new(count);
        let mut conductors = DisjointSet::new(count);
        // A Bus component owns eight anchors, regardless of its number of cells.
        let mut buses: BTreeMap<i32, [usize; 8]> = BTreeMap::new();
        for cell in 0..count {
            if isBus(kinds[cell]) {
                buses
                    .entry(input.ComponentIds[cell])
                    .or_insert_with(|| std::array::from_fn(|_| conductors.add()));
            }
        }
        for cell in 0..count {
            let kind = kinds[cell];
            for (dx, dy) in [(1, 0), (0, 1)] {
                if let Some(n) = neighbor(cell, dx, dy) {
                    if isDevice(kind)
                        && input.ComponentIds[cell] == input.ComponentIds[n]
                        && kinds[n] == kind
                        && (kind != 26 || input.ClockHoldTicks[cell] == input.ClockHoldTicks[n])
                        && (kind != 25
                            || (input.InitialStates[cell] != 0) == (input.InitialStates[n] != 0))
                    {
                        deviceSet.unite(cell, n);
                    }
                    if (kind == 15 || kind == 16)
                        && kinds[n] == kind
                        && input.ComponentIds[cell] == input.ComponentIds[n]
                    {
                        ports.unite(cell, n);
                    }
                    if isTrace(kind)
                        && kinds[n] == kind
                        && input.ComponentIds[cell] == input.ComponentIds[n]
                    {
                        conductors.unite(cell, n);
                    } else if isTrace(kind) && isBus(kinds[n]) {
                        conductors.unite(cell, buses[&input.ComponentIds[n]][color(kind)]);
                    } else if isBus(kind) && isTrace(kinds[n]) {
                        conductors.unite(buses[&input.ComponentIds[cell]][color(kinds[n])], n);
                    }
                }
            }
        }
        let mut components = vec![];
        let mut byRoot = HashMap::new();
        let mut cellComponents = vec![usize::MAX; count];
        for cell in 0..count {
            if isDevice(kinds[cell]) {
                let next = components.len();
                let id = *byRoot.entry(deviceSet.find(cell)).or_insert(next);
                if id == next {
                    components.push(Component {
                        Kind: kinds[cell] as u8,
                        Hold: if kinds[cell] == 26 {
                            input.ClockHoldTicks[cell]
                        } else {
                            0
                        },
                        Initial: (input.InitialStates[cell] != 0) as u8,
                    });
                }
                cellComponents[cell] = id;
            }
        }
        drop(deviceSet);
        drop(byRoot);
        // Cross cells have independent horizontal and vertical channels for every signal color.
        let mut cross = HashMap::new();
        for (cell, &kind) in kinds.iter().enumerate() {
            if kind == 13 {
                let mut channels = [0; 16];
                for anchor in &mut channels {
                    *anchor = conductors.add();
                }
                cross.insert(cell, channels);
            }
        }
        for (&cell, channels) in &cross {
            for orientation in 0..2 {
                let dirs = if orientation == 0 {
                    [(-1, 0), (1, 0)]
                } else {
                    [(0, -1), (0, 1)]
                };
                for c in 0..8 {
                    for (dx, dy) in dirs {
                        if let Some(n) = neighbor(cell, dx, dy) {
                            if isTrace(kinds[n]) && color(kinds[n]) == c {
                                conductors.unite(channels[orientation * 8 + c], n);
                            } else if isBus(kinds[n]) {
                                conductors.unite(
                                    channels[orientation * 8 + c],
                                    buses[&input.ComponentIds[n]][c],
                                );
                            } else if let Some(other) = cross
                                .get(&n)
                                .filter(|_| input.ComponentIds[cell] == input.ComponentIds[n])
                            {
                                conductors.unite(
                                    channels[orientation * 8 + c],
                                    other[orientation * 8 + c],
                                );
                            }
                        }
                    }
                }
            }
        }
        let mut networkRoots = HashMap::new();
        let mut networkByCell = vec![usize::MAX; count];
        let mut getNetwork = |node: usize| {
            if node == usize::MAX {
                return node;
            }
            let next = networkRoots.len();
            *networkRoots.entry(conductors.find(node)).or_insert(next)
        };
        for cell in 0..count {
            if isTrace(kinds[cell]) {
                networkByCell[cell] = getNetwork(cell);
            }
            if let Some(channels) = cross.get_mut(&cell) {
                for n in channels {
                    *n = getNetwork(*n);
                }
            }
        }
        for channels in buses.values_mut() {
            for anchor in channels {
                *anchor = getNetwork(*anchor);
            }
        }
        drop(getNetwork);
        let networkCount = networkRoots.len();
        let mut networkHasBus = vec![false; networkCount];
        for channels in buses.values() {
            for &network in channels {
                networkHasBus[network] = true;
            }
        }
        drop(networkRoots);
        drop(conductors);
        let mut reads: Vec<Port> = vec![];
        let mut writes: Vec<Port> = vec![];
        let mut readByCell = vec![usize::MAX; count];
        let mut writeByCell = vec![usize::MAX; count];
        let mut readRoots = HashMap::new();
        let mut writeRoots = HashMap::new();
        for cell in 0..count {
            let (bindings, roots, indices) = match kinds[cell] {
                15 => (&mut reads, &mut readRoots, &mut readByCell),
                16 => (&mut writes, &mut writeRoots, &mut writeByCell),
                _ => continue,
            };
            let next = bindings.len();
            let id = *roots.entry(ports.find(cell)).or_insert(next);
            if id == next {
                bindings.push(Port {
                    First: cell,
                    ..Default::default()
                });
            }
            indices[cell] = id;
        }
        for cell in 0..count {
            if kinds[cell] != 15 && kinds[cell] != 16 {
                continue;
            }
            for (dx, dy) in directions {
                if let Some(n) = neighbor(cell, dx, dy) {
                    let nk = kinds[n];
                    if kinds[cell] == 15 {
                        let b = &mut reads[readByCell[cell]];
                        if isTrace(nk) {
                            unique(&mut b.Targets, networkByCell[n]);
                            unique(&mut b.TraceIds, input.ComponentIds[n] as usize);
                        } else if isDevice(nk) {
                            unique(&mut b.Sources, cellComponents[n]);
                        }
                    } else {
                        let b = &mut writes[writeByCell[cell]];
                        if isTrace(nk) {
                            unique(&mut b.Sources, networkByCell[n]);
                            unique(&mut b.TraceIds, input.ComponentIds[n] as usize);
                        } else if nk == 15 {
                            unique(&mut b.Peers, readByCell[n]);
                        } else if isDevice(nk) && nk != 26 {
                            unique(&mut b.Targets, cellComponents[n]);
                        }
                    }
                }
            }
        }
        let mut drivers = vec![None; networkCount];
        for (id, binding) in reads.iter().enumerate() {
            if binding.TraceIds.len() != 1 {
                return Err(fail(Some(binding.First), "read_requires_one_trace_sink"));
            }
            let network = binding.Targets[0];
            if networkHasBus[network] && drivers[network].replace(id).is_some() {
                return Err(fail(Some(binding.First), "bus_channel_multiple_reads"));
            }
        }
        for binding in &writes {
            if binding.TraceIds.len() != 1 {
                return Err(fail(Some(binding.First), "write_requires_one_trace_source"));
            }
        }
        let componentCount = components.len();
        let rawCount = networkCount + reads.len() + writes.len();
        let mut edges = vec![];
        let readNode = |r: usize| componentCount + networkCount + r;
        let writeNode = |w: usize| componentCount + networkCount + reads.len() + w;
        for (r, b) in reads.iter().enumerate() {
            for &source in &b.Sources {
                edges.push((source, readNode(r)));
            }
            for &target in &b.Targets {
                edges.push((readNode(r), componentCount + target));
            }
        }
        for (w, b) in writes.iter().enumerate() {
            for &source in &b.Sources {
                edges.push((componentCount + source, writeNode(w)));
            }
            for &r in &b.Peers {
                edges.push((writeNode(w), readNode(r)));
            }
            for &target in &b.Targets {
                edges.push((writeNode(w), target));
            }
        }
        edges.sort_unstable();
        edges.dedup();
        let connectorEdges: Vec<_> = edges
            .iter()
            .filter(|&&(s, t)| s >= componentCount && t >= componentCount)
            .map(|&(s, t)| (s - componentCount, t - componentCount))
            .collect();
        let (condensation, connectorCount) = condense(rawCount, &connectorEdges);
        let nodeCount = componentCount + connectorCount;
        let mapRaw = |raw: usize| {
            if raw < componentCount {
                raw
            } else {
                componentCount + condensation[raw - componentCount]
            }
        };
        let mut outgoing = vec![vec![]; nodeCount];
        for &(s, t) in &edges {
            let (s, t) = (mapRaw(s), mapRaw(t));
            if s != t {
                outgoing[s].push(t);
            }
        }
        dedup(&mut outgoing);
        let mut inc = incoming(&outgoing);
        let mut aliases: Vec<usize> = (0..nodeCount).collect();
        // Preserve multiplicity: a transparent port may be bypassed only if no direct edge already exists.
        for node in componentCount..nodeCount {
            if outgoing[node].is_empty() && inc[node].len() == 1 {
                let source = inc[node][0];
                aliases[node] = source;
                outgoing[source].retain(|&v| v != node);
            }
        }
        inc = incoming(&outgoing);
        let mut candidates: Vec<_> = (componentCount..nodeCount)
            .filter(|&n| outgoing[n].len() == 1 && inc[n].len() == 1)
            .collect();
        let mut cursor = 0;
        while cursor < candidates.len() {
            let node = candidates[cursor];
            cursor += 1;
            if outgoing[node].len() != 1 || inc[node].len() != 1 {
                continue;
            }
            let (source, target) = (inc[node][0], outgoing[node][0]);
            if source == target || outgoing[source].contains(&target) {
                continue;
            }
            aliases[node] = source;
            outgoing[source].retain(|&v| v != node);
            outgoing[source].push(target);
            outgoing[source].sort_unstable();
            outgoing[node].clear();
            inc[node].clear();
            inc[target].retain(|&v| v != node);
            inc[target].push(source);
            inc[target].sort_unstable();
            if source >= componentCount {
                candidates.push(source);
            }
            if target >= componentCount {
                candidates.push(target);
            }
        }
        let (ordered, orderingApplied, localityScore) =
            crate::GraphLocalityOrderer::executionOrder(&outgoing, componentCount, ordering)
                .ok_or_else(|| fail(None, "connector_cycle"))?;
        let mut remap = vec![0; nodeCount];
        for (new, &old) in ordered.iter().enumerate() {
            remap[old] = new;
        }
        let resolve = |mut node: usize| {
            while aliases[node] != node {
                node = aliases[node];
            }
            remap[node]
        };
        let mut visibleNodes = vec![vec![]; count];
        for cell in 0..count {
            let nodes = &mut visibleNodes[cell];
            match kinds[cell] {
                1..=6 | 28..=29 => {
                    nodes.push(resolve(mapRaw(componentCount + networkByCell[cell])))
                }
                7..=12 => {
                    for &network in &buses[&input.ComponentIds[cell]] {
                        unique(nodes, resolve(mapRaw(componentCount + network)));
                    }
                }
                13 => {
                    for &n in &cross[&cell] {
                        unique(nodes, resolve(mapRaw(componentCount + n)));
                    }
                }
                15 => nodes.push(resolve(mapRaw(readNode(readByCell[cell])))),
                16 => nodes.push(resolve(mapRaw(writeNode(writeByCell[cell])))),
                17..=27 => nodes.push(remap[cellComponents[cell]]),
                _ => {}
            }
        }
        let mut runtimeOut = vec![vec![]; nodeCount];
        for (old, targets) in outgoing.iter().enumerate() {
            for &t in targets {
                runtimeOut[remap[old]].push(remap[t]);
            }
        }
        dedup(&mut runtimeOut);
        let runtimeInc = incoming(&runtimeOut);
        let (offsets, mut targets) = flatten(&runtimeOut);
        let mut ends = vec![0; nodeCount];
        for node in 0..nodeCount {
            let start = offsets[node];
            let end = offsets[node + 1];
            let boundary = start + runtimeOut[node].partition_point(|&n| n < componentCount);
            ends[node] = if boundary == start + 1 && boundary == end {
                -(targets[start] as isize) - 1
            } else {
                boundary as isize
            };
            for t in &mut targets[boundary..end] {
                *t -= componentCount;
            }
        }
        let (cellOffsets, cellNodes) = flatten(&visibleNodes);
        let mut cellsByNode = vec![vec![]; nodeCount];
        for (cell, nodes) in visibleNodes.iter().enumerate() {
            for &node in nodes {
                cellsByNode[node].push(cell);
            }
        }
        let (visibleOffsets, visibleCells) = flatten(&cellsByNode);
        let inputCounts: Vec<i32> = runtimeInc[..componentCount]
            .iter()
            .map(|v| v.len() as i32)
            .collect();

        let snapshotComponents = remap[..componentCount].to_vec();
        for component in &mut cellComponents {
            if *component != usize::MAX {
                *component = remap[*component];
            }
        }
        components = ordered[..componentCount]
            .iter()
            .map(|&old| components[old])
            .collect();
        let modes: Vec<u8> = components
            .iter()
            .enumerate()
            .map(|(i, c)| match c.Kind {
                17 | 19 | 27 => 1,
                21 | 23 => 2,
                18 => {
                    if inputCounts[i] == 1 {
                        1
                    } else {
                        3
                    }
                }
                22 => {
                    if inputCounts[i] == 1 {
                        2
                    } else {
                        4
                    }
                }
                20 => {
                    if inputCounts[i] == 1 {
                        1
                    } else {
                        5
                    }
                }
                24 => {
                    if inputCounts[i] == 1 {
                        2
                    } else {
                        6
                    }
                }
                25 => 7,
                _ => 0,
            })
            .collect();
        let clocks = components
            .iter()
            .enumerate()
            .filter(|(_, c)| c.Kind == 26)
            .map(|(i, _)| i)
            .collect();
        let wordCount = componentCount.div_ceil(64);
        let connectorWordCount = connectorCount.div_ceil(64);
        let runtimeBytes = nodeCount * 128
            + count * 48
            + targets.len() * 16
            + cellNodes.len() * 16
            + visibleCells.len() * 16
            + 4096;
        let mut arena = Arena::new(runtimeBytes);
        let hasVisible = visibleOffsets.windows(2).map(|w| w[0] != w[1]).collect();
        let mut core = Self {
            Width: width,
            Height: height,
            OrderingApplied: orderingApplied,
            LocalityScore: localityScore,
            SnapshotComponents: arena.take(snapshotComponents),
            Components: components,
            CellComponents: arena.take(cellComponents),
            Offsets: arena.take(offsets),
            Targets: arena.take(targets),
            ComponentEnds: arena.take(ends),
            CellOffsets: arena.take(cellOffsets),
            CellNodes: arena.take(cellNodes),
            VisibleOffsets: arena.take(visibleOffsets),
            VisibleCells: arena.take(visibleCells),
            HasVisible: arena.take(hasVisible),
            States: arena.take(vec![0; nodeCount]),
            Visible: arena.take(vec![0; count]),
            Reported: arena.take(vec![0; count]),
            InputCounts: arena.take(inputCounts),
            Phases: arena.take(vec![0; componentCount]),
            Clocks: arena.take(clocks),
            Modes: arena.take(modes),
            NextWords: arena.take(vec![0; wordCount]),
            CurrentWords: arena.take(vec![0; wordCount]),
            NextSummary: arena.take(vec![0; wordCount.div_ceil(64)]),
            CurrentSummary: arena.take(vec![0; wordCount.div_ceil(64)]),
            NextStates: arena.take(vec![0; componentCount]),
            CurrentStates: arena.take(vec![0; componentCount]),
            NextActive: Vec::with_capacity(wordCount),
            CurrentActive: Vec::with_capacity(wordCount),
            ComponentRuntime: arena.take(vec![ComponentState::default(); componentCount]),
            ConnectorRuntime: arena.take(vec![ConnectorState::default(); connectorCount]),
            PendingHeads: [usize::MAX; 8],
            PendingTails: [usize::MAX; 8],
            Stamp: 1,
            ConnectorWords: arena.take(vec![0; connectorWordCount]),
            ConnectorSummary: arena.take(vec![0; connectorWordCount.div_ceil(64)]),
            Dirty: Vec::with_capacity(nodeCount),
            DirtyFlags: arena.take(vec![false; nodeCount]),
            DirtyInitial: arena.take(vec![0; nodeCount]),
            Changed: Vec::with_capacity(count),
            ChangedFlags: arena.take(vec![false; count]),
            CellFlags: arena.take(vec![0; count]),
            CellStamp: 1,
            Signature: signature,
            Compiled: true,
            ..Default::default()
        };
        core.resetSilent();
        core.materialize();
        core.Reported.copy_from_slice(&core.Visible);
        core.clearChanges();
        Ok(core)
    }
    #[inline(always)]
    fn evaluate(&self, node: usize, high: i32) -> u8 {
        match self.Modes[node] {
            1 => (high != 0) as u8,
            2 => (high == 0) as u8,
            3 => (high != 0 && high == self.InputCounts[node]) as u8,
            4 => (high == 0 || high != self.InputCounts[node]) as u8,
            5 => (high & 1) as u8,
            6 => ((high & 1) == 0) as u8,
            _ => self.States[node],
        }
    }
    #[inline(always)]
    fn setState(&mut self, node: usize, state: u8) {
        if self.States[node] == state {
            return;
        }
        if self.HasVisible[node] && !self.DirtyFlags[node] {
            self.DirtyFlags[node] = true;
            self.DirtyInitial[node] = self.States[node];
            self.Dirty.push(node);
        }
        self.States[node] = state;
    }
    #[inline(always)]
    fn enqueue(&mut self, node: usize, state: u8) {
        self.NextStates[node] = state;
        let word = node / 64;
        if self.NextWords[word] == 0 {
            let summary = word / 64;
            if self.NextSummary[summary] == 0 {
                self.NextActive.push(summary);
            }
            self.NextSummary[summary] |= 1u64 << (word % 64);
        }
        self.NextWords[word] |= 1u64 << (node % 64);
    }
    #[inline(always)]
    fn accumulateComponent(&mut self, node: usize, delta: i32) {
        let pending = &mut self.ComponentRuntime[node];
        if pending.Stamp == self.Stamp {
            pending.Delta += delta;
            if self.Modes[node] == 7 && delta > 0 {
                pending.Rising += 1;
            }
            return;
        }
        pending.Stamp = self.Stamp;
        pending.Delta = delta;
        pending.Rising = if self.Modes[node] == 7 && delta > 0 {
            1
        } else {
            0
        };
        pending.Next = -1;
        let mode = self.Modes[node] as usize;
        let tail = self.PendingTails[mode];
        if tail == usize::MAX {
            self.PendingHeads[mode] = node;
        } else {
            self.ComponentRuntime[tail].Next = node as i32;
        }
        self.PendingTails[mode] = node;
    }
    #[inline(always)]
    fn accumulateConnector(&mut self, rank: usize, delta: i32) {
        let pending = &mut self.ConnectorRuntime[rank];
        if pending.Stamp == self.Stamp {
            pending.Delta += delta;
            return;
        }
        pending.Stamp = self.Stamp;
        pending.Delta = delta;
        let word = rank / 64;
        self.ConnectorWords[word] |= 1u64 << (rank % 64);
        self.ConnectorSummary[word / 64] |= 1u64 << (word % 64);
    }
    #[inline(always)]
    fn seed(&mut self, node: usize, delta: i32) {
        let boundary = self.ComponentEnds[node];
        if boundary < 0 {
            self.accumulateComponent((-boundary - 1) as usize, delta);
            return;
        }
        let start = self.Offsets[node];
        let end = self.Offsets[node + 1];
        for edge in start..boundary as usize {
            self.accumulateComponent(self.Targets[edge], delta);
        }
        for edge in boundary as usize..end {
            self.accumulateConnector(self.Targets[edge], delta);
        }
    }
    fn begin(&mut self) {
        self.PendingHeads.fill(usize::MAX);
        self.PendingTails.fill(usize::MAX);
        self.Stamp = self.Stamp.wrapping_add(1);
        if self.Stamp == 0 {
            for pending in self.ComponentRuntime.iter_mut() {
                pending.Stamp = 0;
            }
            for pending in self.ConnectorRuntime.iter_mut() {
                pending.Stamp = 0;
            }
            self.Stamp = 1;
        }
    }
    #[inline(always)]
    fn active<const MODE: u8>(&self, node: usize, high: i32) -> u8 {
        match MODE {
            1 => (high != 0) as u8,
            2 => (high == 0) as u8,
            3 => (high != 0 && high == self.InputCounts[node]) as u8,
            4 => (high == 0 || high != self.InputCounts[node]) as u8,
            5 => (high & 1) as u8,
            6 => ((high & 1) == 0) as u8,
            _ => self.States[node],
        }
    }
    #[inline(always)]
    fn flush<const MODE: u8, const QUEUED: bool>(&mut self, suppressLatch: bool) {
        let mut node = self.PendingHeads[MODE as usize];
        while node != usize::MAX {
            let pending = self.ComponentRuntime[node];
            let previous = self.ComponentRuntime[node].High;
            self.ComponentRuntime[node].High += pending.Delta;
            if MODE == 7 {
                if !suppressLatch && (pending.Rising & 1) != 0 {
                    let queued = QUEUED && self.NextWords[node / 64] & (1u64 << (node % 64)) != 0;
                    let base = if queued {
                        self.NextStates[node]
                    } else {
                        self.States[node]
                    };
                    self.enqueue(node, 1 - base);
                }
            } else if QUEUED {
                let queued = self.NextWords[node / 64] & (1u64 << (node % 64)) != 0;
                if pending.Delta != 0 || queued {
                    let next = self.active::<MODE>(node, self.ComponentRuntime[node].High);
                    if queued || next != self.States[node] {
                        self.enqueue(node, next);
                    }
                }
            } else if MODE != 0 && pending.Delta != 0 {
                let high = self.ComponentRuntime[node].High;
                let changed = match MODE {
                    1 | 2 => (previous != 0) != (high != 0),
                    3 | 4 => {
                        (previous != 0 && previous == self.InputCounts[node])
                            != (high != 0 && high == self.InputCounts[node])
                    }
                    5 | 6 => (pending.Delta & 1) != 0,
                    _ => false,
                };
                if changed {
                    self.enqueue(node, self.active::<MODE>(node, high));
                }
            }
            node = if pending.Next < 0 {
                usize::MAX
            } else {
                pending.Next as usize
            };
        }
    }
    fn finish<const QUEUED: bool>(&mut self, suppressLatch: bool) {
        for summary in 0..self.ConnectorSummary.len() {
            while self.ConnectorSummary[summary] != 0 {
                let word = summary * 64 + self.ConnectorSummary[summary].trailing_zeros() as usize;
                while self.ConnectorWords[word] != 0 {
                    let bit = self.ConnectorWords[word].trailing_zeros() as usize;
                    self.ConnectorWords[word] &= self.ConnectorWords[word] - 1;
                    let rank = word * 64 + bit;
                    let node = self.Components.len() + rank;
                    let delta = self.ConnectorRuntime[rank].Delta;
                    if delta == 0 {
                        continue;
                    }
                    let previous = self.ConnectorRuntime[rank].High;
                    self.ConnectorRuntime[rank].High += delta;
                    let next = (self.ConnectorRuntime[rank].High != 0) as u8;
                    if (previous != 0) as u8 != next {
                        self.setState(node, next);
                        self.seed(node, if next != 0 { 1 } else { -1 });
                    }
                }
                self.ConnectorSummary[summary] &= !(1u64 << (word % 64));
            }
        }
        self.flush::<0, QUEUED>(suppressLatch);
        self.flush::<1, QUEUED>(suppressLatch);
        self.flush::<2, QUEUED>(suppressLatch);
        self.flush::<3, QUEUED>(suppressLatch);
        self.flush::<4, QUEUED>(suppressLatch);
        self.flush::<5, QUEUED>(suppressLatch);
        self.flush::<6, QUEUED>(suppressLatch);
        self.flush::<7, QUEUED>(suppressLatch);
    }
    fn materialize(&mut self) {
        self.CellStamp = self.CellStamp.wrapping_add(1);
        if self.CellStamp == 0 {
            self.CellFlags.fill(0);
            self.CellStamp = 1;
        }
        for i in 0..self.Dirty.len() {
            let node = self.Dirty[i];
            self.DirtyFlags[node] = false;
            if self.DirtyInitial[node] == self.States[node] {
                continue;
            }
            for edge in self.VisibleOffsets[node]..self.VisibleOffsets[node + 1] {
                let cell = self.VisibleCells[edge];
                if self.CellFlags[cell] == self.CellStamp {
                    continue;
                }
                self.CellFlags[cell] = self.CellStamp;
                let state = self.CellNodes[self.CellOffsets[cell]..self.CellOffsets[cell + 1]]
                    .iter()
                    .any(|&n| self.States[n] != 0) as u8;
                if self.Visible[cell] != state {
                    self.Visible[cell] = state;
                    if !self.ChangedFlags[cell] {
                        self.ChangedFlags[cell] = true;
                        self.Changed.push(cell);
                    }
                }
            }
        }
        self.Dirty.clear();
    }
    fn clearChanges(&mut self) {
        for &cell in &self.Changed {
            self.ChangedFlags[cell] = false;
        }
        self.Changed.clear();
    }
    pub fn states(&mut self) -> &[u8] {
        self.materialize();
        &self.Visible
    }
    pub fn drain(&mut self) -> Vec<i32> {
        self.materialize();
        self.Changed.sort_unstable();
        let mut result = Vec::with_capacity(self.Changed.len() * 2);
        for &cell in &self.Changed {
            if self.Visible[cell] != self.Reported[cell] {
                result.push(cell as i32);
                result.push(self.Visible[cell] as i32);
            }
            self.Reported[cell] = self.Visible[cell];
        }
        self.clearChanges();
        result
    }
    pub fn probeCapacity(&mut self) -> f64 {
        let snapshot = self.capture();
        let start = std::time::Instant::now();
        let mut ticks = 0u64;
        while start.elapsed() < std::time::Duration::from_millis(20) && ticks < 1_048_576 {
            self.advanceSilent(16);
            ticks += 16;
        }
        self.drain();
        let rate = ticks as f64 / start.elapsed().as_secs_f64();
        self.restore(&snapshot).expect("own capacity snapshot");
        rate.max(1.)
    }
    pub fn beginDeferred(&mut self) -> bool {
        if !self.Compiled || self.Deferred {
            return false;
        }
        self.materialize();
        self.Reported.copy_from_slice(&self.Visible);
        self.clearChanges();
        self.Deferred = true;
        true
    }
    pub fn endDeferred(&mut self) {
        if !self.Deferred {
            return;
        }
        self.materialize();
        for &cell in &self.Changed {
            self.Reported[cell] = self.Visible[cell];
        }
        self.clearChanges();
        self.Deferred = false;
    }
    pub fn advanceSilent(&mut self, ticks: i32) {
        if !self.Compiled {
            return;
        }
        for _ in 0..ticks.max(0) {
            std::mem::swap(&mut self.NextWords, &mut self.CurrentWords);
            std::mem::swap(&mut self.NextSummary, &mut self.CurrentSummary);
            std::mem::swap(&mut self.NextStates, &mut self.CurrentStates);
            std::mem::swap(&mut self.NextActive, &mut self.CurrentActive);
            for &summary in &self.NextActive {
                let mut bits = self.NextSummary[summary];
                while bits != 0 {
                    let word = summary * 64 + bits.trailing_zeros() as usize;
                    bits &= bits - 1;
                    self.NextWords[word] = 0;
                }
                self.NextSummary[summary] = 0;
            }
            self.NextActive.clear();
            self.begin();
            for i in 0..self.CurrentActive.len() {
                let summary = self.CurrentActive[i];
                let mut words = self.CurrentSummary[summary];
                while words != 0 {
                    let word = summary * 64 + words.trailing_zeros() as usize;
                    words &= words - 1;
                    let mut gates = self.CurrentWords[word];
                    while gates != 0 {
                        let node = word * 64 + gates.trailing_zeros() as usize;
                        gates &= gates - 1;
                        let next = self.CurrentStates[node];
                        if next != self.States[node] {
                            self.setState(node, next);
                            self.seed(node, if next != 0 { 1 } else { -1 });
                        }
                    }
                }
            }
            for i in 0..self.Clocks.len() {
                let node = self.Clocks[i];
                self.Phases[node] += 1;
                if self.Phases[node] >= self.Components[node].Hold {
                    self.Phases[node] = 0;
                    let next = 1 - self.States[node];
                    self.setState(node, next);
                    self.seed(node, if next != 0 { 1 } else { -1 });
                }
            }
            self.finish::<false>(false);
            self.Tick = self.Tick.wrapping_add(1);
        }
    }
    pub fn advance(&mut self, ticks: i32) -> Vec<i32> {
        if ticks <= 0 || !self.Compiled {
            return vec![];
        }
        self.advanceSilent(ticks);
        self.drain()
    }
    pub fn toggleLatch(&mut self, cell: usize) -> Result<(), String> {
        if !self.Compiled {
            return Err("simulation_not_compiled".into());
        }
        let node = *self.CellComponents.get(cell).ok_or("cell_out_of_bounds")?;
        if node == usize::MAX || self.Components[node].Kind != 25 {
            return Err("not_latch".into());
        }
        let next = 1 - self.States[node];
        self.setState(node, next);
        if self.NextWords[node / 64] & (1u64 << (node % 64)) != 0 {
            self.NextStates[node] = 1 - self.NextStates[node];
        }
        self.begin();
        self.seed(node, if next != 0 { 1 } else { -1 });
        self.finish::<true>(false);
        Ok(())
    }
    pub fn resetSilent(&mut self) {
        if !self.Compiled {
            return;
        }
        self.Tick = 0;
        self.Phases.fill(0);
        self.ComponentRuntime.fill(ComponentState::default());
        self.ConnectorRuntime.fill(ConnectorState::default());
        self.NextWords.fill(0);
        self.CurrentWords.fill(0);
        self.NextSummary.fill(0);
        self.CurrentSummary.fill(0);
        self.NextActive.clear();
        self.CurrentActive.clear();
        self.NextStates.fill(0);
        self.CurrentStates.fill(0);
        for node in 0..self.States.len() {
            self.setState(node, 0);
        }
        for node in 0..self.Components.len() {
            let state = match self.Components[node].Kind {
                25 => self.Components[node].Initial,
                26 => 0,
                _ => self.evaluate(node, 0),
            };
            self.setState(node, state);
        }
        self.begin();
        for node in 0..self.Components.len() {
            if self.States[node] != 0 {
                self.seed(node, 1);
            }
        }
        self.finish::<true>(true);
    }
    pub fn capture(&self) -> Snapshot {
        Snapshot {
            Signature: self.Signature,
            Tick: self.Tick,
            States: self
                .SnapshotComponents
                .iter()
                .map(|&n| self.States[n])
                .collect(),
            Phases: self
                .SnapshotComponents
                .iter()
                .map(|&n| self.Phases[n])
                .collect(),
            Queued: self
                .SnapshotComponents
                .iter()
                .map(|&n| {
                    if self.NextWords[n / 64] & (1u64 << (n % 64)) != 0 {
                        self.NextStates[n] + 1
                    } else {
                        0
                    }
                })
                .collect(),
        }
    }
    pub fn restore(&mut self, snapshot: &Snapshot) -> Result<(), String> {
        if !self.Compiled {
            return Err("simulation_not_compiled".into());
        }
        if snapshot.Signature != self.Signature || snapshot.States.len() != self.Components.len() {
            return Err("snapshot_topology_mismatch".into());
        }
        if snapshot.Phases.len() != self.Components.len()
            || snapshot.Queued.len() != self.Components.len()
            || snapshot.States.iter().any(|&s| s > 1)
            || snapshot.Queued.iter().any(|&s| s > 2)
            || snapshot.Phases.iter().enumerate().any(|(n, &p)| {
                p < 0
                    || (self.Components[self.SnapshotComponents[n]].Kind == 26
                        && p >= self.Components[self.SnapshotComponents[n]].Hold)
            })
        {
            return Err("invalid_snapshot_state".into());
        }
        self.ComponentRuntime.fill(ComponentState::default());
        self.ConnectorRuntime.fill(ConnectorState::default());
        self.States.fill(0);
        self.NextWords.fill(0);
        self.CurrentWords.fill(0);
        self.NextSummary.fill(0);
        self.CurrentSummary.fill(0);
        self.NextActive.clear();
        self.CurrentActive.clear();
        self.NextStates.fill(0);
        self.CurrentStates.fill(0);
        for (i, &node) in self.SnapshotComponents.iter().enumerate() {
            self.States[node] = snapshot.States[i];
        }
        self.begin();
        for node in 0..self.Components.len() {
            if self.States[node] != 0 {
                self.seed(node, 1);
            }
        }
        self.finish::<true>(true);
        self.NextWords.fill(0);
        self.NextSummary.fill(0);
        self.NextActive.clear();
        for (node, &queued) in snapshot.Queued.iter().enumerate() {
            if queued != 0 {
                self.enqueue(self.SnapshotComponents[node], queued - 1);
            }
        }
        self.Dirty.clear();
        self.DirtyFlags.fill(false);
        for node in 0..self.States.len() {
            self.Dirty.push(node);
            self.DirtyFlags[node] = true;
            self.DirtyInitial[node] = 2;
        }
        self.materialize();
        self.Reported.copy_from_slice(&self.Visible);
        self.clearChanges();
        for (i, &node) in self.SnapshotComponents.iter().enumerate() {
            self.Phases[node] = snapshot.Phases[i];
        }
        self.Tick = snapshot.Tick;
        Ok(())
    }
}
#[derive(Clone)]
pub struct Snapshot {
    Signature: u64,
    Tick: u64,
    States: Vec<u8>,
    Phases: Vec<i32>,
    Queued: Vec<u8>,
}
impl Snapshot {
    pub fn byteCount(&self) -> usize {
        32 + self.States.len() * 6
    }
}

#[cfg(test)]
mod componentTests {
    use super::*;
    fn input(width: usize, height: usize, kinds: Vec<i32>, ids: Vec<i32>) -> CompileInput {
        CompileInput {
            Width: width,
            Height: height,
            Kinds: kinds,
            ComponentIds: ids,
            InitialStates: vec![0; width * height],
            ClockHoldTicks: vec![1; width * height],
        }
    }
    #[test]
    fn adjacentLatchesOnlyShareStateWithinTheirIdentity() {
        for (width, height) in [(4, 2), (2, 4)] {
            let ids = if width == 4 {
                vec![7, 7, 7, 7, 8, 8, 8, 8]
            } else {
                vec![7, 8, 7, 8, 7, 8, 7, 8]
            };
            let data = input(width, height, vec![25; 8], ids.clone());
            let mut core = SimulationCore::compile(data.clone()).unwrap();
            core.toggleLatch(0).unwrap();
            assert_eq!(
                core.states(),
                ids.iter().map(|&id| u8::from(id == 7)).collect::<Vec<_>>()
            );
            let snapshot = core.capture();
            core.toggleLatch(ids.iter().position(|&id| id == 8).unwrap())
                .unwrap();
            assert_eq!(core.states(), &[1; 8]);
            core.restore(&snapshot).unwrap();
            let mut merged = data;
            merged.ComponentIds.fill(7);
            let mut joined = SimulationCore::compile(merged).unwrap();
            assert!(joined.restore(&snapshot).is_err());
            joined.toggleLatch(0).unwrap();
            assert_eq!(joined.states(), &[1; 8]);
        }
    }
    #[test]
    fn adjacentLanesKeepDevicesPortsAndAllConductorKindsIndependent() {
        for conductor in 1..=12 {
            let mut data = input(
                7,
                2,
                vec![
                    25, 15, conductor, conductor, conductor, 16, 17, 25, 15, conductor, conductor,
                    conductor, 16, 17,
                ],
                vec![1, 2, 3, 3, 3, 4, 5, 6, 7, 8, 8, 8, 9, 10],
            );
            // Buses need matching traces at the R/W ports.
            if conductor > 6 {
                let trace = match conductor {
                    7 => 4,
                    8 => 2,
                    9 => 3,
                    10 => 1,
                    11 => 5,
                    _ => 6,
                };
                for cell in [2, 4, 9, 11] {
                    data.Kinds[cell] = trace;
                    data.ComponentIds[cell] = cell as i32 + 100;
                }
            }
            let mut core = SimulationCore::compile(data).unwrap();
            core.toggleLatch(0).unwrap();
            core.advanceSilent(1);
            assert_eq!(
                core.states(),
                &[1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0],
                "conductor {conductor}"
            );
        }
        let data = input(
            7,
            2,
            vec![25, 15, 1, 13, 1, 16, 17, 25, 15, 1, 13, 1, 16, 17],
            (1..=14).collect(),
        );
        let mut core = SimulationCore::compile(data).unwrap();
        core.toggleLatch(0).unwrap();
        core.advanceSilent(1);
        assert_eq!(core.states(), &[1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0]);
    }
    #[test]
    fn differentInkRoutesStillCarrySignalsBetweenIndependentRegions() {
        // Adjacent same-kind traces with distinct IDs don't connect, but a matching bus may bridge them.
        let blocked = input(6, 1, vec![25, 15, 1, 1, 16, 17], (1..=6).collect());
        let mut core = SimulationCore::compile(blocked).unwrap();
        core.toggleLatch(0).unwrap();
        core.advanceSilent(1);
        assert_eq!(core.states(), &[1, 1, 1, 0, 0, 0]);
        let mut bridge = input(
            6,
            2,
            vec![25, 15, 1, 1, 16, 17, 0, 0, 10, 10, 0, 0],
            vec![1, 2, 3, 4, 5, 6, 0, 0, 7, 7, 0, 0],
        );
        let mut core = SimulationCore::compile(bridge.clone()).unwrap();
        core.toggleLatch(0).unwrap();
        core.advanceSilent(1);
        assert_eq!(core.states()[5], 1);
        bridge.Kinds[8] = 7;
        bridge.Kinds[9] = 7; // Legacy Bus color IDs carry every Trace color.
        let mut core = SimulationCore::compile(bridge).unwrap();
        core.toggleLatch(0).unwrap();
        core.advanceSilent(1);
        assert_eq!(core.states()[5], 1);
    }
    #[test]
    fn rejectsMissingDisconnectedAndIncompatibleIdentities() {
        for (kinds, ids, reason) in [
            (vec![25], vec![0], "invalid_component_id"),
            (vec![25], vec![-1], "invalid_component_id"),
            (vec![0], vec![1], "invalid_component_id"),
            (vec![25, 0, 25], vec![1, 0, 1], "disconnected_component"),
            (vec![25, 26], vec![1, 1], "incompatible_component"),
            (vec![14], vec![1], "unknown_kind"),
        ] {
            let width = kinds.len();
            assert_eq!(
                SimulationCore::compile(input(width, 1, kinds, ids))
                    .err()
                    .unwrap()
                    .ErrorReason,
                reason
            );
        }
        for kind in [25, 26] {
            let mut data = input(2, 1, vec![kind; 2], vec![1; 2]);
            if kind == 25 {
                data.InitialStates[1] = 1;
            } else {
                data.ClockHoldTicks[1] = 2;
            }
            assert_eq!(
                SimulationCore::compile(data).err().unwrap().ErrorReason,
                "incompatible_component"
            );
        }
    }
    // Sparse fixtures describe physical components explicitly, including their IDs.
    fn board(cells: &[(usize, usize, i32, i32)]) -> CompileInput {
        let width = cells.iter().map(|c| c.0).max().unwrap() + 1;
        let height = cells.iter().map(|c| c.1).max().unwrap() + 1;
        let mut data = input(
            width,
            height,
            vec![0; width * height],
            vec![0; width * height],
        );
        for &(x, y, kind, id) in cells {
            data.Kinds[y * width + x] = kind;
            data.ComponentIds[y * width + x] = id;
        }
        data
    }
    #[test]
    fn eightBusChannelsFanOutIndependentlyAndUndrivenWritesStayLow() {
        let mut cells = vec![];
        let traceKinds = [1, 2, 3, 4, 5, 6, 28, 29];
        for (lane, &kind) in traceKinds.iter().enumerate() {
            let y = lane * 3;
            let id = 10 + lane as i32 * 10;
            cells.extend([
                (0, y, 25, id),
                (1, y, 15, id + 1),
                (2, y, kind, id + 2),
                (4, y, kind, id + 3),
                (5, y, 16, id + 4),
                (6, y, 27, id + 5),
                (4, y + 1, 16, id + 6),
                (5, y + 1, 27, id + 7),
            ]);
            for dy in y..y + 3 {
                cells.push((3, dy, 7, 1));
            }
        }
        // A second yellow receiver has no separate driver and follows channel zero.
        cells.extend([
            (2, 24, 1, 200),
            (1, 24, 16, 201),
            (0, 24, 27, 202),
            (3, 24, 7, 1),
        ]);
        let mut core = SimulationCore::compile(board(&cells)).unwrap();
        let width = core.Width;
        for active in 0..8 {
            core.toggleLatch(active * 3 * width).unwrap();
            core.advanceSilent(1);
            for lane in 0..8 {
                let expected = u8::from(lane == active);
                assert_eq!(core.states()[lane * 3 * width + 6], expected);
                assert_eq!(core.states()[(lane * 3 + 1) * width + 5], expected);
            }
            assert_eq!(core.states()[24 * width], u8::from(active == 0));
            let snapshot = core.capture();
            core.resetSilent();
            assert!(core.states().iter().all(|&v| v == 0));
            core.restore(&snapshot).unwrap();
            core.toggleLatch(active * 3 * width).unwrap();
            core.advanceSilent(1);
        }
        let mut undriven = board(&[(0, 0, 7, 1), (1, 0, 29, 2), (2, 0, 16, 3), (3, 0, 27, 4)]);
        undriven.InitialStates.fill(1);
        let mut core = SimulationCore::compile(undriven).unwrap();
        core.advanceSilent(8);
        assert_eq!(core.states(), &[0, 0, 0, 0]);
    }
    #[test]
    fn readCombinesLogicAndWriteSourcesWithoutReversingThePortLink() {
        let data = board(&[
            (0, 1, 25, 1),
            (1, 1, 15, 2),
            (2, 1, 1, 3),
            (3, 1, 16, 4),
            (4, 1, 15, 5),
            (5, 1, 2, 6),
            (6, 1, 16, 7),
            (7, 1, 27, 8),
            (4, 0, 25, 9),
        ]);
        let mut core = SimulationCore::compile(data).unwrap();
        let width = core.Width;
        core.toggleLatch(width).unwrap();
        core.advanceSilent(1);
        assert_eq!(core.states()[width + 7], 1);
        core.toggleLatch(4).unwrap();
        core.toggleLatch(width).unwrap();
        core.advanceSilent(1);
        assert_eq!(core.states()[width + 7], 1);
        assert_eq!(
            core.states()[width + 2],
            0,
            "Read cannot drive its neighboring Write"
        );
        core.toggleLatch(4).unwrap();
        core.advanceSilent(1);
        assert_eq!(core.states()[width + 7], 0);
        // Multiple direct logic sources also OR together without a gate tick.
        let mut core = SimulationCore::compile(board(&[
            (0, 0, 25, 1),
            (1, 0, 15, 2),
            (2, 0, 1, 3),
            (1, 1, 25, 4),
        ]))
        .unwrap();
        core.toggleLatch(0).unwrap();
        assert_eq!(core.states()[2], 1);
        core.toggleLatch(4).unwrap();
        core.toggleLatch(0).unwrap();
        assert_eq!(core.states()[2], 1);
    }
    #[test]
    fn logicSidesMayBeEmptyButTraceSidesRequireExactlyOneComponent() {
        for cells in [
            vec![(0, 0, 15, 1), (1, 0, 1, 2)],
            vec![(0, 0, 1, 1), (1, 0, 16, 2)],
        ] {
            let mut core = SimulationCore::compile(board(&cells)).unwrap();
            core.advanceSilent(4);
            assert_eq!(core.states(), &[0, 0]);
        }
        for (cells, reason) in [
            (vec![(0, 0, 15, 1)], "read_requires_one_trace_sink"),
            (vec![(0, 0, 16, 1)], "write_requires_one_trace_source"),
            (
                vec![(0, 0, 1, 1), (1, 0, 15, 2), (2, 0, 1, 3)],
                "read_requires_one_trace_sink",
            ),
            (
                vec![(0, 0, 1, 1), (1, 0, 16, 2), (2, 0, 1, 3)],
                "write_requires_one_trace_source",
            ),
            // Bus unifies the two traces electrically, but not their identities.
            (
                vec![
                    (0, 0, 1, 1),
                    (1, 0, 15, 2),
                    (2, 0, 1, 3),
                    (0, 1, 7, 4),
                    (1, 1, 7, 4),
                    (2, 1, 7, 4),
                ],
                "read_requires_one_trace_sink",
            ),
        ] {
            assert_eq!(
                SimulationCore::compile(board(&cells))
                    .err()
                    .unwrap()
                    .ErrorReason,
                reason
            );
        }
        // Repeated contacts to the same physical Trace count once.
        SimulationCore::compile(board(&[
            (0, 0, 15, 1),
            (1, 0, 15, 1),
            (0, 1, 1, 2),
            (1, 1, 1, 2),
        ]))
        .unwrap();
        // Bus must not connect directly to a port.
        assert_eq!(
            SimulationCore::compile(board(&[(0, 0, 7, 1), (1, 0, 15, 2)]))
                .err()
                .unwrap()
                .ErrorReason,
            "read_requires_one_trace_sink"
        );
    }
    #[test]
    fn busRejectsMultipleReadsAfterCrossConnectivityButPlainTraceStillOrs() {
        let data = board(&[
            (0, 0, 25, 1),
            (1, 0, 15, 2),
            (2, 0, 1, 3),
            (3, 0, 1, 3),
            (4, 0, 15, 4),
            (5, 0, 25, 5),
        ]);
        let mut core = SimulationCore::compile(data.clone()).unwrap();
        core.toggleLatch(0).unwrap();
        assert_eq!(core.states()[3], 1);
        core.toggleLatch(5).unwrap();
        core.toggleLatch(0).unwrap();
        assert_eq!(core.states()[3], 1);
        core.toggleLatch(5).unwrap();
        assert_eq!(core.states()[3], 0);
        let multiple = board(&[
            (0, 0, 25, 1),
            (1, 0, 15, 2),
            (2, 0, 1, 3),
            (3, 0, 7, 4),
            (4, 0, 13, 5),
            (5, 0, 1, 6),
            (6, 0, 15, 7),
            (7, 0, 25, 8),
        ]);
        let error = SimulationCore::compile(multiple).err().unwrap();
        assert_eq!(error.ErrorReason, "bus_channel_multiple_reads");
        assert_eq!((error.ErrorX, error.ErrorY), (6, 0));
        // One Read may touch its own Trace more than once without becoming two drivers.
        SimulationCore::compile(board(&[
            (0, 0, 15, 1),
            (1, 0, 15, 1),
            (0, 1, 1, 2),
            (1, 1, 1, 2),
            (2, 1, 7, 3),
        ]))
        .unwrap();
    }
    #[test]
    fn crossCarriesBusTraceAndBusBusOnIndependentAxes() {
        for horizontalBus in [false, true] {
            let mut cells = vec![
                (0, 3, 25, 1),
                (1, 3, 15, 2),
                (2, 3, 28, 3),
                (3, 3, 7, 4),
                (4, 3, 13, 5),
                (6, 3, 28, 7),
                (7, 3, 16, 8),
                (8, 3, 27, 9),
                (4, 0, 25, 10),
                (4, 1, 15, 11),
                (4, 2, 28, 12),
                (4, 4, 28, 13),
                (4, 5, 16, 14),
                (4, 6, 27, 15),
            ];
            cells.push((
                5,
                3,
                if horizontalBus { 7 } else { 28 },
                if horizontalBus { 6 } else { 7 },
            ));
            let mut core = SimulationCore::compile(board(&cells)).unwrap();
            let width = core.Width;
            core.toggleLatch(3 * width).unwrap();
            core.advanceSilent(1);
            assert_eq!(core.states()[3 * width + 8], 1);
            assert_eq!(core.states()[6 * width + 4], 0);
            core.toggleLatch(4).unwrap();
            core.toggleLatch(3 * width).unwrap();
            core.advanceSilent(1);
            assert_eq!(core.states()[3 * width + 8], 0);
            assert_eq!(core.states()[6 * width + 4], 1);
        }
    }
}
