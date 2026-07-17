# OpenCircuitBoard

OpenCircuitBoard is a Godot 4.7 circuit-board editor with a native simulation backend shell.

The editor uses compact, switchable Dock panels on both sides of a hex-pattern circuit canvas. Each side can show Circuit Editor, Clipboard, or Event Log; selecting the Dock already shown on the opposite side swaps the two panels so a class is never duplicated. Components use soft projected shadows to remain legible over the board.

Choose an Ink from Circuit Editor, then left-click to place it or drag with the left button to place continuously. Hold Shift while dragging with the left button to draw a marquee selection; drag anywhere inside its rectangular bounds, including empty cells, to move it. Drag with the right button to delete continuously. Ctrl+C and Ctrl+X respectively copy or cut the selection into a four-item Clipboard history; choose the history item in the Clipboard dock that Ctrl+V should preview under the pointer. Left-click confirms a paste, while right-click or Esc cancels it; the middle mouse button still pans the view during the preview. Ctrl+Z undoes and Ctrl+U redoes edits. Use the mouse wheel to zoom.

## Build

Initialize the third-party submodule, then select the target platform:

```bash
make init
make frontend targetPlatform=linux
make backend targetPlatform=linux
make coreBenchmark targetPlatform=linux
```

Run Windows targets from an MSYS2 UCRT64 Bash shell:

```bash
make frontend targetPlatform=windows
make backend targetPlatform=windows
make coreBenchmark targetPlatform=windows
```

`make build targetPlatform=<linux|windows>` runs both shell targets. `make clean` removes generated build output.

`coreBenchmark` defaults to a 1024x1024 board with 512 continuously toggling pipelines and reports median TPS against the 100K target. Use `coreBenchmarkArgs="--quick --compare-ordering"` for the legacy-sized graph-ordering comparison.
