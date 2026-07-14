---
name: frontend-visual-validation
description: Generate and inspect Godot frontend captures using `scripts/visualCapture.gd`. Use for frontend editor, rendering, tile, selector, board-boundary, or interaction changes before handoff.
---

# Frontend Visual Validation

Run `scripts/visualCapture.gd` to produce a representative board image at `user://capture.png`. Treat visual inspection of that image as a required validation result, not as a substitute for relevant automated tests.

## Capture

1. Read `.codex/skills/platform-shell/SKILL.md` and select the required `targetPlatform` shell.
2. Build the selected target with `make build targetPlatform=<linux|windows>`.
3. Run the selected target's Godot executable headlessly:

```bash
"build/tools/godot-4.7/Godot_v4.7-stable_<platform-executable>" --headless --path . --script scripts/visualCapture.gd
```

Use `linux.x86_64` for Linux and `win64.exe` for Windows. The script prints the Godot user-data directory; open `<user-data-directory>/capture.png` with the image viewer.

Run one additional capture before image inspection when the changed surface requires it:

- Use `-- --captureSelector` for selector appearance or positioning.
- Use `-- --captureBoardEdge` for board boundary behavior.

## Inspect

- Confirm all placed tiles render, are fully visible, and keep their intended depth order.
- Check tile shadows and the isolated gate for clipping or incorrect silhouettes.
- For selector captures, check its visibility, placement, and relationship to the selected tile.
- For board-edge captures, check that the board remains framed correctly at its boundary.
- Compare the image directly against the changed visual behavior; report observed defects or state that the applicable checks passed.

