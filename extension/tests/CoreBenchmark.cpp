#include "SimulationCore.hpp"

#include <algorithm>
#include <cerrno>
#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <iomanip>
#include <iostream>
#include <limits>
#include <string>
#include <vector>

namespace {

using ocb::CompileError;
using ocb::CompileInput;
using ocb::SimulationCore;
using ocb::ToolKind;

constexpr int32_t PipelineRowStride = 2;
constexpr int32_t CellsPerPipelineStage = 4;
constexpr int32_t TargetTicksPerSecond = 100000;

struct BenchmarkConfig {
	int32_t boardWidth = 1024;
	int32_t boardHeight = 1024;
	int32_t pipelineCount = 512;
	int32_t warmupTicks = 128;
	int32_t measurementTicks = 1024;
	int32_t sampleCount = 3;
	bool compareOrdering = false;
};

struct CoreBenchmarkResult {
	double ticksPerSecond = 0.0;
	double minimumTicksPerSecond = 0.0;
	double maximumTicksPerSecond = 0.0;
	uint64_t stateChecksum = 0;
};

enum class ParseResult {
	Ok,
	Help,
	Error,
};

void printUsage() {
	std::cout << "Usage: ocbsimulation_core_benchmark [--quick] [--compare-ordering]"
			  << " [--width value] [--height value] [--pipelines value]"
			  << " [--warmup value] [--ticks value] [--samples value]\n";
}

bool parseInt32(const char *text, int32_t &value) {
	char *end = nullptr;
	errno = 0;
	const long parsed = std::strtol(text, &end, 10);
	if (errno == ERANGE || end == text || *end != '\0' || parsed < std::numeric_limits<int32_t>::min() ||
			parsed > std::numeric_limits<int32_t>::max()) {
		return false;
	}
	value = static_cast<int32_t>(parsed);
	return true;
}

ParseResult parseConfig(int argc, char **argv, BenchmarkConfig &config) {
	for (int32_t index = 1; index < argc; ++index) {
		const std::string argument = argv[index];
		if (argument == "--help") {
			return ParseResult::Help;
		}
		if (argument == "--quick") {
			config.boardWidth = 256;
			config.boardHeight = 256;
			config.pipelineCount = 128;
			config.warmupTicks = 256;
			config.measurementTicks = 4096;
			continue;
		}
		if (argument == "--compare-ordering") {
			config.compareOrdering = true;
			continue;
		}

		int32_t *target = nullptr;
		if (argument == "--width") {
			target = &config.boardWidth;
		} else if (argument == "--height") {
			target = &config.boardHeight;
		} else if (argument == "--pipelines") {
			target = &config.pipelineCount;
		} else if (argument == "--warmup") {
			target = &config.warmupTicks;
		} else if (argument == "--ticks") {
			target = &config.measurementTicks;
		} else if (argument == "--samples") {
			target = &config.sampleCount;
		} else {
			std::cerr << "Unknown benchmark argument: " << argument << '\n';
			return ParseResult::Error;
		}
		if (++index >= argc || !parseInt32(argv[index], *target)) {
			std::cerr << "Expected an int32 value after " << argument << '\n';
			return ParseResult::Error;
		}
	}
	return ParseResult::Ok;
}

bool validateConfig(const BenchmarkConfig &config, std::string &error) {
	if (config.boardWidth <= CellsPerPipelineStage || config.boardHeight <= 0 || config.pipelineCount <= 0 ||
			config.warmupTicks < 0 || config.measurementTicks <= 0 || config.sampleCount <= 0) {
		error = "benchmark dimensions and tick counts must be positive";
		return false;
	}
	if (static_cast<int64_t>(config.boardWidth) * static_cast<int64_t>(config.boardHeight) > std::numeric_limits<int32_t>::max()) {
		error = "benchmark board is too large";
		return false;
	}
	if ((config.boardWidth - 1) / CellsPerPipelineStage <= 0) {
		error = "benchmark board has no complete pipeline stage";
		return false;
	}
	const int64_t lastPipelineRow = static_cast<int64_t>(config.pipelineCount - 1) * PipelineRowStride;
	if (lastPipelineRow >= config.boardHeight) {
		error = "benchmark pipelines do not fit in the board height";
		return false;
	}
	return true;
}

int32_t pipelineStageCount(const BenchmarkConfig &config) {
	return (config.boardWidth - 1) / CellsPerPipelineStage;
}

int64_t activeCellCount(const BenchmarkConfig &config) {
	return static_cast<int64_t>(config.pipelineCount) *
			(1 + static_cast<int64_t>(pipelineStageCount(config)) * CellsPerPipelineStage);
}

void setKind(CompileInput &input, int32_t x, int32_t y, ToolKind kind) {
	input.kinds[y * input.width + x] = static_cast<int32_t>(kind);
}

CompileInput makeBenchmarkInput(const BenchmarkConfig &config) {
	CompileInput input;
	input.width = config.boardWidth;
	input.height = config.boardHeight;
	const int32_t cellCount = config.boardWidth * config.boardHeight;
	input.kinds.assign(cellCount, static_cast<int32_t>(ToolKind::Empty));
	input.initialStates.assign(cellCount, 0);
	input.clockHoldTicks.assign(cellCount, 1);
	input.meshIds.assign(cellCount, 0);

	const int32_t stageCount = pipelineStageCount(config);
	for (int32_t pipeline = 0; pipeline < config.pipelineCount; ++pipeline) {
		const int32_t y = pipeline * PipelineRowStride;
		setKind(input, 0, y, ToolKind::Clock);
		for (int32_t stage = 0; stage < stageCount; ++stage) {
			const int32_t x = 1 + stage * CellsPerPipelineStage;
			setKind(input, x, y, ToolKind::Read);
			setKind(input, x + 1, y, ToolKind::Trace);
			setKind(input, x + 2, y, ToolKind::Write);
			setKind(input, x + 3, y, ToolKind::Buffer);
		}
	}

	return input;
}

uint64_t calculateStateChecksum(const std::vector<int32_t> &states) {
	uint64_t checksum = 1469598103934665603ULL;
	for (int32_t state : states) {
		checksum ^= static_cast<uint64_t>(state + 1);
		checksum *= 1099511628211ULL;
	}
	return checksum;
}

CoreBenchmarkResult benchmarkCore(SimulationCore &core, const BenchmarkConfig &config) {
	std::vector<double> samples;
	samples.reserve(config.sampleCount);
	uint64_t checksum = 0;
	for (int32_t sample = 0; sample < config.sampleCount; ++sample) {
		static_cast<void>(core.reset());
		core.advanceTicksSilent(config.warmupTicks);
		static_cast<void>(core.drainStateChanges());

		const auto start = std::chrono::steady_clock::now();
		core.advanceTicksSilent(config.measurementTicks);
		static_cast<void>(core.drainStateChanges());
		const auto finish = std::chrono::steady_clock::now();

		const std::chrono::duration<double> elapsed = finish - start;
		samples.push_back(static_cast<double>(config.measurementTicks) / elapsed.count());
		checksum = calculateStateChecksum(core.getStates());
	}
	std::sort(samples.begin(), samples.end());
	const size_t medianIndex = samples.size() / 2U;
	CoreBenchmarkResult result;
	result.ticksPerSecond = samples[medianIndex];
	result.minimumTicksPerSecond = samples.front();
	result.maximumTicksPerSecond = samples.back();
	result.stateChecksum = checksum;
	return result;
}

bool compileBenchmarkCore(SimulationCore &core, const CompileInput &input, const char *label) {
	CompileError error;
	if (core.compile(input, error)) {
		return true;
	}
	std::cerr << "coreBenchmark " << label << " compile failed at (" << error.errorX << ", " << error.errorY << "): " << error.errorReason << '\n';
	return false;
}

double percentageImprovement(double before, double after) {
	if (before == 0.0) {
		return 0.0;
	}
	return (after - before) * 100.0 / before;
}

void printResult(const char *label, const CoreBenchmarkResult &result) {
	std::cout << "SimulationCore TPS (" << label << "): median=" << result.ticksPerSecond
			  << ", min=" << result.minimumTicksPerSecond << ", max=" << result.maximumTicksPerSecond
			  << ", target100K=" << (result.ticksPerSecond >= TargetTicksPerSecond ? "met" : "not_met") << '\n';
	std::cout << "SimulationCore state checksum (" << label << "): " << result.stateChecksum << '\n';
}

} // namespace

