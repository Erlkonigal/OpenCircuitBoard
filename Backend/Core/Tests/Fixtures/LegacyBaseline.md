# Legacy simulation baseline

Recorded on Windows x86_64, 2026-11-15, from Git revision `7feac8f`.
The fixture was recorded from the existing `SimulationCoreTests.cpp` operation stream,
plus 128 fixed-seed random boards (seed 20261115). Repeated arrays are run-length encoded.
The active replay retains 597 state/delta comparisons. Sessions 39, 40, 46, 48, 49, and 81
used the removed Mesh component (kind 14) and were retired with it; obsolete `meshIds`
fields were dropped from the remaining records. Isolation masks default to zero for
this legacy replay, preserving its original connectivity.
It contains original inputs, compilation errors, visible states, deltas, latch operations,
snapshot capture/restore operations, resets, and deferred presentation operations.

Default Release mixed benchmark: 1024x1024, 256 pipelines, 572672 active cells,
512 warmup ticks, 1024 measured ticks, five samples. Median: **3491.07 TPS**;
compile: **0.52 seconds**; drain median: **6.47 ms**;
state checksum: **8157184091000160966**. Existing 100K TPS target was not met.
The Rust gate is 90% of this same-machine baseline (3141.963 TPS).

Rust MSVC x64 Release, same mixed workload and checksum: **3675.27 TPS**,
compile **0.836 s**, median drain **6.01 ms**. This exceeds the 3141.963 TPS gate.
The legacy measurement used the previous GNU toolchain; the replacement Windows
workflow is native PowerShell/MSVC throughout. Performance measurements are
machine-dependent and are not used as a shared-runner CI threshold.
