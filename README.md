# OpenCircuitBoard

A desktop circuit workspace built with **Tauri, React, TypeScript, Mantine, and PixiJS**. Rust owns the simulation, timeline, project archives, and native services. The core runs independently of Tauri.

The workspace has a searchable component library, a central canvas, and an inspector for component and canvas properties. Clipboard history lives in its own panel; Activity opens below the canvas. Transport, stepping, speed, and full-speed controls stay in the top toolbar. Press Ctrl+K to find commands.

Click or drag to draw. Right-drag erases; Shift-drag selects. Drag within a selection to move it. Ctrl+C/X/V copies, cuts, and previews a paste. Click to place; Esc cancels. Middle-drag pans and the wheel zooms. Ctrl+Z undoes, Ctrl+U or Ctrl+Shift+Z redoes. The inspector edits selected components, or the defaults for the active tool. Runtime states never overwrite the editable circuit.

## Build and run

Use **make on both Windows and Linux**, from the repository root. The default target matches the native host. You can specify `TARGET_PLATFORM=windows` or `TARGET_PLATFORM=linux` explicitly.

Windows prerequisites:

- Native Windows GNU Make (`make.exe`), standard x64 Node.js, and Rust with `stable-x86_64-pc-windows-msvc`.
- Visual Studio Build Tools with **Desktop development with C++** and a Windows SDK. The helper loads the actual x64 Developer PowerShell environment automatically; a full IDE is unnecessary.
- Edge WebView2 for the desktop runtime, and Edge for browser tests.

Run from native PowerShell:

```powershell
make check-platform TARGET_PLATFORM=windows
make init
make build-release
make run BUILD_TYPE=Debug
make package
```

The app sets `app.security.csp` to `null` in `Desktop/tauri.conf.json` and uses the standard PixiJS renderer.

Windows uses `make -> PowerShell -> MSVC`. It does not require MSYS2, UCRT64, MinGW, Git Bash, or WSL.

Linux requires native Bash, GNU Make, Node.js, Rust, a linker, and Tauri's WebKitGTK 4.1 development libraries. On Debian/Ubuntu these include `build-essential`, `pkg-config`, `libwebkit2gtk-4.1-dev`, `libayatana-appindicator3-dev`, `librsvg2-dev`, `patchelf`, and `libssl-dev`.

```bash
make check-platform TARGET_PLATFORM=linux
make init
make build-release
make run BUILD_TYPE=Debug
make package
```

`make build [BUILD_TYPE=Debug|Release]` builds without an installer. `make run BUILD_TYPE=Debug` launches Vite and Tauri; Release builds and launches the standalone app. `make package` creates NSIS on Windows or AppImage on Linux. `make clean` removes generated output.

## Validation

```powershell
make core-test
make frontend-test
make test-tools
make native-test
make test
make core-benchmark CORE_BENCHMARK_ARGS="--minimum-tps 3142"
make board-benchmark BOARD_PATH=C:/Projects/Example.ocb
```

`frontend-test` builds the frontend, runs editor unit tests, and exercises the rendered production UI in Edge on Windows or Chromium on Linux. Captures are written under `build/`; inspect `InterfaceCapture.png`, `Capture.png`, `SelectorCapture.png`, `BoardEdgeCapture.png`, and the relevant property/clipboard captures.

`native-test` builds and tests the real Tauri app, its simulation controls, and archive IPC. On Windows, `test-tools` installs `tauri-driver` and matching EdgeDriver into `build/TestTools`. Linux also needs `WebKitWebDriver` (the `webkit2gtk-driver` package on Debian/Ubuntu), and a display or Xvfb. Native captures are `DesktopCapture.png` and `DesktopSimulationCapture.png`. Use `make native-ui-test` to test an already-built Release binary without rebuilding it.

`test` runs Rust workspace tests, a frontend production build, unit tests, and browser tests. CI defines Windows and Linux validation and packaging separately.

The core tests replay 682 recorded C++ state/delta comparisons, plus snapshots, clock/latch behavior, graph ordering, project compatibility, and worker lifecycle tests. The default mixed benchmark uses 1024x1024 cells and 256 pipelines. The migration gate is 90% of the measured legacy baseline; the separate historical 100K TPS target has not been reached. See `Tests/Fixtures/LegacyBaseline.md`. Pass `CORE_BENCHMARK_ARGS="--quick"` for a short run. `board-benchmark` also accepts `BOARD_BENCHMARK_ARGS="--editorProbe"`.

## Project format

Existing `.ocb` v2 files remain ZIP archives with `project.json` and `formatVersion: 2`. Grid bounds, per-cell clock/mesh settings, latch initial states, and editor defaults are preserved. Loading completes validation before replacing the open board. Recent projects are imported from the previous editor's settings when no native settings exist.
