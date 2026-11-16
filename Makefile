.DEFAULT_GOAL := help
ifeq ($(OS),Windows_NT)
TARGET_PLATFORM ?= windows
SHELL := powershell.exe
.SHELLFLAGS := -NoLogo -NoProfile -ExecutionPolicy Bypass -Command
OcbCommand = ./scripts/Command.ps1 -Action $@ -TargetPlatform "$(TARGET_PLATFORM)" -BuildType "$(BUILD_TYPE)"
else
TARGET_PLATFORM ?= linux
SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
OcbCommand = TARGET_PLATFORM="$(TARGET_PLATFORM)" BUILD_TYPE="$(BUILD_TYPE)" /bin/bash scripts/Command.sh "$@"
endif
BUILD_TYPE ?= Release
export CORE_BENCHMARK_ARGS
export BOARD_PATH
export BOARD_BENCHMARK_ARGS
export FRONTEND_TEST

.PHONY: help init examples format frontend-build test-tools build build-debug build-release run package core-test core-benchmark board-benchmark native-test native-ui-test frontend-test browser-test test check-platform clean
help:
	@echo 'make init TARGET_PLATFORM=<windows|linux>          Install locked npm/Cargo dependencies'
	@echo 'make examples                                    Regenerate and verify example projects'
	@echo 'make build [BUILD_TYPE=Debug|Release]              Build the desktop application'
	@echo 'make run [BUILD_TYPE=Debug|Release]                Launch the editor'
	@echo 'make package                                     Build NSIS or AppImage package'
	@echo 'make test                                        Rust, frontend, and browser tests'
	@echo 'make frontend-test                               Editor behavior and rendered captures'
	@echo 'make native-test                                 Real Tauri WebView tests'
	@echo 'make core-benchmark [CORE_BENCHMARK_ARGS=...]'
	@echo 'make board-benchmark BOARD_PATH=/absolute/path/project.ocb'

init examples format frontend-build test-tools build run package core-test core-benchmark board-benchmark native-test native-ui-test frontend-test browser-test test check-platform clean:
	@$(OcbCommand)

build-debug:
	@$(MAKE) build BUILD_TYPE=Debug TARGET_PLATFORM="$(TARGET_PLATFORM)"
build-release:
	@$(MAKE) build BUILD_TYPE=Release TARGET_PLATFORM="$(TARGET_PLATFORM)"
