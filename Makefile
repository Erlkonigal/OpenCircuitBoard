.DEFAULT_GOAL := help

# Project paths
PROJECT_ROOT := $(CURDIR)
BUILD_ROOT := $(PROJECT_ROOT)/build
GODOT_CPP_ROOT := $(PROJECT_ROOT)/thirdparty/godotcpp
TARGET_PLATFORM ?= windows
BUILD_TYPE ?= Release
CORE_BENCHMARK_ARGS ?=

ifeq ($(BUILD_TYPE),Debug)
BUILD_VARIANT := debug
GODOTCPP_TARGET_FOR_BUILD := template_debug
else ifeq ($(BUILD_TYPE),Release)
BUILD_VARIANT := release
GODOTCPP_TARGET_FOR_BUILD := template_release
else
$(error Unsupported BUILD_TYPE: $(BUILD_TYPE). Use Debug or Release.)
endif

TARGET_BUILD_ROOT := $(BUILD_ROOT)/$(TARGET_PLATFORM)/$(BUILD_VARIANT)
BACKEND_BUILD_ROOT := $(TARGET_BUILD_ROOT)/extension
BACKEND_LIBRARY := $(TARGET_BUILD_ROOT)/ocbsimulation$(if $(filter windows,$(TARGET_PLATFORM)),.dll,.so)
EXTENSION_API := $(TARGET_BUILD_ROOT)/extension-api.json
GODOT_CPP_PROFILE := $(TARGET_BUILD_ROOT)/godot-cpp-profile.json
BACKEND_BUILD_CONFIGURATION := $(BACKEND_BUILD_ROOT)/build-configuration
BACKEND_CONFIGURE_STAMP := $(BACKEND_BUILD_ROOT)/.configured
GODOT_CPP_BUILD_STAMP := $(BACKEND_BUILD_ROOT)/.godot-cpp-built
RELEASE_BACKEND_BUILD_ROOT := $(BUILD_ROOT)/$(TARGET_PLATFORM)/release/extension

# Godot toolchain
GODOT_VERSION := 4.7
GODOT_TOOLS_ROOT := $(BUILD_ROOT)/tools/godot-$(GODOT_VERSION)
GODOT_PLATFORM_NAME := $(if $(filter windows,$(TARGET_PLATFORM)),win64.exe,linux.x86_64)
GODOT_ARCHIVE_NAME := Godot_v$(GODOT_VERSION)-stable_$(GODOT_PLATFORM_NAME).zip
GODOT_ARCHIVE_URL := https://github.com/godotengine/godot-builds/releases/download/$(GODOT_VERSION)-stable/$(GODOT_ARCHIVE_NAME)
DOWNLOADED_GODOT_EXECUTABLE := $(GODOT_TOOLS_ROOT)/Godot_v$(GODOT_VERSION)-stable_$(GODOT_PLATFORM_NAME)

ifeq ($(origin GODOT_EXECUTABLE), undefined)
GODOT_EXECUTABLE := $(DOWNLOADED_GODOT_EXECUTABLE)
GODOT_DOWNLOAD_PREREQUISITE := download-godot
GODOT_EXECUTABLE_INPUT := $(DOWNLOADED_GODOT_EXECUTABLE)
endif


.PHONY: help init build build-debug build-release core-test core-benchmark native-test frontend-test test run clean \
	check-platform check-backend-tools check-godot-executable download-godot force

EXTENSION_BUILD_INPUTS := $(shell find "$(PROJECT_ROOT)/extension" -type f -print)
EXTENSION_INPUT_DIRECTORIES := $(shell find "$(PROJECT_ROOT)/extension" -type d -print)
GODOT_CPP_SOURCE_INPUTS := $(shell find "$(GODOT_CPP_ROOT)/include" "$(GODOT_CPP_ROOT)/src" -type f -print)
GODOT_CPP_CONFIGURATION_INPUTS := \
	$(GODOT_CPP_ROOT)/CMakeLists.txt \
	$(GODOT_CPP_ROOT)/binding_generator.py \
	$(GODOT_CPP_ROOT)/build_profile.py \
	$(GODOT_CPP_ROOT)/make_interface_header.py \
	$(shell find "$(GODOT_CPP_ROOT)/cmake" "$(GODOT_CPP_ROOT)/gdextension" "$(GODOT_CPP_ROOT)/natvis" -type f -print)
