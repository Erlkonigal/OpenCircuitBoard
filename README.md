# OpenCircuitBoard

A desktop circuit workspace built with **Tauri, React, TypeScript, Mantine, and PixiJS**. Rust owns the simulation, timeline, project archives, and native services. The core runs independently of Tauri.

The workspace has a searchable component library, a central canvas, and an inspector for component and canvas properties. Clipboard history lives in its own panel; Activity opens below the canvas. Transport, stepping, speed, and full-speed controls stay in the top toolbar. Press Ctrl+K to find commands.

The editor opens in **Pointer** mode. Click a component to inspect its properties. Shift-click toggles a whole component without clearing the others. Drag from blank space or an unselected component to replace the selection; in Pointer mode, **Shift-drag adds whole components** to the selection, including when started over an occupied cell. Every marquee tests actual cell intersections and selects complete identities, including cells outside the rectangle. Drag selected components to move them; a four-CSS-pixel threshold separates clicks from moves. Selection follows component IDs and exact membership, including holes. Ctrl and Meta do not modify mouse selection; keyboard shortcuts such as Ctrl+C and Ctrl+Z remain available.

Hover and selection use the same 15% whole-surface highlight, covering the top and both visible sides in 2.5D, without a permanent outline or extra brightness when both apply. All inks share a moderate-brightness palette (weighted RGB at most 160/255), leaving room for the same light tint on every material. Holes and neighboring independent components keep their original appearance at every rendering LOD. The temporary drag rectangle uses a static dashed edge.

Common editing controls stay near the left hand:

| Action | Control |
| --- | --- |
| Pointer / draw with last ink | V / B |
| Add or remove a component | Shift+click |
| Add a component area (Pointer) | Shift+drag |
| Draw a filled ink rectangle (Draw) | Shift+drag |
| Delete the current selection | X |
| Cancel an unfinished operation and return to Pointer | Right-click or Q |
| Clear an idle pointer selection | Right-click, Q, or Ctrl+D |
| Merge tool / confirm merge | G |
| Split along grid edges | Shift+G, then left-drag |
| Pan / zoom / fit canvas | Space+left drag or middle drag / wheel / F |
| Undo / redo | Ctrl+Z / Ctrl+Shift+Z |
| Copy / cut / paste | Ctrl+C / Ctrl+X / Ctrl+V |
| Select all complete components | Ctrl+A |

Select an ink or the Draw tool to enter drawing mode. Left-click or drag draws; **Shift+drag fills an inclusive rectangle**, clipped to the board in any direction. The translucent rectangle is only a preview until release, so shrinking or cancelling leaves no cells behind. One rectangle follows the same starting-cell inheritance and merge rules as a freehand stroke, creates one undo step, and stays in Draw mode. Right mouse never erases. Each stroke creates a component, including traces, buses, Cross, and ports. Starting on an existing cell with the same exact ink extends that component and inherits its settings. If that stroke enters another compatible component, its entire region joins the starting component and keeps the starting ID. One stroke can join several targets; the bridge and all merges form one undo step and cancel together. Merely touching a side or corner does not merge, and a stroke started in empty space does not enable whole-component joining. Incompatible targets retain ordinary overwrite behavior. Overwriting splits disconnected leftovers using four-neighbor connectivity; the largest piece keeps its ID, with topmost then leftmost order breaking ties.

**X deletes what is selected, never what is merely hovered.** Deletion, cutting, copying, movement, blueprint capture and property edits always operate on complete components. Snapshots trim outside whitespace while preserving gaps between selected components. Moves preserve IDs; paste and move reject occupied or out-of-bounds destinations.

The Tools section contains Pointer, Draw, Merge, and Split. A **Merge** button appears below the canvas when at least two selected components have the same exact ink, compatible settings, and a connected group. It merges them directly and selects the result. The Merge tool also lets you pick complete regions by clicks and confirm with G or the action bar.

