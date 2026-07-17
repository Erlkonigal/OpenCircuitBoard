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

using PropagationMode = SimulationCore::PropagationMode;

constexpr int32_t StageWidth = 4;
constexpr int32_t MixedLaneRowStride = 4;
constexpr int32_t UnaryBufferLaneRowStride = 2;
constexpr int32_t TargetTicksPerSecond = 100000;

enum class BenchmarkWorkload {
	Mixed,
	UnaryBuffer,
};

constexpr ToolKind MixedGateKinds[] = {
		ToolKind::And,
		ToolKind::Nand,
		ToolKind::Or,
		ToolKind::Nor,
		ToolKind::Xor,
		ToolKind::Xnor,
		ToolKind::Not,
		ToolKind::Buffer,
};

struct BenchmarkConfig {
	int32_t boardWidth = 1024;
	int32_t boardHeight = 1024;
	int32_t pipelineCount = 256;
	int32_t warmupTicks = 512;
	int32_t measurementTicks = 1024;
	int32_t sampleCount = 5;
	BenchmarkWorkload workload = BenchmarkWorkload::Mixed;
	PropagationMode propagationMode = PropagationMode::EventDriven;
	bool compareOrdering = false;
	bool comparePropagation = false;
};

struct CoreBenchmarkSample {
	double advanceSeconds = 0.0;
	double drainSeconds = 0.0;
	uint64_t stateChecksum = 0;
};

struct CoreBenchmarkObservation {
	CoreBenchmarkSample sample;
	std::vector<int32_t> stateChanges;
	std::vector<int32_t> states;
};

struct CoreBenchmarkResult {
	double ticksPerSecond = 0.0;
	double minimumTicksPerSecond = 0.0;
	double maximumTicksPerSecond = 0.0;
	double advanceTicksPerSecond = 0.0;
	double medianDrainMilliseconds = 0.0;
	uint64_t stateChecksum = 0;
};

enum class ParseResult {
	Ok,
	Help,
	Error,
};

void printUsage() {
	std::cout << "Usage: ocbsimulation_core_benchmark [--quick] [--compare-ordering|--compare-propagation]"
			  << " [--workload mixed|unary-buffer]"
			  << " [--propagation event|reference]"
			  << " [--width value] [--height value] [--pipelines value]"
			  << " [--warmup value] [--ticks value] [--samples value]\n";
}

const char *workloadName(BenchmarkWorkload workload) {
	switch (workload) {
		case BenchmarkWorkload::Mixed:
			return "mixed";
		case BenchmarkWorkload::UnaryBuffer:
			return "unary-buffer";
	}
	return "unknown";
}

bool parseWorkload(const std::string &text, BenchmarkWorkload &workload) {
	if (text == "mixed") {
		workload = BenchmarkWorkload::Mixed;
		return true;
	}
	if (text == "unary-buffer") {
		workload = BenchmarkWorkload::UnaryBuffer;
		return true;
	}
	return false;
}

const char *propagationModeName(PropagationMode propagationMode) {
	switch (propagationMode) {
		case PropagationMode::EventDriven:
			return "event";
		case PropagationMode::EventDrivenReference:
			return "reference";
	}
	return "unknown";
}

bool parsePropagationMode(const std::string &text, PropagationMode &propagationMode) {
	if (text == "event") {
		propagationMode = PropagationMode::EventDriven;
		return true;
	}
	if (text == "reference") {
		propagationMode = PropagationMode::EventDrivenReference;
		return true;
	}
	return false;
}

int32_t laneRowStride(BenchmarkWorkload workload) {
	return workload == BenchmarkWorkload::Mixed ? MixedLaneRowStride : UnaryBufferLaneRowStride;
}

int32_t lastActiveRowOffset(BenchmarkWorkload workload) {
	return workload == BenchmarkWorkload::Mixed ? 2 : 0;
}