GODOT_CPP_INPUT_DIRECTORIES := $(shell find "$(GODOT_CPP_ROOT)/cmake" "$(GODOT_CPP_ROOT)/gdextension" "$(GODOT_CPP_ROOT)/include" "$(GODOT_CPP_ROOT)/natvis" "$(GODOT_CPP_ROOT)/src" -type d -print)
BACKEND_CONFIGURE_INPUTS := \
	$(EXTENSION_API) \
	$(GODOT_CPP_PROFILE) \
	$(BACKEND_BUILD_CONFIGURATION) \
	$(PROJECT_ROOT)/Makefile \
	$(PROJECT_ROOT)/extension/CMakeLists.txt \
	$(PROJECT_ROOT)/extension/OcbSimulation.gdextension.in \
	$(EXTENSION_INPUT_DIRECTORIES) \
	$(GODOT_CPP_CONFIGURATION_INPUTS) \
	$(GODOT_CPP_INPUT_DIRECTORIES)

help:
	@echo "make build TARGET_PLATFORM=<linux|windows> [BUILD_TYPE=<Debug|Release>] Build one OcbSimulation variant"
	@echo "make build-debug TARGET_PLATFORM=<linux|windows> Build the editor/debug GDExtension variant"
	@echo "make build-release TARGET_PLATFORM=<linux|windows> Build the optimized export GDExtension variant"
	@echo "make core-test TARGET_PLATFORM=<linux|windows> Run native SimulationCore tests"
	@echo "make core-benchmark TARGET_PLATFORM=<linux|windows> Run the 1024x1024 Release mixed-gate SimulationCore throughput benchmark"
	@echo "make native-test TARGET_PLATFORM=<linux|windows> Run headless GDExtension smoke tests"
	@echo "make frontend-test TARGET_PLATFORM=<linux|windows> Run real-renderer frontend tests"
	@echo "make test TARGET_PLATFORM=<linux|windows> Run core, native, and frontend tests"
	@echo "make download-godot TARGET_PLATFORM=<linux|windows> Download the pinned Godot executable"
	@echo "make clean Remove generated build outputs"

# Environment checks
check-platform:
	@case "$(TARGET_PLATFORM)" in \
		linux) test "$$(uname -o)" = "GNU/Linux" || (echo "Linux builds must run on native Linux."; exit 1);; \
		windows) test "$${MSYSTEM:-}" = "UCRT64" && test "$$(uname -o)" = "Msys" || (echo "Windows builds must run from the MSYS2 UCRT64 shell."; exit 1);; \
		*) echo "Unsupported TARGET_PLATFORM: $(TARGET_PLATFORM). Use linux or windows."; exit 1;; \
	esac

check-backend-tools:
	@for tool in cmake g++ scons; do \
		if ! command -v "$$tool" >/dev/null; then \
			echo "$$tool is required for backend builds."; \
			exit 1; \
		fi; \
	done

check-godot-executable: $(GODOT_DOWNLOAD_PREREQUISITE)
	@test -f "$(GODOT_EXECUTABLE)" || command -v "$(GODOT_EXECUTABLE)" >/dev/null || (echo "Godot executable not found: $(GODOT_EXECUTABLE)"; exit 1)

# Setup and tool acquisition
init:
	@git submodule update --init

download-godot: $(DOWNLOADED_GODOT_EXECUTABLE)

$(DOWNLOADED_GODOT_EXECUTABLE): | check-platform
	@set -e; \
	if [ -f "$@" ]; then exit 0; fi; \
	if ! command -v curl >/dev/null; then echo "curl is required to download Godot. Install curl, then rerun make download-godot."; exit 1; fi; \
	if ! command -v unzip >/dev/null; then echo "unzip is required to extract Godot. Install unzip, then rerun make download-godot."; exit 1; fi; \
	mkdir -p "$(GODOT_TOOLS_ROOT)"; \
	curl --fail --location --retry 3 --output "$(GODOT_TOOLS_ROOT)/$(GODOT_ARCHIVE_NAME).part" "$(GODOT_ARCHIVE_URL)"; \
	unzip -oq "$(GODOT_TOOLS_ROOT)/$(GODOT_ARCHIVE_NAME).part" -d "$(GODOT_TOOLS_ROOT)"; \
	mv "$(GODOT_TOOLS_ROOT)/$(GODOT_ARCHIVE_NAME).part" "$(GODOT_TOOLS_ROOT)/$(GODOT_ARCHIVE_NAME)"; \
	if [ ! -f "$@" ]; then echo "Downloaded Godot archive did not contain $(notdir $(DOWNLOADED_GODOT_EXECUTABLE))."; exit 1; fi