**Split follows a grid-edge polyline.** Drag from an indicated grid vertex, turn along cell edges, and release to split every component actually cut into disconnected regions, independent of the selection. The line is a temporary preview and never deletes cells or creates saved isolation edges. Each component's largest result keeps its ID; ties use topmost then leftmost order. Other results get fresh IDs. Retracing the tail removes its segments immediately, including across turns; draw in another direction to replace the removed tail. Returning along the whole path to its start leaves an empty line, so releasing makes no edit and shows no failure hint. Crossings, closed loops, and a different route back to an earlier vertex stay intact. Lines across multiple components are supported. An incomplete line that leaves a component connected does nothing and shows a hint; endpoints are never extended automatically. Every successful line is one undo step, selects the resulting pieces, and keeps Split active for the next cut. Undo during a line cancels only that line; undo/redo in idle Split works immediately and keeps the tool active. Right-click or Q returns to Pointer while preserving completed cuts.

Right-click or Q cancels unfinished drawing, movement, selection or merge operations and restores the previous selection and document. A second cancel in idle Pointer clears the selection. The inspector edits whole components and displays mixed values for compatible multi-selections; use Split before editing a portion independently. In Draw, inspector settings are defaults for new strokes. Text fields and modal windows own their keyboard input, so typing X, Q, or other editing letters cannot change the canvas. Esc, Del, Backspace, Enter, and Ctrl+U are not canvas commands. Runtime state stays separate from editable data; simulation locks design edits while retaining Latch clicks.

Running simulation frames follow the UI display cadence, with at most one queued or active poll. Simulation ticks advance independently in Rust; display updates show the latest state rather than replaying intermediate ticks. Pausing stops periodic polling, and control commands apply their returned state immediately.

Same-ink components with different IDs do not merge or conduct directly; another physical route may still connect separate components.

Trace has eight colors: yellow, red, green, blue, cyan, magenta, orange, and white. A single blue Bus carries eight independent Trace-color channels. Attach a Trace directly to a Bus, then connect its other end to Read or Write. Read ORs zero or more logic/Write sources into exactly one Trace component; Write takes exactly one Trace component and fans out to zero or more logic/Read sinks. Direct port connections run from Write to Read. An undriven channel stays low. Every Bus channel allows at most one Read and any number of Writes; pure Trace networks may OR multiple Reads. Ports count Trace component IDs, even when separate traces connect electrically elsewhere.

Cross carries all eight colors on independent horizontal and vertical axes, including Bus-to-Bus and Bus-to-Trace connections. Runtime Bus/Cross brightness indicates whether any carried channel is high. Older colored Bus tool IDs remain readable and normalize to the unified Bus in boards and blueprints; existing numeric tool IDs and the v2 project format are preserved.

Blueprints are flat ink snapshots saved with the current project. Save a selection in the inspector or save a clipboard item; the Blueprints panel supports search, rename, and delete. Clicking a blueprint copies its snapshot into clipboard history while keeping the panel open. Each Ctrl+V starts an ordinary paste preview, and each placement remaps every internal component to a fresh ID while preserving its grouping as editable cells. Confirming a paste returns to Pointer and selects the newly placed components; right-click or Q cancels the preview. Blueprint management and placement support undo/redo.

The toolbar's 2D / 2.5D control applies to the board and both preview libraries and remembers the choice on this device. At 12 CSS pixels per cell and above, the board and previews show ink symbols; all Trace variants use only their color at every zoom level. Between 2 and 12 pixels they use color chunks with batched depth in 2.5D. Live color chunks update in the same draw as detailed cells; their cached palettes and exposed depth faces avoid rebuilding geometry for every runtime frame. Below 2 pixels both modes use area-weighted color and coverage maps. Overview workers retain chunk geometry, receive state-only updates, and rebuild color ancestors only when the current view requests them. Runtime frames start overview work before the next draw. The sparse 64-cell chunk index and worker-built color pyramid update affected chunks and ancestors; a shared 64 MiB LRU bounds color raster and thumbnail caches. Zoom uses proportional steps around the pointer.

## Example projects

