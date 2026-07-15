---
name: frontendTests
description: Run and inspect split Godot frontend test scenarios through scripts/tests/frontendTest.gd. Use for frontend editor, rendering, tile, selector, board-boundary, or interaction changes before handoff.
---

# Frontend Tests

`scripts/tests/frontendTest.gd` is the real-renderer runner for independent scenarios in `scripts/tests/`. It runs the complete behavior suite and the default board scenario when no selector is supplied, then writes `user://capture.png`. Keep each scenario's setup and assertions in one `scripts/tests/*Test.gd` file; keep shared startup, selection, image output, and process exit in the runner. Treat direct inspection of the resulting image as required validation, not as a substitute for relevant automated tests.

## Capture

1. Read `.codex/skills/platform-shell/SKILL.md` and select the required `targetPlatform` shell.
2. Build the selected target with `make build targetPlatform=<linux|windows>`.
3. Run the selected target's Godot executable with a real rendering backend. Do not pass `--headless`: it uses the dummy renderer, which cannot read the `SubViewport` texture needed for capture.

```bash
"build/tools/godot-4.7/Godot_v4.7-stable_<platform-executable>" --rendering-method gl_compatibility --path . --script scripts/tests/frontendTest.gd
```

Use `linux.x86_64` for Linux and `win64.exe` for Windows. The script prints the Godot user-data directory; open `<user-data-directory>/capture.png` with the image viewer.

Pass `-- --frontendTest=<camelCaseId>` to run exactly one registered scenario, for example `-- --frontendTest=selector`. Existing `--captureX` arguments remain compatibility aliases.

Run one additional capture before image inspection when the changed surface requires it:

- Use `-- --frontendTest=selector` (or `--captureSelector`) for selector appearance or positioning.
- Use `-- --frontendTest=boardEdge` (or `--captureBoardEdge`) for board boundary behavior.

## Inspect

- Confirm all placed tiles render, are fully visible, and keep their intended depth order.
- Check tile shadows and the isolated gate for clipping or incorrect silhouettes.
- For selector captures, check its visibility, placement, and relationship to the selected tile.
- For board-edge captures, check that the board remains framed correctly at its boundary.
- Compare the image directly against the changed visual behavior; report observed defects or state that the applicable checks passed.
