# OpenCircuitBoard

A desktop circuit workspace built with **Tauri, React, TypeScript, Mantine, and PixiJS**. Rust owns the simulation, timeline, project archives, and native services. The core runs independently of Tauri.

The workspace has a searchable component library, a central canvas, and an inspector for component and canvas properties. Clipboard history lives in its own panel; Activity opens below the canvas. Transport, stepping, speed, and full-speed controls stay in the top toolbar. Press Ctrl+K to find commands.

Click or drag to draw. Right-drag erases; Shift-drag selects. Drag within a selection to move it. Ctrl+C/X/V copies, cuts, and previews a paste. Click to place; Esc cancels. Middle-drag pans and the wheel zooms. Ctrl+Z undoes, Ctrl+U or Ctrl+Shift+Z redoes. The inspector edits selected components, or the defaults for the active tool. Runtime states never overwrite the editable circuit.

Each stroke creates a component, including traces, buses, Cross, and ports. Starting on an existing cell with the same exact ink extends that component and inherits its settings. Left painting replaces occupied cells. Adjacent strokes remain independent; hover or selection highlights the whole component's actual area, without permanent boundary lines. Overwriting, erasing, cutting, deleting, or moving a portion splits any disconnected pieces using four-neighbor connectivity. The largest remaining piece keeps its ID; equal-sized pieces use topmost, then leftmost order.

Use **Merge** to click complete component regions with the same ink and settings. Each new region must touch the selected group; confirm once with the inspector or Enter. Esc or right-click cancels. **Split**, beside Merge in the Tools section, lets you drag a rectangle over a portion and confirm with the inspector or Enter. Select less than the whole component. Inspector property changes apply to whole touched components, so split first to edit only a portion. Whole-component moves retain their IDs; partial moves detach the moved pieces. Paste and move still reject occupied or out-of-bounds destinations.

Same-ink components with different IDs do not merge or conduct directly. Existing connections between different inks retain their color, port, and directional Cross rules; another physical route may still connect separate components.

Blueprints are flat ink snapshots saved with the current project. Save a selection in the inspector or save a clipboard item; the Blueprints panel supports search, rename, and delete. Clicking a blueprint copies its snapshot into clipboard history while keeping the panel open. Each Ctrl+V starts an ordinary paste preview, and each placement remaps every internal component to a fresh ID while preserving its grouping as editable cells. Blueprint management and placement support undo/redo.

The toolbar's 2D / 2.5D control applies to the board and both preview libraries and remembers the choice on this device. At 12 CSS pixels per cell and above, the board and previews show ink symbols; all Trace variants use only their color at every zoom level. Between 2 and 12 pixels they use color chunks with batched depth in 2.5D. Below 2 pixels both modes use area-weighted color and coverage maps. The sparse 64-cell chunk index and worker-built color pyramid update affected chunks and ancestors; a shared 64 MiB LRU bounds color raster and thumbnail caches. Zoom uses proportional steps around the pointer.

## Repository layout

- `Frontend/Source`: React editor, PixiJS renderer, and TypeScript state and IPC clients.
- `Frontend/Assets`: component SVGs and third-party notices.
- `Frontend/Tests`: unit, browser, and desktop UI tests; npm, Vite, TypeScript, and test configuration live in `Frontend/`.
- `Backend/Core`: independent Rust simulation, project archives, tests, and regression fixtures.
- `Backend/Desktop`: Tauri host, native commands, application icons, and desktop configuration; the Cargo workspace and lockfile live in `Backend/`.
- `scripts/` and `Makefile`: shared build entrypoints. Shared test tools and inspected captures are generated in `build/`.

All build results live under root `build/`: frontend assets in `build/Frontend/`, Rust intermediates, binaries and installers in `build/Backend/`, Vite/Vitest caches in `build/Cache/`, Tauri schemas in `build/Backend/TauriSchemas/`, and test captures/reports in their existing `build/` locations. npm installs locked frontend dependencies in `build/Dependencies/node_modules/`; the frontend command runner, TypeScript and Vite resolve them from there without links inside source folders. Use `make init` after a full clean. Cargo uses the root `.cargo/config.toml` so direct Cargo and Tauri commands use the same output directory.

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

The app sets `app.security.csp` to `null` in `Backend/Desktop/tauri.conf.json` and uses the standard PixiJS renderer.

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

`native-test` builds and tests the real Tauri app, its simulation controls, and archive IPC. On Windows, `test-tools` installs `tauri-driver` and matching EdgeDriver into `build/TestTools`. Linux also needs `WebKitWebDriver` (the `webkit2gtk-driver` package on Debian/Ubuntu), and a display or Xvfb. Native captures include `DesktopCapture.png`, `DesktopSimulationCapture.png`, and `DesktopComponentLanesCapture.png`, and `DesktopComponentMergeCapture.png`. Use `make native-ui-test` to test an already-built Release binary without rebuilding it.

`test` runs Rust workspace tests, a frontend production build, unit tests, and browser tests. CI defines Windows and Linux validation and packaging separately.

The core tests replay 597 recorded C++ state/delta comparisons for supported components, plus component identities, independent adjacent lanes, snapshots, clock/latch behavior, graph ordering, project compatibility, and worker lifecycle tests. The default mixed benchmark uses 1024x1024 cells and 256 pipelines. The migration gate is 90% of the measured legacy baseline; the separate historical 100K TPS target has not been reached. See `Backend/Core/Tests/Fixtures/LegacyBaseline.md`. Pass `CORE_BENCHMARK_ARGS="--quick"` for a short run. `board-benchmark` also accepts `BOARD_BENCHMARK_ARGS="--editorProbe"`.

## Project format

`.ocb` files remain ZIP archives with `project.json` and `formatVersion: 2`. Grid bounds, per-cell clock settings, latch initial states, and editor defaults are preserved. Loading completes validation before replacing the open board. Every occupied tile must have a positive int32 `componentId`. Cells sharing an ID must have the same exact ink, compatible Latch initial state or Clock interval, and form one four-neighbor connected region. The optional top-level `blueprints` array contains `{ id, name, width, height, tiles }` snapshots using relative coordinates, explicit clock parameters, and snapshot-local component IDs. Empty blueprints are invalid.

Missing component IDs and unknown inks produce ordinary board or blueprint validation errors; IDs are never inferred when loading old files. Isolation edges are removed. Numeric tool IDs retain their values; ID 14 remains undefined. Native project IPC exchanges `{ board, blueprints }`; simulation receives the board alone. Binary compile input uses version **3** with a 24-byte header followed by four int32 arrays: kinds, initial states, clock intervals, and component IDs (zero for empty cells). Runtime frames retain their existing format. Display mode is stored in application-origin localStorage and stays outside project files. Recent projects are stored in `RecentProjects.json` in the native application data directory.
