.DEFAULT_GOAL := help

# Project paths
projectRoot := $(CURDIR)
buildRoot := $(projectRoot)/build
godotCppRoot := $(projectRoot)/thirdparty/godotcpp
targetPlatform ?= windows
coreBenchmarkArgs ?=
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

.PHONY: help init build frontend backend native coreTest coreBenchmark nativeTest frontendTest test run clean \
	checkPlatform checkBackendTools checkGodotExecutable downloadGodot

help:
	@echo "make frontend targetPlatform=<linux|windows> Validate the Godot frontend target"
	@echo "make backend targetPlatform=<linux|windows>  Build the OcbSimulation GDExtension"
	@echo "make build targetPlatform=<linux|windows>    Build the frontend target and GDExtension"
	@echo "make coreTest targetPlatform=<linux|windows> Run native SimulationCore tests"
	@echo "make coreBenchmark targetPlatform=<linux|windows> Run the 1024x1024 Release mixed-gate SimulationCore throughput benchmark"
	@echo "make nativeTest targetPlatform=<linux|windows> Run headless GDExtension smoke tests"
	@echo "make frontendTest targetPlatform=<linux|windows> Run real-renderer frontend tests"
	@echo "make test targetPlatform=<linux|windows> Run core, native, and frontend tests"
	@echo "make native targetPlatform=<linux|windows>   Alias for the backend target"
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
frontend: checkGodotExecutable
	@true

backend: checkGodotExecutable checkBackendTools
	@mkdir -p "$(targetBuildRoot)"
	@cd "$(targetBuildRoot)" && "$(godotExecutable)" --headless --quiet --dump-extension-api
	@mv "$(targetBuildRoot)/extension_api.json" "$(targetBuildRoot)/extensionApi.json"
	@sed -e 's/enabledClasses/enabled_classes/' -e 's/enabledBuiltinClasses/enabled_builtin_classes/' "$(projectRoot)/BuildProfile.json" > "$(targetBuildRoot)/godotcppProfile.json"
	@cmake -S "$(projectRoot)/extension" -B "$(backendBuildRoot)" \
		-DGODOTCPPDIR="$(godotCppRoot)" \
		-DOCBOUTPUTDIR="$(targetBuildRoot)" \
		-DGODOTCPP_CUSTOM_API_FILE="$(targetBuildRoot)/extensionApi.json" \
		-DGODOTCPP_BUILD_PROFILE="$(targetBuildRoot)/godotcppProfile.json" $(if $(buildType),-DCMAKE_BUILD_TYPE="$(buildType)")
	@cmake --build "$(backendBuildRoot)"

build: frontend backend

native: backend

coreTest: backend
	@ctest --test-dir "$(backendBuildRoot)" --output-on-failure

coreBenchmark: buildType := Release
coreBenchmark: backend
	@cmake --build "$(backendBuildRoot)" --target ocbsimulation_core_benchmark
	@cd "$(backendBuildRoot)" && ./ocbsimulation_core_benchmark$(if $(filter windows,$(targetPlatform)),.exe) $(coreBenchmarkArgs)

nativeTest: backend
	@"$(godotExecutable)" --headless --path "$(projectRoot)" --script "$(projectRoot)/scripts/tests/NativeSimulationTest.gd"

frontendTest: build
	@"$(godotExecutable)" --rendering-method gl_compatibility --path "$(projectRoot)" --script "$(projectRoot)/scripts/tests/FrontendTest.gd"

test: coreTest nativeTest frontendTest

run:
	@"$(godotExecutable)" --path "$(projectRoot)"

clean:
	@rm -rf "$(buildRoot)"
