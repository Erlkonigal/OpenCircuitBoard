# OpenCircuitBoard Working Agreement

## Project Rules

- Use PascalCase for project-owned filenames, resource names, type names, script members, scene nodes, shader uniforms, and static constants. Use lowerCamel for functions, signals, parameters, local variables, IDs, JSON keys, config keys, and dynamic method names. Preserve Godot and tool-required names, including built-in snake_case properties and skill naming conventions.
- Keep the runtime editor, rendering, dialogs, ZIP handling, and project format in GDScript. Native code is limited to the `OcbSimulation` `RefCounted` GDExtension backend.
- `thirdparty/godotcpp` is the only external source dependency and must remain a Git submodule. Do not vendor generated Godot bindings.

## Build And Validation

- Use `make` targets for normal configure, build, test, and clean workflows. Native builds require matching Godot 4.7 headers, `g++`, CMake, and SCons.
- Validate frontend editor, rendering, or interaction changes with `scripts/tests/FrontendTest.gd`; inspect the resulting `user://capture.png` before handoff.
- Run the relevant validation before handing work over. Each completed work session must finish with a Git commit whose subject is a title and whose body begins on line two with a concise summary of the completed work.
- Preserve user changes in a dirty worktree; do not reset or discard them.

## Shell And Platform

- Use Bash syntax for project commands. Commands must work in both Linux and MSYS2 environments.
- Before build, test, configure, package, or platform diagnostics, read and follow `.codex/skills/platform-shell/SKILL.md`.
- Select the execution shell from the requested `TARGET_PLATFORM`, not from whichever `bash` executable is available. Inspect the Makefile when no target is specified.
- Run Linux targets in native Linux Bash. Verify `uname -o` reports `GNU/Linux` before Linux-native work.
- Run Windows targets only in an MSYS2 UCRT64 Bash environment. Verify `MSYSTEM=UCRT64`, `uname -o` reports `Msys`, and `make`, `g++`, and `scons` resolve from MSYS2 before native Windows work.
- Use `C:\msys64\msys2_shell.cmd -defterm -here -no-start -ucrt64` to bootstrap UCRT64 when the host runner is not already in that environment. Use cmd.exe only for this bootstrap; execute project commands inside UCRT64 Bash.
- Do not run Windows-native commands through a bare `bash`, WSL, Git Bash, or simulated UCRT64 environment variables.
- Use `/c/` drive access in MSYS2 and `/` paths in Linux.
