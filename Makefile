.DEFAULT_GOAL := help

# Project paths
projectRoot := $(CURDIR)
buildRoot := $(projectRoot)/build
godotCppRoot := $(projectRoot)/thirdparty/godotcpp
targetPlatform ?= windows
targetBuildRoot := $(buildRoot)/$(targetPlatform)
backendBuildRoot := $(targetBuildRoot)/extension

# Godot toolchain
godotVersion := 4.7
godotToolsRoot := $(buildRoot)/tools/godot-$(godotVersion)
godotPlatformName := $(if $(filter windows,$(targetPlatform)),win64.exe,linux.x86_64)
godotArchiveName := Godot_v$(godotVersion)-stable_$(godotPlatformName).zip
godotArchiveUrl := https://github.com/godotengine/godot-builds/releases/download/$(godotVersion)-stable/$(godotArchiveName)
downloadedGodotExecutable := $(godotToolsRoot)/Godot_v$(godotVersion)-stable_$(godotPlatformName)

ifeq ($(origin godotExecutable), undefined)
godotExecutable := $(downloadedGodotExecutable)
godotDownloadPrerequisite := downloadGodot
endif

.PHONY: help init build frontend backend native clean \
	checkPlatform checkBackendTools checkGodotExecutable downloadGodot

help:
	@echo "make frontend targetPlatform=<linux|windows> Build the empty Godot frontend shell"
	@echo "make backend targetPlatform=<linux|windows>  Configure the empty CMake backend shell"
	@echo "make build targetPlatform=<linux|windows>    Build both shells"
	@echo "make native targetPlatform=<linux|windows>   Alias for the backend shell"
	@echo "make downloadGodot targetPlatform=<linux|windows> Download the pinned Godot executable"
	@echo "make clean                                    Remove generated build outputs"

# Environment checks
checkPlatform:
	@case "$(targetPlatform)" in \
		linux) test "$$(uname -o)" = "GNU/Linux" || (echo "Linux builds must run on native Linux."; exit 1);; \
		windows) test "$${MSYSTEM:-}" = "UCRT64" && test "$$(uname -o)" = "Msys" || (echo "Windows builds must run from the MSYS2 UCRT64 shell."; exit 1);; \
		*) echo "Unsupported targetPlatform: $(targetPlatform). Use linux or windows."; exit 1;; \
	esac

checkBackendTools:
	@for toolName in cmake g++ scons; do \
		if ! command -v "$$toolName" >/dev/null; then \
			echo "$$toolName is required for backend builds."; \
			exit 1; \
		fi; \
	done

checkGodotExecutable: $(godotDownloadPrerequisite)
	@test -f "$(godotExecutable)" || command -v "$(godotExecutable)" >/dev/null || (echo "Godot executable not found: $(godotExecutable)"; exit 1)

# Setup and tool acquisition
init:
	@git submodule update --init

downloadGodot: checkPlatform
	@set -e; \
	if [ -f "$(downloadedGodotExecutable)" ]; then exit 0; fi; \
	if ! command -v curl >/dev/null; then echo "curl is required to download Godot. Install curl, then rerun make downloadGodot."; exit 1; fi; \
	if ! command -v unzip >/dev/null; then echo "unzip is required to extract Godot. Install unzip, then rerun make downloadGodot."; exit 1; fi; \
	mkdir -p "$(godotToolsRoot)"; \
	curl --fail --location --retry 3 --output "$(godotToolsRoot)/$(godotArchiveName).part" "$(godotArchiveUrl)"; \
	unzip -oq "$(godotToolsRoot)/$(godotArchiveName).part" -d "$(godotToolsRoot)"; \
	mv "$(godotToolsRoot)/$(godotArchiveName).part" "$(godotToolsRoot)/$(godotArchiveName)"; \
	if [ ! -f "$(downloadedGodotExecutable)" ]; then echo "Downloaded Godot archive did not contain $(notdir $(downloadedGodotExecutable))."; exit 1; fi

# Build entry points
build: checkGodotExecutable checkBackendTools
	@cmake -S "$(projectRoot)/extension" -B "$(backendBuildRoot)" -DGODOTCPPDIR="$(godotCppRoot)" -DOCBOUTPUTDIR="$(targetBuildRoot)"
	@cmake --build "$(backendBuildRoot)"

run: build
	@"$(godotExecutable)" --path "$(projectRoot)"

clean:
	@rm -rf "$(buildRoot)"