int32_t pipelineStageCount(const BenchmarkConfig &config);

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
			config.pipelineCount = 64;
			config.warmupTicks = 256;
			config.measurementTicks = 4096;
			continue;
		}
		if (argument == "--compare-ordering") {
			config.compareOrdering = true;
			continue;
		}
		if (argument == "--compare-propagation") {
			config.comparePropagation = true;
			continue;
		}
		if (argument == "--workload") {
			if (++index >= argc || !parseWorkload(argv[index], config.workload)) {
				std::cerr << "Expected mixed or unary-buffer after --workload\n";
				return ParseResult::Error;
			}
			continue;
		}
		if (argument == "--propagation") {
			if (++index >= argc || !parsePropagationMode(argv[index], config.propagationMode)) {
				std::cerr << "Expected event or reference after --propagation\n";
				return ParseResult::Error;
			}
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
	if (config.compareOrdering && config.comparePropagation) {
		error = "compare-ordering and compare-propagation are mutually exclusive";
		return false;
	}
	if (config.comparePropagation && config.propagationMode != PropagationMode::EventDriven) {
		error = "compare-propagation always compares reference against event";
		return false;
	}
	if (config.boardWidth < 8 || config.boardHeight <= 0 || config.pipelineCount <= 0 ||
			config.warmupTicks < 0 || config.measurementTicks <= 0 || config.sampleCount <= 0) {
		error = "benchmark dimensions and tick counts must be positive";
		return false;
	}
	if (static_cast<int64_t>(config.boardWidth) * static_cast<int64_t>(config.boardHeight) > std::numeric_limits<int32_t>::max()) {
		error = "benchmark board is too large";
		return false;
	}
	if (pipelineStageCount(config) <= 0) {
		error = "benchmark board has no complete pipeline stage";
		return false;
	}
	const int64_t lastPipelineRow = static_cast<int64_t>(config.pipelineCount - 1) * laneRowStride(config.workload) +
			lastActiveRowOffset(config.workload);
	if (lastPipelineRow >= config.boardHeight) {
		error = "benchmark pipelines do not fit in the board height";
		return false;
	}
	return true;
}

int32_t pipelineStageCount(const BenchmarkConfig &config) {
	return config.workload == BenchmarkWorkload::Mixed ? (config.boardWidth - StageWidth) / StageWidth :
			(config.boardWidth - 1) / StageWidth;
}

int64_t activeCellCount(const CompileInput &input) {
	return std::count_if(input.kinds.begin(), input.kinds.end(), [](int32_t kind) {
		return static_cast<ToolKind>(kind) != ToolKind::Empty;
	});
}

void setKind(CompileInput &input, int32_t x, int32_t y, ToolKind kind) {
	input.kinds[y * input.width + x] = static_cast<int32_t>(kind);
}

void setClockHoldTicks(CompileInput &input, int32_t x, int32_t y, int32_t holdTicks) {
	input.clockHoldTicks[y * input.width + x] = holdTicks;
}

