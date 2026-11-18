---
name: platform-shell
description: Run OpenCircuitBoard build, test, package, and toolchain diagnostics through make with native Windows PowerShell/MSVC or native Linux Bash, keeping dependencies and generated output under build/.
---

# Platform Shell

Select the native environment from `TARGET_PLATFORM`. The root `Makefile` defaults to the host platform. Check `Makefile`, `scripts/Command.ps1`, and `scripts/Command.sh` when changing commands or output routing.

## Windows

Use native Windows PowerShell from the repository root with a compatible GNU Make. If the executable is named `mingw32-make`, use that command in place of `make`.

```powershell
make check-platform TARGET_PLATFORM=windows
make init TARGET_PLATFORM=windows
make build TARGET_PLATFORM=windows BUILD_TYPE=Release
```

Windows recipes dispatch to `scripts/Command.ps1`, which loads `scripts/Platform.ps1`. The helper discovers Visual Studio Build Tools with `vswhere`, imports its real x64 Developer PowerShell environment, and validates:

- Standard x64 Windows Node.js and `npm.cmd`.
- `cl.exe` and `link.exe` from the selected Visual Studio installation, with `rc.exe` from its Windows SDK.
- Rust `stable-x86_64-pc-windows-msvc` and the `x86_64-pc-windows-msvc` host.

Visual Studio Build Tools with Desktop development with C++ and a Windows SDK are sufficient. Keep Windows builds, core tests, benchmarks, and packaging on MSVC.

For a one-off native command, load the same environment in that PowerShell process first:

```powershell
. ./scripts/Platform.ps1 -TargetPlatform windows
```

Use native Windows paths and PowerShell's call operator for quoted executable paths. Launch background helpers with hidden windows unless the user needs an interactive window.

## Linux

Use native Linux Bash from the repository root. `scripts/Platform.sh` verifies `uname -o` is `GNU/Linux`, the Linux Rust host, and Linux Node.js before dispatch:

```bash
make check-platform TARGET_PLATFORM=linux
make init TARGET_PLATFORM=linux
make build TARGET_PLATFORM=linux BUILD_TYPE=Release
```

Use Linux toolchains and Tauri's WebKitGTK 4.1 dependencies. Report an unavailable native target instead of substituting a different host environment.

## Workspaces and generated files

The editor uses React, TypeScript, Mantine, and PixiJS in `Frontend/`; Rust simulation and the Tauri host live in `Backend/`. The dispatchers select these working directories automatically.

Install locked dependencies with `make init`. `Frontend/Tools/Command.mjs` resolves frontend tools from `build/Dependencies/node_modules/`; keep dependency folders and links out of both source workspaces. Keep npm manifests and lockfiles in `Frontend/`, and the Cargo workspace and lockfile in `Backend/`.

| Generated content | Repository-relative destination |
| --- | --- |
| npm dependencies | `build/Dependencies/node_modules/` |
| Production frontend | `build/Frontend/` |
| Cargo intermediates, binaries, bundles | `build/Backend/` |
| Tauri schemas | `build/Backend/TauriSchemas/` |
| Vite/Vitest caches | `build/Cache/` |
| Test drivers | `build/TestTools/` |
| Captures and test reports | `build/` and its test subdirectories |

The root `.cargo/config.toml` controls Cargo output even for direct Cargo/Tauri commands. Frontend output and caches are configured in `Frontend/Vite.config.ts`; `Backend/Desktop/tauri.conf.json` loads the built frontend, and `Backend/Desktop/Build.rs` relocates generated Tauri schemas. Keep these paths aligned when changing build configuration.

## Choose the required target

- `make run BUILD_TYPE=Debug` starts Vite and the Tauri development app. Release builds and runs the standalone app.
- `make format` formats the Rust workspace; `make core-test` tests `ocb-core`.
- `make frontend-test` builds the frontend, runs unit tests, and runs rendered browser tests. Use [frontend-tests](../frontend-tests/SKILL.md) for validation and captures.
- `make test` runs Rust workspace, frontend unit, and rendered browser checks; native desktop tests are separate.
- `make test-tools` prepares platform WebDriver tooling. `make native-test` builds the Release app and tests it; `make native-ui-test` reuses an already-current Release binary.
- `make package` creates NSIS on Windows or AppImage on Linux.
- `make clean` removes `build/`, including installed npm dependencies and test tools; initialize them again before dependent commands.
