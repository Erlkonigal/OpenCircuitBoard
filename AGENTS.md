# OpenCircuitBoard Working Agreement

## Project Rules

- Use PascalCase for project-owned filenames, resource names, type names, members, and static constants. Use lowerCamel for functions, parameters, local variables, IDs, JSON keys, and config keys. Preserve tool-required names and skill naming conventions.
- Implement the editor in React and TypeScript, UI controls in Mantine, and the board renderer in PixiJS. Tauri hosts the desktop app; Rust owns simulation, project archives, and native services.
- Keep frontend source, assets, npm manifests, configuration, and UI tests in `Frontend/`. Keep the Cargo workspace, simulation core, native services, and backend fixtures in `Backend/`. Root build scripts coordinate both workspaces.
- Keep the simulation core independent of Tauri. Preserve `.ocb` formatVersion 2 and the stable tool IDs. Keep runtime state separate from editable project data.
- Keep installed npm dependencies in `build/Dependencies/node_modules/`; do not create dependency directories or links inside `Frontend/` or `Backend/`.
- Put frontend build assets in `build/Frontend/`, Cargo/Tauri build output in `build/Backend/`, and generated test reports/captures under root `build/`. Keep the configured output paths aligned across scripts, tests, and CI.
- Use locked npm and Cargo dependencies. Do not vendor dependency source or generated bindings.

## Build And Validation

- Use `make` for normal initialization, build, run, package, test, benchmark, and clean workflows on both Windows and Linux.
- Before build, test, configure, package, or platform diagnostics, read and follow `.codex/skills/platform-shell/SKILL.md`.
- Validate editor, rendering, selector, board-boundary, and interaction changes using `.codex/skills/frontend-tests/SKILL.md`; inspect the relevant generated captures before handoff.
- Run relevant validation before handing work over. Report native and browser validation separately. Each completed work session must finish with a Git commit whose subject is a title and whose body contains a concise summary of completed work.
- Preserve user changes in a dirty worktree; do not reset or discard them.

## Shell And Platform

- Select the native execution environment from `TARGET_PLATFORM`; make defaults to the native host platform.
- Run Windows targets from native PowerShell using native Windows `make.exe`, standard Windows Node.js, and `x86_64-pc-windows-msvc` Rust. `scripts/Platform.ps1` loads the real x64 Visual Studio Developer PowerShell environment and checks MSVC and Windows SDK paths.
- Windows make recipes dispatch to `scripts/Command.ps1`. Do not use MSYS2, UCRT64, MinGW, Git Bash, WSL, or fabricated platform environment variables for Windows work.
- Run Linux targets in native Linux Bash. `scripts/Platform.sh` verifies `uname -o` is `GNU/Linux` and checks the Linux Rust and Node hosts; make recipes dispatch to `scripts/Command.sh`.
- Keep scripts compatible with the native platform. Use native Windows paths in PowerShell and POSIX paths in Linux Bash.