bool isMultiInputMixedGate(ToolKind kind) {
	return kind != ToolKind::Not && kind != ToolKind::Buffer;
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
	if (config.workload == BenchmarkWorkload::UnaryBuffer) {
		for (int32_t pipeline = 0; pipeline < config.pipelineCount; ++pipeline) {
			const int32_t y = pipeline * UnaryBufferLaneRowStride;
			setKind(input, 0, y, ToolKind::Clock);
			for (int32_t stage = 0; stage < stageCount; ++stage) {
				const int32_t x = 1 + stage * StageWidth;
				setKind(input, x, y, ToolKind::Read);
				setKind(input, x + 1, y, ToolKind::Trace);
				setKind(input, x + 2, y, ToolKind::Write);
				setKind(input, x + 3, y, ToolKind::Buffer);
			}
		}
		return input;
	}

	for (int32_t pipeline = 0; pipeline < config.pipelineCount; ++pipeline) {
		const int32_t y = pipeline * MixedLaneRowStride;
		const int32_t bottomY = y + 2;
		setKind(input, 0, y, ToolKind::Clock);
		setClockHoldTicks(input, 0, y, 2 + pipeline % 3);
		setKind(input, 1, y, ToolKind::Read);
		for (int32_t x = 2; x <= config.boardWidth - 3; ++x) {
			setKind(input, x, y, ToolKind::Trace);
		}
		setKind(input, config.boardWidth - 2, y, ToolKind::Read);
		setKind(input, config.boardWidth - 1, y, ToolKind::Clock);
		setClockHoldTicks(input, config.boardWidth - 1, y, 3 + (pipeline / 3) % 4);

		setKind(input, 0, bottomY, ToolKind::Clock);
		setClockHoldTicks(input, 0, bottomY, 1 + pipeline % 2);
		for (int32_t stage = 0; stage < stageCount; ++stage) {
			const int32_t gateX = StageWidth + stage * StageWidth;
			const ToolKind gateKind = MixedGateKinds[stage % (sizeof(MixedGateKinds) / sizeof(MixedGateKinds[0]))];
			if (stage == 0) {
				setKind(input, 1, bottomY, ToolKind::Read);
				setKind(input, 2, bottomY, ToolKind::Trace);
				setKind(input, 3, bottomY, ToolKind::Write);
			} else {
				setKind(input, gateX - 3, bottomY, ToolKind::Read);
				setKind(input, gateX - 2, bottomY, ToolKind::Trace);
				setKind(input, gateX - 1, bottomY, ToolKind::Write);
			}
			setKind(input, gateX, bottomY, gateKind);
			if (isMultiInputMixedGate(gateKind)) {
				setKind(input, gateX, y + 1, ToolKind::Write);
			}
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

bool compileBenchmarkCore(SimulationCore &core, const CompileInput &input, const char *label, double &compileSeconds) {
	const auto start = std::chrono::steady_clock::now();
	CompileError error;
	const bool compiled = core.compile(input, error);
	compileSeconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - start).count();
	if (compiled) {
		return true;
	}
	std::cerr << "coreBenchmark " << label << " compile failed at (" << error.errorX << ", " << error.errorY << "): " << error.errorReason << '\n';
	return false;
}

CoreBenchmarkObservation benchmarkSample(SimulationCore &core, const BenchmarkConfig &config) {
	static_cast<void>(core.reset());
	core.advanceTicksSilent(config.warmupTicks);
	static_cast<void>(core.drainStateChanges());

	const auto advanceStart = std::chrono::steady_clock::now();
	core.advanceTicksSilent(config.measurementTicks);
	const auto advanceFinish = std::chrono::steady_clock::now();
	CoreBenchmarkObservation result;
	result.stateChanges = core.drainStateChanges();
	const auto finish = std::chrono::steady_clock::now();

	result.sample.advanceSeconds = std::chrono::duration<double>(advanceFinish - advanceStart).count();
	result.sample.drainSeconds = std::chrono::duration<double>(finish - advanceFinish).count();
	result.states = core.getStates();
	result.sample.stateChecksum = calculateStateChecksum(result.states);
	return result;
}

bool observationsMatch(const CoreBenchmarkObservation &baseline, const CoreBenchmarkObservation &candidate, const char *label) {
	if (baseline.stateChanges != candidate.stateChanges) {
		std::cerr << "coreBenchmark " << label << " runtime changed the state delta result\n";
		return false;
	}
	if (baseline.states != candidate.states) {
		std::cerr << "coreBenchmark " << label << " runtime changed the visible state result\n";
		return false;
	}
	return true;
}

double median(std::vector<double> values) {
	std::sort(values.begin(), values.end());
	return values[values.size() / 2U];
}

bool summarizeSamples(const std::vector<CoreBenchmarkSample> &samples, int32_t measurementTicks, CoreBenchmarkResult &result) {
	if (samples.empty()) {
		return false;
	}
	std::vector<double> totalTicksPerSecond;
	std::vector<double> advanceTicksPerSecond;
	std::vector<double> drainMilliseconds;
	totalTicksPerSecond.reserve(samples.size());
	advanceTicksPerSecond.reserve(samples.size());
	drainMilliseconds.reserve(samples.size());
	const uint64_t checksum = samples.front().stateChecksum;
	for (const CoreBenchmarkSample &sample : samples) {
		if (sample.stateChecksum != checksum || sample.advanceSeconds <= 0.0) {
			return false;
		}
		const double totalSeconds = sample.advanceSeconds + sample.drainSeconds;
		if (totalSeconds <= 0.0) {
			return false;
		}
		totalTicksPerSecond.push_back(static_cast<double>(measurementTicks) / totalSeconds);
		advanceTicksPerSecond.push_back(static_cast<double>(measurementTicks) / sample.advanceSeconds);
		drainMilliseconds.push_back(sample.drainSeconds * 1000.0);
	}
	std::sort(totalTicksPerSecond.begin(), totalTicksPerSecond.end());
	result.ticksPerSecond = totalTicksPerSecond[totalTicksPerSecond.size() / 2U];
	result.minimumTicksPerSecond = totalTicksPerSecond.front();
	result.maximumTicksPerSecond = totalTicksPerSecond.back();
	result.advanceTicksPerSecond = median(std::move(advanceTicksPerSecond));
	result.medianDrainMilliseconds = median(std::move(drainMilliseconds));
	result.stateChecksum = checksum;
	return true;
}

double percentageImprovement(double before, double after) {
	if (before == 0.0) {
		return 0.0;
	}
	return (after - before) * 100.0 / before;
}

void printResult(const char *label, const CoreBenchmarkResult &result, double compileSeconds) {
	std::cout << "SimulationCore TPS (" << label << "): median=" << result.ticksPerSecond
			  << ", min=" << result.minimumTicksPerSecond << ", max=" << result.maximumTicksPerSecond
			  << ", advanceMedian=" << result.advanceTicksPerSecond
			  << ", drainMedianMs=" << result.medianDrainMilliseconds
			  << ", compileSeconds=" << compileSeconds
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
	const bool hasComparison = config.compareOrdering || config.comparePropagation;
	const PropagationMode baselinePropagationMode =
			config.comparePropagation ? PropagationMode::EventDrivenReference : config.propagationMode;
	const PropagationMode comparisonPropagationMode =
			config.comparePropagation ? PropagationMode::EventDriven : config.propagationMode;
	const char *baselineLabel = config.comparePropagation ? "reference" : "baseline";
	const char *comparisonLabel = config.comparePropagation ? "event" : "candidate";
	const char *comparisonName = config.comparePropagation ? "propagation" : "ordering";
	SimulationCore baselineCore(false, baselinePropagationMode);
	double baselineCompileSeconds = 0.0;
	if (!compileBenchmarkCore(baselineCore, input, baselineLabel, baselineCompileSeconds)) {
		return 1;
	}

	SimulationCore comparisonCore(config.compareOrdering, comparisonPropagationMode);
	double comparisonCompileSeconds = 0.0;
	if (hasComparison && !compileBenchmarkCore(comparisonCore, input, comparisonLabel, comparisonCompileSeconds)) {
		return 1;
	}

	std::vector<CoreBenchmarkSample> baselineSamples(config.sampleCount);
	std::vector<CoreBenchmarkSample> comparisonSamples;
	if (hasComparison) {
		comparisonSamples.resize(config.sampleCount);
	}
	for (int32_t sample = 0; sample < config.sampleCount; ++sample) {
		CoreBenchmarkObservation baselineObservation;
		CoreBenchmarkObservation comparisonObservation;
		const bool comparisonFirst = hasComparison && (sample % 2 != 0);
		if (comparisonFirst) {
			comparisonObservation = benchmarkSample(comparisonCore, config);
		}
		baselineObservation = benchmarkSample(baselineCore, config);
		if (hasComparison && !comparisonFirst) {
			comparisonObservation = benchmarkSample(comparisonCore, config);
		}
		baselineSamples[sample] = baselineObservation.sample;
		if (hasComparison) {
			comparisonSamples[sample] = comparisonObservation.sample;
			if (!observationsMatch(baselineObservation, comparisonObservation, comparisonName)) {
				return 1;
			}
		}
	}

	CoreBenchmarkResult baselineResult;
	if (!summarizeSamples(baselineSamples, config.measurementTicks, baselineResult)) {
		std::cerr << "coreBenchmark baseline produced inconsistent samples\n";
		return 1;
	}
	CoreBenchmarkResult comparisonResult;
	if (hasComparison && !summarizeSamples(comparisonSamples, config.measurementTicks, comparisonResult)) {
		std::cerr << "coreBenchmark " << comparisonLabel << " produced inconsistent samples\n";
		return 1;
	}

	std::cout << std::fixed << std::setprecision(2);
	std::cout << "Core benchmark: workload=" << workloadName(config.workload) << ", " << config.boardWidth << 'x' << config.boardHeight
			  << ", lanes=" << config.pipelineCount << ", activeCells=" << activeCellCount(input)
			  << ", propagation=" << (config.comparePropagation ? "reference-vs-event" : propagationModeName(config.propagationMode))
			  << ", warmup=" << config.warmupTicks << ", measured=" << config.measurementTicks
			  << ", pairedSamples=" << config.sampleCount << "\n";
	if (config.workload == BenchmarkWorkload::Mixed) {
		std::cout << "Core benchmark mixed gate cycle: And,Nand,Or,Nor,Xor,Xnor,Not,Buffer\n";
	}
	printResult(baselineLabel, baselineResult, baselineCompileSeconds);
	std::cout << "SimulationCore execution graph locality (baseline): " << baselineCore.getGraphLocalityScore() << '\n';
	std::cout << "SimulationCore single-input fast path (" << baselineLabel << "): "
			  << (baselineCore.isSingleInputComponentFastPathEnabled() ? "enabled" : "disabled") << '\n';

	if (!hasComparison) {
		return 0;
	}
	if (baselineResult.stateChecksum != comparisonResult.stateChecksum) {
		std::cerr << "coreBenchmark " << comparisonLabel << " runtime changed the visible state result\n";
		return 1;
	}
	printResult(comparisonLabel, comparisonResult, comparisonCompileSeconds);
	std::cout << "SimulationCore single-input fast path (" << comparisonLabel << "): "
			  << (comparisonCore.isSingleInputComponentFastPathEnabled() ? "enabled" : "disabled") << '\n';
	if (config.compareOrdering) {
		const bool orderingApplied = comparisonCore.isGraphLocalityOrderingApplied();
		std::cout << "SimulationCore graph locality ordering (candidate): "
				  << (orderingApplied ? "applied" : "rejected") << '\n';
		if (!orderingApplied) {
			std::cout << "SimulationCore paired TPS ordering improvement: not_measured (candidate_rejected)\n";
			return 0;
		}
	}
	std::vector<double> pairedTotalSpeedups;
	std::vector<double> pairedAdvanceSpeedups;
	std::vector<double> pairedDrainSpeedups;
	pairedTotalSpeedups.reserve(config.sampleCount);
	pairedAdvanceSpeedups.reserve(config.sampleCount);
	pairedDrainSpeedups.reserve(config.sampleCount);
	for (int32_t sample = 0; sample < config.sampleCount; ++sample) {
		const double baselineSeconds = baselineSamples[sample].advanceSeconds + baselineSamples[sample].drainSeconds;
		const double comparisonSeconds = comparisonSamples[sample].advanceSeconds + comparisonSamples[sample].drainSeconds;
		pairedTotalSpeedups.push_back((baselineSeconds / comparisonSeconds - 1.0) * 100.0);
		pairedAdvanceSpeedups.push_back(
				(baselineSamples[sample].advanceSeconds / comparisonSamples[sample].advanceSeconds - 1.0) * 100.0);
		if (baselineSamples[sample].drainSeconds > 0.0 && comparisonSamples[sample].drainSeconds > 0.0) {
			pairedDrainSpeedups.push_back(
					(baselineSamples[sample].drainSeconds / comparisonSamples[sample].drainSeconds - 1.0) * 100.0);
		}
	}
	std::cout << "SimulationCore paired " << comparisonName << " total speedup: median=" << median(pairedTotalSpeedups)
			  << "%\n";
	std::cout << "SimulationCore paired " << comparisonName << " advance speedup: median=" << median(pairedAdvanceSpeedups)
			  << "%\n";
	if (pairedDrainSpeedups.empty()) {
		std::cout << "SimulationCore paired " << comparisonName << " drain speedup: not_measured\n";
	} else {
		std::cout << "SimulationCore paired " << comparisonName << " drain speedup: median=" << median(pairedDrainSpeedups)
				  << "%\n";
	}
	std::cout << "SimulationCore median TPS " << comparisonName << " improvement: "
			  << percentageImprovement(baselineResult.ticksPerSecond, comparisonResult.ticksPerSecond) << "%\n";
	if (config.compareOrdering) {
		std::cout << "SimulationCore execution graph locality (reordered): " << comparisonCore.getGraphLocalityScore() << '\n';
	}
	return 0;
}
