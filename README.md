# OpenCircuitBoard

OpenCircuitBoard is a Godot 4.7 circuit-board editor with a native simulation backend shell.

The editor uses compact, switchable Dock panels on both sides of a hex-pattern circuit canvas. Each side can show Circuit Editor, Clipboard, or Event Log; selecting the Dock already shown on the opposite side swaps the two panels so a class is never duplicated. Components use soft projected shadows to remain legible over the board.

Choose an Ink from Circuit Editor, then left-click to place it or drag with the left button to place continuously. Hold Shift while dragging with the left button to draw a marquee selection; drag anywhere inside its rectangular bounds, including empty cells, to move it. Drag with the right button to delete continuously. Ctrl+C and Ctrl+X respectively copy or cut the selection into a four-item Clipboard history; choose the history item in the Clipboard dock that Ctrl+V should preview under the pointer. Left-click confirms a paste, while right-click or Esc cancels it; the middle mouse button still pans the view during the preview. Ctrl+Z undoes and Ctrl+U redoes edits. Use the mouse wheel to zoom.

## Build

Initialize the third-party submodule, then select the target platform:

```bash
make init
make build-release TARGET_PLATFORM=linux
make core-benchmark TARGET_PLATFORM=linux
```

Build the editor-facing debug variant when running the project from Godot:

```bash
make build-debug TARGET_PLATFORM=linux
```

Run Windows targets from an MSYS2 UCRT64 Bash shell:

```bash
make build-release TARGET_PLATFORM=windows
make core-benchmark TARGET_PLATFORM=windows
```

`make build TARGET_PLATFORM=<linux|windows> BUILD_TYPE=<Debug|Release>` builds one GDExtension variant. The `build-debug` and `build-release` shortcuts write separate artifacts that match the debug and release entries in `OcbSimulation.gdextension`. `make clean` removes generated build output.

`core-benchmark` defaults to a 1024x1024 board with 256 continuously toggling pipelines and reports median TPS against the 100K target. Use `CORE_BENCHMARK_ARGS="--quick --compare-ordering"` for the legacy-sized graph-ordering comparison.
