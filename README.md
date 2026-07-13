# OpenCircuitBoard

OpenCircuitBoard is a Godot 4.7 circuit-board editor with a native simulation backend shell.

The editor provides a pan-and-zoom grid, component placement and removal, and a compact component library. Use the left mouse button to place a selected component, the right mouse button to remove it, the middle mouse button to pan, and the mouse wheel to zoom.

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
