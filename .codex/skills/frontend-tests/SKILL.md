---
name: frontend-tests
description: Validate the React workspace, PixiJS canvas, and Tauri simulation with behavior tests and inspected captures when changing editor layout, components, inspector, clipboard, canvas boundaries, or interactions.
---

# Frontend Tests

Read `.codex/skills/platform-shell/SKILL.md` first. Use `make` on both platforms: native Windows PowerShell/MSVC or native Linux Bash.

## Run

From the repository root:

```powershell
make frontend-test TARGET_PLATFORM=windows
```

```bash
make frontend-test TARGET_PLATFORM=linux
```

This builds the production frontend and runs unit and rendered browser workflows. Frontend manifests, configuration, source, assets, and UI tests live under `Frontend/`; the make dispatcher selects that working directory automatically. Native tests launch `Backend/target/release/OpenCircuitBoard` (with `.exe` on Windows). Capture paths resolve against the repository root and stay in `build/`. Windows uses installed Edge; Linux uses Playwright Chromium. Unit assertions do not validate the canvas.

For IPC, native project services, runtime rendering, or simulation controls, also run:

```powershell
make test-tools TARGET_PLATFORM=windows
make native-test TARGET_PLATFORM=windows
```

Linux uses the corresponding `TARGET_PLATFORM=linux` targets, `WebKitWebDriver`, and a display or Xvfb. `test-tools` installs Tauri WebDriver into `build/TestTools`; Windows also downloads the driver matching installed Edge. Native validation is separate from browser validation.

## Inspect

Open the relevant captures with the image viewer before handoff:

- `build/InterfaceCapture.png` and `build/SidebarCapture.png`: layout, component visibility, readable labels, inspector, and toolbar at 1280x720.
- `build/Capture.png` and `build/SelectorCapture.png`: glyphs, colors, shadows, depth order, and hover placement.
- `build/SelectionCapture.png`, `build/PastePreviewCapture.png`, and `build/PastedLayeringCapture.png`: selected cells, preview validity, and placement.
- `build/BoardEdgeCapture.png` and `build/CanvasResizeCapture.png`: fitted bounds, zoom, corner handles, and resizing.
- `build/ClockSettingsCapture.png`, `build/SelectionSettingsCapture.png`, `build/TraceColorCapture.png`, and `build/BusColorCapture.png`: inspector settings.
- `build/DesktopCapture.png` and `build/DesktopSimulationCapture.png`: actual Tauri rendering and runtime states.

Fix observed defects and report the checks actually completed. Treat a blank native canvas as a failure even when IPC and toolbar assertions pass.