int main(int argc, char **argv) {
	BenchmarkConfig config;
	const ParseResult parseResult = parseConfig(argc, argv, config);
	if (parseResult == ParseResult::Help) {
		printUsage();
		return 0;
	}
	if (parseResult != ParseResult::Ok) {
		printUsage();
		return 1;
	}
	std::string configError;
	if (!validateConfig(config, configError)) {
		std::cerr << "Invalid benchmark configuration: " << configError << '\n';
		return 1;
	}

	const CompileInput input = makeBenchmarkInput(config);
	SimulationCore baselineCore(false);
	if (!compileBenchmarkCore(baselineCore, input, "baseline")) {
		return 1;
	}
	const CoreBenchmarkResult baselineResult = benchmarkCore(baselineCore, config);

	std::cout << std::fixed << std::setprecision(2);
	std::cout << "Core benchmark: " << config.boardWidth << 'x' << config.boardHeight << ", " << config.pipelineCount
			  << " continuously toggling pipelines, activeCells=" << activeCellCount(config)
			  << ", warmup=" << config.warmupTicks << ", measured=" << config.measurementTicks
			  << ", samples=" << config.sampleCount << "\n";
	printResult("identity", baselineResult);
	std::cout << "SimulationCore execution graph locality (identity): " << baselineCore.getGraphLocalityScore() << '\n';

	if (!config.compareOrdering) {
		return 0;
	}

	SimulationCore reorderedCore(true);
	if (!compileBenchmarkCore(reorderedCore, input, "reordered")) {
		return 1;
	}
	const CoreBenchmarkResult reorderedResult = benchmarkCore(reorderedCore, config);
	if (baselineResult.stateChecksum != reorderedResult.stateChecksum) {
		std::cerr << "coreBenchmark reordered runtime changed the visible state result\n";
		return 1;
	}
	printResult("reordered", reorderedResult);
	std::cout << "SimulationCore TPS ordering improvement: "
			  << percentageImprovement(baselineResult.ticksPerSecond, reorderedResult.ticksPerSecond) << "%\n";
	std::cout << "SimulationCore execution graph locality (reordered): " << reorderedCore.getGraphLocalityScore() << '\n';
	return 0;
}
