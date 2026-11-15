#!/usr/bin/env bash
# Source only from the selected native Linux shell.
set -euo pipefail
ocbPlatform="${TARGET_PLATFORM:-linux}"
[[ "$ocbPlatform" == linux && "$(uname -o)" == GNU/Linux ]] || { echo 'Linux targets require native Linux Bash. Run Windows make from native PowerShell with MSVC.' >&2; exit 1; }
for ocbTool in make node npm cargo rustc; do command -v "$ocbTool" >/dev/null || { echo "$ocbTool is required." >&2; exit 1; }; done
[[ "$(rustc -vV)" == *'host: x86_64-unknown-linux-'* ]] || { echo 'Linux x86_64 Rust toolchain required.' >&2; exit 1; }
node -e 'if(process.platform!=="linux" || process.arch!=="x64") process.exit(1)'
