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
        if op == "new" {
            ordering.insert(id, v["order"] == 1);
            cores.insert(id, SimulationCore::default());
            continue;
        }
        if op == "compile" {
            let input = CompileInput {
                Width: v["width"].as_u64().unwrap() as usize,
                Height: v["height"].as_u64().unwrap() as usize,
                Kinds: expand(&v["kinds"]),
                InitialStates: expand(&v["initialStates"]),
                ClockHoldTicks: expand(&v["clockHoldTicks"]),
                MeshIds: expand(&v["meshIds"]),
            };
            let result = SimulationCore::compileWithOrdering(input, *ordering.get(&id).unwrap());
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
                        v["reason"].as_str().unwrap(),
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
    assert!(checks > 500);
    println!("Compared {checks} legacy states and deltas");
}