[Hello, World! 5脳8 character display](Frontend/Assets/Examples/HelloWorld5x8.ocb) is a complete editable circuit that cycles through the text one character at a time. Open it in the desktop app, zoom out around the display to about 9%, set 16 TPS, and run. See the [example guide](Frontend/Assets/Examples/README.md) for viewing, timing, circuit structure, and regeneration with `make examples`.

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

`frontend-test` builds the frontend, runs editor unit tests, and exercises the rendered production UI in Edge on Windows or Chromium on Linux. Captures are written under `build/`; inspect `InterfaceCapture.png`, `PointerPropertiesCapture.png`, `ComponentMarqueeCapture.png`, `ShiftMultiSelectCapture.png`, `MergeActionsCapture.png`, `DrawMergeCapture.png`, `SplitPathCapture.png`, `SplitBacktrackCapture.png`, `SplitFlatPreviewCapture.png`, `SplitDepthPreviewCapture.png`, and the relevant rendering/clipboard captures.

`native-test` builds and tests the real Tauri app, its simulation controls, and archive IPC. On Windows, `test-tools` installs `tauri-driver` and matching EdgeDriver into `build/TestTools`. Linux also needs `WebKitWebDriver` (the `webkit2gtk-driver` package on Debian/Ubuntu), and a display or Xvfb. Native captures include `DesktopCapture.png`, `DesktopSimulationCapture.png`, `DesktopComponentLanesCapture.png`, `DesktopComponentMergeCapture.png`, `DesktopPointerInteractionCapture.png`, `DesktopDrawMergeSplitCapture.png`, and `DesktopSplitBacktrackCapture.png`. Use `make native-ui-test` to test an already-built Release binary without rebuilding it.

`test` runs Rust workspace tests, a frontend production build, unit tests, and browser tests. CI defines Windows and Linux validation and packaging separately.

Rendered runtime refresh tests cover detail, color, and aggregate views in both display modes on a 131,072-cell board. Per-transition latency measurements and captures are written to `build/LodRefresh-*`; assertions check actual WebGL color changes, with reset, editing, and return-to-design coverage in unit and native tests.

The core tests replay 502 unchanged recorded C++ state/delta comparisons, with explicit replacement compilation assertions for fourteen historical sessions affected by the new port rules, plus component identities, independent adjacent lanes, snapshots, clock/latch behavior, graph ordering, project compatibility, and worker lifecycle tests. The default mixed benchmark uses 1024x1024 cells and 256 pipelines. The migration gate is 90% of the measured legacy baseline; the separate historical 100K TPS target has not been reached. See `Backend/Core/Tests/Fixtures/LegacyBaseline.md`. Pass `CORE_BENCHMARK_ARGS="--quick"` for a short run. `board-benchmark` also accepts `BOARD_BENCHMARK_ARGS="--editorProbe"`.

## Project format

`.ocb` files remain ZIP archives with `project.json` and `formatVersion: 2`. Grid bounds, per-cell clock settings, latch initial states, and editor defaults are preserved. Loading completes validation before replacing the open board. Every occupied tile must have a positive int32 `componentId`. Cells sharing an ID must have the same exact ink, compatible Latch initial state or Clock interval, and form one four-neighbor connected region. The optional top-level `blueprints` array contains `{ id, name, width, height, tiles }` snapshots using relative coordinates, explicit clock parameters, and snapshot-local component IDs. Empty blueprints are invalid.

Missing component IDs and unknown inks produce ordinary board or blueprint validation errors; IDs are never inferred when loading old files. Isolation edges are removed. Numeric tool IDs retain their values; ID 14 remains undefined. Native project IPC exchanges `{ board, blueprints }`; simulation receives the board alone. Binary compile input uses version **3** with a 24-byte header followed by four int32 arrays: kinds, initial states, clock intervals, and component IDs (zero for empty cells). Runtime frames retain their existing format. Display mode is stored in application-origin localStorage and stays outside project files. Recent projects are stored in `RecentProjects.json` in the native application data directory.
