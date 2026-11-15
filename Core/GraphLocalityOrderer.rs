//! Deterministic reverse Cuthill-McKee followed by a 64-node Gorder window.
use std::collections::VecDeque;
const WindowSize: usize = 64;
fn incoming(out: &[Vec<usize>]) -> Vec<Vec<usize>> {
    let mut inc = vec![vec![]; out.len()];
    for (source, targets) in out.iter().enumerate() {
        for &target in targets {
            inc[target].push(source);
        }
    }
    inc
}
fn inverse(order: &[usize]) -> Vec<usize> {
    let mut map = vec![0; order.len()];
    for (new, &old) in order.iter().enumerate() {
        map[old] = new;
    }
    map
}
fn score(out: &[Vec<usize>], order: &[usize]) -> u64 {
    let map = inverse(order);
    out.iter()
        .enumerate()
        .flat_map(|(s, ts)| ts.iter().map(move |&t| (s, t)))
        .map(|(s, t)| {
            let distance = map[s].abs_diff(map[t]);
            if distance <= WindowSize {
                (WindowSize + 1 - distance) as u64
            } else {
                0
            }
        })
        .sum()
}
struct ScoreHeap {
    Nodes: Vec<usize>,
    Positions: Vec<usize>,
    Scores: Vec<i64>,
}
impl ScoreHeap {
    fn new(nodes: Vec<usize>, count: usize) -> Self {
        let mut heap = Self {
            Nodes: nodes,
            Positions: vec![usize::MAX; count],
            Scores: vec![0; count],
        };
        for (i, &n) in heap.Nodes.iter().enumerate() {
            heap.Positions[n] = i;
        }
        for i in (0..heap.Nodes.len() / 2).rev() {
            heap.down(i);
        }
        heap
    }
    fn higher(&self, a: usize, b: usize) -> bool {
        self.Scores[a] > self.Scores[b] || (self.Scores[a] == self.Scores[b] && a < b)
    }
    fn swap(&mut self, a: usize, b: usize) {
        self.Nodes.swap(a, b);
        self.Positions[self.Nodes[a]] = a;
        self.Positions[self.Nodes[b]] = b;
    }
    fn down(&mut self, mut i: usize) {
        loop {
            let left = i * 2 + 1;
            if left >= self.Nodes.len() {
                break;
            }
            let right = left + 1;
            let best =
                if right < self.Nodes.len() && self.higher(self.Nodes[right], self.Nodes[left]) {
                    right
                } else {
                    left
                };
            if !self.higher(self.Nodes[best], self.Nodes[i]) {
                break;
            }
            self.swap(i, best);
            i = best;
        }
    }
    fn adjust(&mut self, node: usize) {
        let mut i = self.Positions[node];
        if i == usize::MAX {
            return;
        }
        if i > 0 && self.higher(node, self.Nodes[(i - 1) / 2]) {
            while i > 0 {
                let parent = (i - 1) / 2;
                if !self.higher(self.Nodes[i], self.Nodes[parent]) {
                    break;
                }
                self.swap(i, parent);
                i = parent;
            }
        } else {
            self.down(i);
        }
    }
    fn update(&mut self, node: usize, delta: i64) {
        if self.Positions[node] != usize::MAX {
            self.Scores[node] += delta;
            self.adjust(node);
        }
    }
    fn remove(&mut self, node: usize) {
        let i = self.Positions[node];
        if i == usize::MAX {
            return;
        }
        let last = self.Nodes.pop().unwrap();
        self.Positions[node] = usize::MAX;
        if i < self.Nodes.len() {
            self.Nodes[i] = last;
            self.Positions[last] = i;
            self.adjust(last);
        }
    }
    fn pop(&mut self) -> Option<usize> {
        let node = *self.Nodes.first()?;
        self.remove(node);
        Some(node)
    }
}
fn windowUpdate(
    node: usize,
    delta: i64,
    out: &[Vec<usize>],
    inc: &[Vec<usize>],
    large: usize,
    heap: &mut ScoreHeap,
) {
    if out[node].len() <= large {
        for &target in &out[node] {
            heap.update(target, delta);
        }
    }
    for &source in &inc[node] {
        if out[source].len() > large {
            continue;
        }
        heap.update(source, delta);
        if out[source].len() > 1 {
            for &target in &out[source] {
                heap.update(target, delta);
            }
        }
    }
}
pub fn localityOrder(out: &[Vec<usize>]) -> Vec<usize> {
    let count = out.len();
    if count <= 1 {
        return (0..count).collect();
    }
    let inc = incoming(out);
    let degree = |n: usize| out[n].len() + inc[n].len();
    let mut seeds: Vec<_> = (0..count).collect();
    seeds.sort_unstable_by_key(|&n| (degree(n), n));
    let mut visited = vec![false; count];
    let mut traversal = Vec::with_capacity(count);
    let mut queue = Vec::new();
    let mut neighbors = Vec::new();
    for seed in seeds {
        if visited[seed] {
            continue;
        }
        queue.clear();
        queue.push(seed);
        visited[seed] = true;
        let mut cursor = 0;
        while cursor < queue.len() {
            let node = queue[cursor];
            cursor += 1;
            traversal.push(node);
            neighbors.clear();
            neighbors.extend(out[node].iter().copied().filter(|&n| !visited[n]));
            neighbors.sort_unstable_by_key(|&n| (degree(n), n));
            for &n in &neighbors {
                if !visited[n] {
                    visited[n] = true;
                    queue.push(n);
                }
            }
        }
    }
    traversal.reverse();
    let rcm = inverse(&traversal);
    let mut transformed = vec![vec![]; count];
    for (old, ts) in out.iter().enumerate() {
        transformed[rcm[old]] = ts.iter().map(|&t| rcm[t]).collect();
        transformed[rcm[old]].sort_unstable();
        transformed[rcm[old]].dedup();
    }
    let inc = incoming(&transformed);
    let out = &transformed;
    let connected: Vec<_> = (0..count)
        .filter(|&n| !out[n].is_empty() || !inc[n].is_empty())
        .collect();
    if connected.is_empty() {
        return (0..count).collect();
    }
    let first = *connected
        .iter()
        .min_by_key(|&&n| (std::cmp::Reverse(inc[n].len()), n))
        .unwrap();
    let mut heap = ScoreHeap::new(connected, count);
    let mut order = Vec::with_capacity(count);
    let large = (count as f64).sqrt() as usize;
    let mut window = VecDeque::new();
    heap.remove(first);
    order.push(first);
    window.push_back(first);
    windowUpdate(first, 1, out, &inc, large.max(1), &mut heap);
    while let Some(node) = heap.pop() {
        order.push(node);
        windowUpdate(node, 1, out, &inc, large.max(1), &mut heap);
        window.push_back(node);
        if window.len() > WindowSize {
            windowUpdate(
                window.pop_front().unwrap(),
                -1,
                out,
                &inc,
                large.max(1),
                &mut heap,
            );
        }
    }
    order.extend((0..count).filter(|&n| out[n].is_empty() && inc[n].is_empty()));
    order.into_iter().map(|n| traversal[n]).collect()
}
fn rankConnectors(out: &[Vec<usize>], components: usize, priority: &[usize]) -> Option<Vec<usize>> {
    let map = inverse(priority);
    let mut indegree = vec![0; out.len()];
    for ts in &out[components..] {
        for &t in ts {
            if t >= components {
                indegree[t] += 1;
            }
        }
    }
    let mut order: Vec<_> = priority
        .iter()
        .copied()
        .filter(|&n| n < components)
        .collect();
    let mut queue: VecDeque<_> = priority
        .iter()
        .copied()
        .filter(|&n| n >= components && indegree[n] == 0)
        .collect();
    while let Some(n) = queue.pop_front() {
        order.push(n);
        let mut targets = out[n].clone();
        targets.sort_unstable_by_key(|&t| map[t]);
        for t in targets {
            if t >= components {
                indegree[t] -= 1;
                if indegree[t] == 0 {
                    queue.push_back(t);
                }
            }
        }
    }
    (order.len() == out.len()).then_some(order)
}
/// Keep components before connectors and every connector edge in DAG order.
/// Only accept a candidate whose locality score improves over the baseline.
pub fn executionOrder(
    out: &[Vec<usize>],
    components: usize,
    enabled: bool,
) -> Option<(Vec<usize>, bool, u64)> {
    let identity: Vec<_> = (0..out.len()).collect();
    let baseline = rankConnectors(out, components, &identity)?;
    let baselineScore = score(out, &baseline);
    if !enabled {
        return Some((baseline, false, baselineScore));
    }
    let locality = localityOrder(out);
    let candidate = rankConnectors(out, components, &locality)?;
    let candidateScore = score(out, &candidate);
    if candidateScore > baselineScore {
        Some((candidate, true, candidateScore))
    } else {
        Some((baseline, false, baselineScore))
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn permutationLocalityAndTopology() {
        let graph = vec![
            vec![4],
            vec![5],
            vec![6],
            vec![],
            vec![0],
            vec![1],
            vec![2],
            vec![],
        ];
        let a = localityOrder(&graph);
        assert_eq!(a, localityOrder(&graph));
        let mut sorted = a.clone();
        sorted.sort_unstable();
        assert_eq!(sorted, (0..8).collect::<Vec<_>>());
        assert!(score(&graph, &a) > score(&graph, &sorted));
        let map = inverse(&a);
        for (s, ts) in graph.iter().enumerate() {
            for &t in ts {
                assert_eq!((a[map[s]], a[map[t]]), (s, t));
            }
        }
    }
    #[test]
    fn connectorRanksAndFallback() {
        let graph = vec![vec![3], vec![], vec![1], vec![2]];
        let (order, _, _) = executionOrder(&graph, 2, true).unwrap();
        let map = inverse(&order);
        assert!(map[3] < map[2]);
        assert!(order[..2].iter().all(|&n| n < 2));
        assert!(executionOrder(&[vec![1], vec![0]], 0, true).is_none());
    }
}
