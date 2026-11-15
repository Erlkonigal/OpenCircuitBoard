---
name: platform-shell
description: Select and validate native PowerShell with the MSVC toolchain for Windows, or native Bash for Linux, before project builds, tests, packaging, and platform diagnostics.
---

# Platform Shell

Choose the execution environment from the requested target. Windows uses native PowerShell and MSVC; Linux uses native Bash. Windows work must not depend on MSYS2, UCRT64, MinGW, Git Bash, or WSL.

## Windows

Run from the repository root in native Windows PowerShell:

```powershell
make check-platform TARGET_PLATFORM=windows
make build TARGET_PLATFORM=windows BUILD_TYPE=Release
make core-test TARGET_PLATFORM=windows
make frontend-test TARGET_PLATFORM=windows
```

Native Windows `make.exe` dispatches recipes to `scripts/Command.ps1`. The dispatcher runs npm from `Frontend/`, Cargo from `Backend/`, and Tauri from `Backend/Desktop/`; npm dependencies go to `build/Dependencies/node_modules/` through the frontend command runner and build output goes to root `build/Frontend/` and `build/Backend/` through Vite and the root Cargo configuration. That entrypoint loads `scripts/Platform.ps1`, discovers Visual Studio Build Tools through `vswhere`, and imports the x64 Developer PowerShell environment without changing the working directory or opening a window. A complete Visual Studio IDE is unnecessary.

Before native work, the platform helper must confirm:

- `make.exe` comes from a native Windows installation, such as Chocolatey, and does not require MSYS2.
- `cl.exe` and `link.exe` belong to the selected Visual Studio installation, and `rc.exe` belongs to the Windows SDK.
- Rust reports `host: x86_64-pc-windows-msvc`; use the installed MSVC Rust toolchain for core tests and benchmarks as well as Tauri builds.
- Node.js is the standard Windows build, not an MSYS2/GNU shared-library build; invoke `npm.cmd` from PowerShell.

For a one-off command, dot-source `.\scripts\Platform.ps1 -TargetPlatform windows` first, then run the native command in that PowerShell process. Quote executable paths and use PowerShell's call operator. Do not bootstrap UCRT64, use `/c/` paths, or substitute GNU tools when a required MSVC component is missing.

## Linux

Use the host's native Bash. Verify `uname -o` reports `GNU/Linux` and the Rust host is a Linux target before native work:

```bash
make check-platform TARGET_PLATFORM=linux
make build TARGET_PLATFORM=linux BUILD_TYPE=Release
make frontend-test TARGET_PLATFORM=linux
```

Use Linux Node, Cargo, compiler, and WebKitGTK dependencies. Do not invoke Windows executables or use WSL to stand in for a requested native Windows build.

## Target Selection

- `scripts/Command.ps1` defaults to Windows; `make` defaults to the host platform and dispatches to its native entrypoint.
- Use `-TargetPlatform windows` for PowerShell and `TARGET_PLATFORM=linux` for Bash when the target needs to be explicit.
- Report missing tools or a target mismatch. Keep the chosen native environment for configuration, compilation, tests, and packaging.