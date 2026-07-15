# OpenCircuitBoard

OpenCircuitBoard is a Godot 4.7 circuit-board editor with a native simulation backend shell.

The editor uses a compact CircuitEditorDock with categorized Inks on the left and a hex-pattern circuit canvas on the right. Components use soft projected shadows to remain legible over the board.

Choose an Ink from CircuitEditorDock, then left-click to place it or drag with the left button to place continuously. Hold the left button still to draw a marquee selection; drag anywhere inside its rectangular bounds, including empty cells, to move it. Drag with the right button to delete continuously. Ctrl+C and Ctrl+X respectively copy or cut the selection into a four-item Clipboard history; choose the history item in the Clipboard dock that Ctrl+V should preview under the pointer. Left-click confirms a paste, while right-click or Esc cancels it; the middle mouse button still pans the view during the preview. Ctrl+Z undoes and Ctrl+U redoes edits. Use the mouse wheel to zoom. Ink selection and array settings are ready for future simulation backend commands.

## Build

Initialize the third-party submodule, then select the target platform:

```bash
make init
make frontend targetPlatform=linux
make backend targetPlatform=linux
```

Run Windows targets from an MSYS2 UCRT64 Bash shell:

```bash
make frontend targetPlatform=windows
make backend targetPlatform=windows
```

`make build targetPlatform=<linux|windows>` runs both shell targets. `make clean` removes generated build output.
