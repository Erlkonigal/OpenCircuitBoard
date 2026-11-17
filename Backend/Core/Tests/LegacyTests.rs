#![allow(non_snake_case)]
use ocb_core::{CompileInput, SimulationCore};
use serde_json::Value;
use std::collections::HashMap;
fn expand(value: &Value) -> Vec<i32> {
    let mut values = vec![];
    for pair in value.as_array().unwrap() {
        values.extend(std::iter::repeat_n(
            pair[0].as_i64().unwrap() as i32,
            pair[1].as_u64().unwrap() as usize,
        ));
    }
    values
}
// The recordings predate IDs. This adapter exists only for historical test fixtures.
fn assignRecordedComponents(input: &mut CompileInput) {
    let count = input.Width * input.Height;
    input.ComponentIds = vec![0; count];
    let mut id = 0;
    for cell in 0..count {
        if input.Kinds.get(cell).copied().unwrap_or(0) == 0 || input.ComponentIds[cell] != 0 {
            continue;
        }
        id += 1;
        input.ComponentIds[cell] = id;
        let mut queue = vec![cell];
        while let Some(current) = queue.pop() {
            let (x, y) = (current % input.Width, current / input.Width);
            for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                let (nx, ny) = (x as i32 + dx, y as i32 + dy);
                if nx < 0 || ny < 0 || nx >= input.Width as i32 || ny >= input.Height as i32 {
                    continue;
                }
                let n = ny as usize * input.Width + nx as usize;
                if input.ComponentIds[n] == 0
                    && input.Kinds[n] == input.Kinds[cell]
                    && (input.Kinds[cell] != 25
                        || (input.InitialStates[n] != 0) == (input.InitialStates[cell] != 0))
                    && (input.Kinds[cell] != 26
                        || input.ClockHoldTicks[n] == input.ClockHoldTicks[cell])
                {
                    input.ComponentIds[n] = id;
                    queue.push(n);
                }
            }
        }
    }
}
#[test]
fn replayLegacyCore() {
    let mut cores: HashMap<u64, SimulationCore> = HashMap::new();
    let mut snapshots = HashMap::new();
    let mut checks = 0;
    let mut ordering = HashMap::new();
    for (line, text) in include_str!("Fixtures/LegacyCore.jsonl")
        .lines()
        .enumerate()
    {
        let v: Value = serde_json::from_str(text).unwrap();
        let id = v["id"].as_u64().unwrap();
        let op = v["op"].as_str().unwrap();
        // These recordings exercised multi-Trace ports or Read-to-Write bypasses.
        // Check their new compilation result; their obsolete frames are not replayed.
        let changed = match id {
            16 | 43 | 52 | 53 | 59 | 72 | 73 | 74 | 75 | 77 => Some("read_requires_one_trace_sink"),
            42 | 60 | 103 => Some("write_requires_one_trace_source"),
            56 => Some(""), // An output-free Write is now valid.
            _ => None,
        };
        if changed.is_some() && !matches!(op, "new" | "compile") {
            continue;
        }
        if op == "new" {
            ordering.insert(id, v["order"] == 1);
            cores.insert(id, SimulationCore::default());
            continue;
        }
        if op == "compile" {
            let mut input = CompileInput {
                Width: v["width"].as_u64().unwrap() as usize,
                Height: v["height"].as_u64().unwrap() as usize,
                Kinds: expand(&v["kinds"]),
                InitialStates: expand(&v["initialStates"]),
                ClockHoldTicks: expand(&v["clockHoldTicks"]),
                ComponentIds: vec![],
            };
            assignRecordedComponents(&mut input);
            let result = SimulationCore::compileWithOrdering(input, *ordering.get(&id).unwrap());
            if let Some(reason) = changed {
                if reason.is_empty() {
                    let mut core = result.expect("Unloaded Write now compiles");
                    core.advanceSilent(4);
                    assert!(core.states().iter().all(|&v| v == 0));
                } else {
                    assert_eq!(
                        result.err().unwrap().ErrorReason,
                        reason,
                        "Changed session {id}"
                    );
                }
                continue;
            }
            assert_eq!(
                result.is_ok(),
                v["ok"] == 1,
                "compile at line {}: {:?}",
                line + 1,
                result.as_ref().err()
            );
            match result {
                Ok(core) => {
                    cores.insert(id, core);
                }
                Err(e) => {
                    assert_eq!(
                        e.ErrorReason,
                        match v["reason"].as_str().unwrap() {
                            "read_requires_one_source" | "read_requires_output" =>
                                "read_requires_one_trace_sink",
                            "write_requires_one_input" => "write_requires_one_trace_source",
                            reason => reason,
                        },
                        "reason line {}",
                        line + 1
                    );
                    assert_eq!(e.ErrorX, v["errorX"].as_i64().unwrap() as i32);
                    assert_eq!(e.ErrorY, v["errorY"].as_i64().unwrap() as i32);
                    cores.insert(id, SimulationCore::default());
                }
            }
            continue;
        }
        let core = cores.get_mut(&id).unwrap();
        let expected = || {
            v["values"]
                .as_array()
                .unwrap()
                .iter()
                .map(|n| n.as_i64().unwrap() as i32)
                .collect::<Vec<_>>()
        };
        match op {
            "states" => {
                assert_eq!(
                    core.states().iter().map(|&n| n as i32).collect::<Vec<_>>(),
                    expand(&v["values"]),
                    "states line {}",
                    line + 1
                );
                checks += 1;
            }
            "advance" => core.advanceSilent(v["ticks"].as_i64().unwrap() as i32),
            "ticks" => {
                assert_eq!(
                    core.advance(v["ticks"].as_i64().unwrap() as i32),
                    expected(),
                    "ticks line {}",
                    line + 1
                );
                checks += 1;
            }
            "drain" => {
                assert_eq!(core.drain(), expected(), "drain line {}", line + 1);
                checks += 1;
            }
            "toggle" => assert_eq!(
                core.toggleLatch(v["cell"].as_i64().unwrap() as usize)
                    .is_ok(),
                v["ok"] == 1,
                "toggle line {}",
                line + 1
            ),
            "capture" => {
                snapshots.insert(v["key"].as_i64().unwrap(), core.capture());
            }
            "restore" => {
                let result = snapshots
                    .get(&v["key"].as_i64().unwrap())
                    .map_or(false, |s| core.restore(s).is_ok());
                assert_eq!(result, v["ok"] == 1, "restore line {}", line + 1);
            }
            "reset" => core.resetSilent(),
            "beginDeferred" => assert_eq!(core.beginDeferred(), v["ok"] == 1),
            "endDeferred" => core.endDeferred(),
            _ => panic!("unknown {op}"),
        }
    }
    assert_eq!(checks, 502);
    println!("Compared {checks} legacy states and deltas");
}
