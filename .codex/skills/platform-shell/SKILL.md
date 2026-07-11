---
name: platform-shell
description: Run project commands in the correct Linux Bash or MSYS2 UCRT64 shell. Use when a build, test, configure, package, or diagnostic command must select and validate its execution platform, especially when a Windows host runner could resolve a bare Bash command to WSL instead of UCRT64.
---

# Platform Shell

Select the shell from the requested build target, not from the shell that happens to be available.

## Select The Target

- Use the Linux procedure for `targetPlatform=linux` or a task explicitly targeting Linux.
- Use the UCRT64 procedure for `targetPlatform=windows`, native Windows builds, or a Makefile whose selected default target is Windows.
- Inspect the project's Makefile and instructions when the target is omitted. Do not infer the target from a bare `bash` executable.

## Run Linux Commands

- Run commands in the host's native Bash environment.
- Verify `uname -o` reports `GNU/Linux` before Linux-native work.
- Do not use an MSYS2 compiler or Windows Godot executable for a Linux target.

## Run UCRT64 Commands

- Run commands directly when the current shell reports `MSYSTEM=UCRT64` and `uname -o` reports `Msys`.
- When the host runner is PowerShell, cmd.exe, WSL, or another non-UCRT shell, synchronously bootstrap MSYS2 from the project directory:

```text
cmd.exe /d /s /c 'call "C:\msys64\msys2_shell.cmd" -defterm -here -no-start -ucrt64 -c "make test"'
```

- Replace `make test` with one required Bash command. Keep `-here` only when the host process starts in the project directory; otherwise use `-where` with the project directory.
- Treat `cmd.exe` only as the MSYS2 bootstrap. Execute all project commands inside the resulting UCRT64 Bash process.
- Do not invoke a bare `bash`, Git Bash, or WSL for a Windows-native command. Do not emulate UCRT64 by setting environment variables.

## Verify Before Work

- For UCRT64, confirm all of the following before native build or test work:
  - `MSYSTEM` is exactly `UCRT64`.
  - `uname -o` reports `Msys`.
  - `command -v make g++ scons` resolves the required MSYS2 tools.
- Stop and report an environment mismatch rather than substituting a different shell or faking verification results.
- Keep the selected shell for the entire command sequence, including configuration, compilation, and tests.
