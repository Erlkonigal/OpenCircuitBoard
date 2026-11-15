---
name: frontend-tests
description: Validate OpenCircuitBoard editor interactions, blueprints, 2D/2.5D and low-zoom PixiJS rendering, native IPC, and simulation controls with relevant unit, browser, and Tauri tests plus inspected captures.
---

# Frontend Tests

Follow [platform-shell](../platform-shell/SKILL.md) before running commands. Use `make` from the repository root, with native PowerShell/MSVC on Windows or native Linux Bash.

The editor uses React and Mantine, renders the board and previews with PixiJS, and receives native simulation frames from Rust through Tauri. Frontend tests live in `Frontend/Tests/`; core regressions live in `Backend/Core/Session.rs` and `Backend/Core/Tests/`.

## Select validation by the change

For editor behavior, layout, properties, clipboard, blueprints, display mode, canvas boundaries, or rendering changes:

```powershell
make frontend-test TARGET_PLATFORM=windows
```

This builds the production frontend, runs unit tests, and runs rendered browser workflows. Windows uses installed Edge; Linux uses Playwright Chromium and `TARGET_PLATFORM=linux`. Browser tests use port 1421; development uses port 1420. Unit assertions alone do not validate the rendered canvas.

For simulation core or worker timing changes, also run:

```powershell
make core-test TARGET_PLATFORM=windows
```

For simulation controls, runtime colors, archive services, or native IPC changes, also validate the actual desktop app:

```powershell
make test-tools TARGET_PLATFORM=windows
make native-test TARGET_PLATFORM=windows
```

`native-test` builds the Release app and runs WebDriver workflows against `build/Backend/release/OpenCircuitBoard.exe` on Windows or the extensionless Linux binary. Use `make native-ui-test` only when that binary already includes the current frontend and backend changes. Windows needs matching EdgeDriver and WebView2; Linux needs `WebKitWebDriver` and a display or Xvfb. `test-tools` installs drivers in `build/TestTools/`; on Linux provide the system WebKit driver separately.

For a focused browser rerun after a relevant failure, use the existing make filter, for example:

```powershell
make browser-test TARGET_PLATFORM=windows FRONTEND_TEST="Tests/Browser/BlueprintRendering.spec.ts"
```

`make test` covers Rust workspace, unit, and browser tests; it does not include native desktop tests. Run checks relevant to the change rather than treating every skill or documentation edit as requiring all suites.

## Behavior to preserve

Choose the cases touched by the change:

- Blueprints are flat, independent ink snapshots saved in the project. Test selection/clipboard capture, repeated ordinary Ctrl+V placement, panel selection, rename/delete, undo/redo, and archive round trips when affected. Placement produces editable cells without a hierarchy.
- The board, clipboard, blueprints, and paste previews share display and LOD behavior. At 12 CSS pixels per cell and above show symbols; from 2 to 12 use color chunks; below 2 use aggregate color/coverage textures. Verify both 2D and 2.5D, persistent display mode, and updates after edits or runtime frames when affected.
- For large or sparse boards, verify bounded rendered objects and visible color updates, including negative coordinates. Wait for `data-render-ready="true"` and, for worker-built colors, `data-color-ready="true"` before a capture. Use `data-lod` and the existing rendering tests to check the active path; a screenshot alone cannot establish scalability.
- For joined 2.5D cells, inspect continuous side faces, contacts, directional gradient shadows, and selection/paste layering at relevant zoom levels. Keep the standard PixiJS renderer and current desktop configuration during validation.
- Runtime state must remain separate from editable tiles and blueprint snapshots. Check that Back to design restores editable colors, including aggregate textures.
- For scheduler or TPS changes, test actual tick progression and measured throughput at slow positive rates, including 1-4 TPS, as well as bounded catch-up and full-speed responsiveness. Low-rate sampling must include a tick before publishing a new measurement. Check pause/resume and rate changes so idle time and previous samples do not distort throughput. Prefer deterministic core tests using the worker's explicit `Instant` argument, plus a native regression proving the UI advances and retains throughput between ticks.

## Inspect captures

All generated captures and reports stay under root `build/`. Test configuration uses `Frontend/Tests/Paths.ts` to resolve that directory. Keep dependencies in `build/Dependencies/node_modules/` via `make init`; do not create source-local dependency folders, caches, `dist`, or `target` directories.

Open captures relevant to the change with the image viewer before handoff. Current workflows include:

| Area | Captures under `build/` |
| --- | --- |
| Workspace and inspector | `InterfaceCapture.png`, `SidebarCapture.png`, `ClockSettingsCapture.png`, `SelectionSettingsCapture.png` |
| Selection and placement | `SelectionCapture.png`, `PastePreviewCapture.png`, `PastedLayeringCapture.png`, `BoardEdgeCapture.png`, `CanvasResizeCapture.png` |
| Joined cells and depth | `ContinuousTilesCapture.png`, `TileShapesCapture.png`, `JoinedTilesCapture.png`, `JoinedPreviewCapture.png` |
| Blueprints, display mode, LOD | `BlueprintLibraryCapture.png`, `FlatPreviewCapture.png`, `MillionCellOverviewCapture.png`, `LargeClipboardPreviewCapture.png`, `ColorOnlyCapture.png`, `SparseOverviewCapture.png` |
| Native runtime | `DesktopCapture.png`, `DesktopSimulationCapture.png`, `DesktopLatchCapture.png`, `DesktopLodSimulationCapture.png`, `DesktopLodDesignCapture.png` |
| Low-speed simulation | `DesktopLowSpeed1Capture.png` through `DesktopLowSpeed4Capture.png` |

Additional capture names are defined in `Frontend/Tests/Browser/` and `Frontend/Tests/Desktop/`. Treat a blank native canvas, missing geometry, stale colors, or a non-advancing simulation as a failure even if labels and IPC assertions pass. Report core, browser, and native results separately, with any checks that could not run.