# Build inputs and artifacts
$(TARGET_BUILD_ROOT):
	@mkdir -p "$@"

$(BACKEND_BUILD_ROOT): | $(TARGET_BUILD_ROOT)
	@mkdir -p "$@"

$(EXTENSION_API): $(GODOT_EXECUTABLE_INPUT) | $(TARGET_BUILD_ROOT) check-godot-executable
	@cd "$(TARGET_BUILD_ROOT)" && "$(GODOT_EXECUTABLE)" --headless --quiet --dump-extension-api
	@mv "$(TARGET_BUILD_ROOT)/extension_api.json" "$@"

$(GODOT_CPP_PROFILE): $(PROJECT_ROOT)/BuildProfile.json | $(TARGET_BUILD_ROOT)
	@sed -e 's/enabledClasses/enabled_classes/' -e 's/enabledBuiltinClasses/enabled_builtin_classes/' "$<" > "$@"

force:

$(BACKEND_BUILD_CONFIGURATION): force | $(BACKEND_BUILD_ROOT)
	@printf '%s\n' "$(BUILD_TYPE)|$(GODOTCPP_TARGET_FOR_BUILD)" > "$@.tmp"; \
	if ! cmp -s "$@.tmp" "$@"; then mv "$@.tmp" "$@"; else rm "$@.tmp"; fi

$(BACKEND_CONFIGURE_STAMP): $(BACKEND_CONFIGURE_INPUTS) | $(BACKEND_BUILD_ROOT) check-platform check-backend-tools
	@cmake -S "$(PROJECT_ROOT)/extension" -B "$(BACKEND_BUILD_ROOT)" \
		-DGODOTCPPDIR="$(GODOT_CPP_ROOT)" \
		-DOCBOUTPUTDIR="$(TARGET_BUILD_ROOT)" \
		-DGODOTCPP_CUSTOM_API_FILE="$(EXTENSION_API)" \
		-DGODOTCPP_BUILD_PROFILE="$(GODOT_CPP_PROFILE)" \
		-DCMAKE_BUILD_TYPE="$(BUILD_TYPE)" \
		-DGODOTCPP_TARGET="$(GODOTCPP_TARGET_FOR_BUILD)"
	@touch "$@"

$(GODOT_CPP_BUILD_STAMP): $(BACKEND_CONFIGURE_STAMP) $(GODOT_CPP_SOURCE_INPUTS) | check-backend-tools
	@cmake --build "$(BACKEND_BUILD_ROOT)" --target godot-cpp
	@touch "$@"

$(BACKEND_LIBRARY): $(BACKEND_CONFIGURE_STAMP) $(GODOT_CPP_BUILD_STAMP) $(EXTENSION_BUILD_INPUTS) | check-backend-tools
	@cmake --build "$(BACKEND_BUILD_ROOT)"
	@test -f "$@" || (echo "Backend library was not produced: $@"; exit 1)

build: $(BACKEND_LIBRARY)

build-debug:
	@$(MAKE) --no-print-directory build TARGET_PLATFORM="$(TARGET_PLATFORM)" BUILD_TYPE=Debug

build-release:
	@$(MAKE) --no-print-directory build TARGET_PLATFORM="$(TARGET_PLATFORM)" BUILD_TYPE=Release

core-test: build-release
	@ctest --test-dir "$(RELEASE_BACKEND_BUILD_ROOT)" --output-on-failure

core-benchmark: build-release
	@cmake --build "$(RELEASE_BACKEND_BUILD_ROOT)" --target ocbsimulation_core_benchmark
	@cd "$(RELEASE_BACKEND_BUILD_ROOT)" && ./ocbsimulation_core_benchmark$(if $(filter windows,$(TARGET_PLATFORM)),.exe) $(CORE_BENCHMARK_ARGS)

native-test: build-debug
	@"$(GODOT_EXECUTABLE)" --headless --path "$(PROJECT_ROOT)" --script "$(PROJECT_ROOT)/scripts/tests/NativeSimulationTest.gd"

frontend-test: build-debug
	@"$(GODOT_EXECUTABLE)" --rendering-method gl_compatibility --path "$(PROJECT_ROOT)" --script "$(PROJECT_ROOT)/scripts/tests/FrontendTest.gd"

test: core-test native-test frontend-test

run:
	@"$(GODOT_EXECUTABLE)" --path "$(PROJECT_ROOT)"

clean:
	@rm -rf "$(BUILD_ROOT)"
