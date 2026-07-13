# OpenCircuitBoard

OpenCircuitBoard is a Godot 4.7 circuit-board editor with a native simulation backend shell.

The editor uses a compact, flat workbench with a two-row command bar, a component library on the left, a live inspector on the right, and a hex-pattern circuit canvas in the center. Components use soft projected shadows to remain legible over the board.

Choose Wire, OR Gate, or Processor from the component library. Use the left mouse button to place the selected component, the right mouse button to remove it, the middle mouse button to pan, and the mouse wheel to zoom. The simulation controls are visible for the intended workflow, but remain disabled until the native simulation backend exposes runtime commands.

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
