#include "SimulationCore.hpp"

#ifndef OCB_HAS_GRAPH_LOCALITY_ORDERER
#define OCB_HAS_GRAPH_LOCALITY_ORDERER 0
#endif

#if OCB_HAS_GRAPH_LOCALITY_ORDERER
#include "GraphLocalityOrderer.hpp"
#endif

#include <chrono>
#include <cstdint>
#include <iomanip>
#include <iostream>
#include <numeric>
#include <string>
#include <type_traits>
#include <utility>
#include <vector>

namespace {

using ocb::CompileError;
using ocb::CompileInput;
using ocb::SimulationCore;
using ocb::ToolKind;

constexpr int32_t BoardWidth = 256;
constexpr int32_t BoardHeight = 256;
constexpr int32_t PipelineCount = 128;
constexpr int32_t PipelineRowStride = 2;
constexpr int32_t CellsPerPipelineStage = 4;
constexpr int32_t PipelineStages = (BoardWidth - 1) / CellsPerPipelineStage;
constexpr int32_t WarmupTicks = 256;
constexpr int32_t MeasurementTicks = 4096;

struct CoreBenchmarkResult {
	double ticksPerSecond = 0.0;
	uint64_t stateChecksum = 0;
};

template <typename Type, typename = void>
struct HasAdvanceTicksSilent : std::false_type {
};

template <typename Type>
struct HasAdvanceTicksSilent<Type, std::void_t<decltype(std::declval<Type &>().advanceTicksSilent(int32_t{}))>> : std::true_type {
};

template <typename Type, typename = void>
struct HasDrainStateChanges : std::false_type {
};

template <typename Type>
struct HasDrainStateChanges<Type, std::void_t<decltype(std::declval<Type &>().drainStateChanges())>> : std::true_type {
};

void setKind(CompileInput &input, int32_t x, int32_t y, ToolKind kind) {
	input.kinds[y * input.width + x] = static_cast<int32_t>(kind);
}

CompileInput makeBenchmarkInput() {
	CompileInput input;
	input.width = BoardWidth;
	input.height = BoardHeight;
	const int32_t cellCount = BoardWidth * BoardHeight;
	input.kinds.assign(cellCount, static_cast<int32_t>(ToolKind::Empty));
	input.initialStates.assign(cellCount, 0);
	input.clockHoldTicks.assign(cellCount, 1);
	input.meshIds.assign(cellCount, 0);

	for (int32_t pipeline = 0; pipeline < PipelineCount; ++pipeline) {
		const int32_t y = pipeline * PipelineRowStride;
		setKind(input, 0, y, ToolKind::Clock);
		for (int32_t stage = 0; stage < PipelineStages; ++stage) {
			const int32_t x = 1 + stage * CellsPerPipelineStage;
			setKind(input, x, y, ToolKind::Read);
			setKind(input, x + 1, y, ToolKind::Trace);
			setKind(input, x + 2, y, ToolKind::Write);
			setKind(input, x + 3, y, ToolKind::Buffer);
		}
	}

	return input;
}

template <typename Type>
void advanceSilently(Type &core, int32_t tickCount) {
	if constexpr (HasAdvanceTicksSilent<Type>::value) {
		core.advanceTicksSilent(tickCount);
	} else {
		static_cast<void>(core.advanceTicks(tickCount));
	}
}

template <typename Type>
void discardStateChanges(Type &core) {
	if constexpr (HasDrainStateChanges<Type>::value) {
		static_cast<void>(core.drainStateChanges());
	}
}

uint64_t calculateStateChecksum(const std::vector<int32_t> &states) {
	uint64_t checksum = 1469598103934665603ULL;
	for (int32_t state : states) {
		checksum ^= static_cast<uint64_t>(state + 1);
		checksum *= 1099511628211ULL;
	}
	return checksum;
}

CoreBenchmarkResult benchmarkCore(SimulationCore &core) {
	advanceSilently(core, WarmupTicks);
	discardStateChanges(core);

	const auto start = std::chrono::steady_clock::now();
	advanceSilently(core, MeasurementTicks);
	discardStateChanges(core);
	const auto finish = std::chrono::steady_clock::now();

	const std::chrono::duration<double> elapsed = finish - start;
	CoreBenchmarkResult result;
	result.ticksPerSecond = static_cast<double>(MeasurementTicks) / elapsed.count();
	result.stateChecksum = calculateStateChecksum(core.getStates());
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

#if OCB_HAS_GRAPH_LOCALITY_ORDERER

struct BenchmarkGraph {
	std::vector<int32_t> outgoingOffsets;
	std::vector<int32_t> outgoingTargets;
	std::vector<int32_t> incomingOffsets;
	std::vector<int32_t> incomingSources;
};

int32_t graphNodeId(int32_t pipeline, int32_t stage, int32_t lane) {
	const int32_t nodesPerPair = PipelineCount * PipelineStages * 2;
	const int32_t pairIndex = stage * PipelineCount + pipeline;
	if (lane < 2) {
		return PipelineCount + pairIndex * 2 + lane;
	}
	return PipelineCount + nodesPerPair + pairIndex * 2 + lane - 2;
}

void makeIncomingEdges(BenchmarkGraph &graph) {
	const int32_t nodeCount = static_cast<int32_t>(graph.outgoingOffsets.size()) - 1;
	std::vector<int32_t> incomingCounts(nodeCount, 0);
	for (int32_t target : graph.outgoingTargets) {
		++incomingCounts[target];
	}

	graph.incomingOffsets.assign(nodeCount + 1, 0);
	for (int32_t node = 0; node < nodeCount; ++node) {
		graph.incomingOffsets[node + 1] = graph.incomingOffsets[node] + incomingCounts[node];
	}

	graph.incomingSources.assign(graph.outgoingTargets.size(), 0);
	std::vector<int32_t> insertionOffsets = graph.incomingOffsets;
	for (int32_t source = 0; source < nodeCount; ++source) {
		for (int32_t edge = graph.outgoingOffsets[source]; edge < graph.outgoingOffsets[source + 1]; ++edge) {
			const int32_t target = graph.outgoingTargets[edge];
			graph.incomingSources[insertionOffsets[target]++] = source;
		}
	}
}

BenchmarkGraph makePipelineGraph() {
	const int32_t nodesPerPipeline = 1 + PipelineStages * CellsPerPipelineStage;
	const int32_t nodeCount = PipelineCount * nodesPerPipeline;
	std::vector<std::vector<int32_t>> outgoing(nodeCount);

	for (int32_t pipeline = 0; pipeline < PipelineCount; ++pipeline) {
		int32_t previous = pipeline;
		for (int32_t stage = 0; stage < PipelineStages; ++stage) {
			for (int32_t lane = 0; lane < CellsPerPipelineStage; ++lane) {
				const int32_t current = graphNodeId(pipeline, stage, lane);
				outgoing[previous].push_back(current);
				previous = current;
			}
		}
	}

	BenchmarkGraph graph;
	graph.outgoingOffsets.resize(nodeCount + 1, 0);
	for (int32_t node = 0; node < nodeCount; ++node) {
		graph.outgoingOffsets[node] = static_cast<int32_t>(graph.outgoingTargets.size());
		graph.outgoingTargets.insert(graph.outgoingTargets.end(), outgoing[node].begin(), outgoing[node].end());
	}
	graph.outgoingOffsets[nodeCount] = static_cast<int32_t>(graph.outgoingTargets.size());
	makeIncomingEdges(graph);
	return graph;
}

bool isValidOrder(const ocb::GraphLocalityOrder &order, int32_t nodeCount) {
	if (static_cast<int32_t>(order.newToOld.size()) != nodeCount || static_cast<int32_t>(order.oldToNew.size()) != nodeCount) {
		return false;
	}
	std::vector<uint8_t> seen(nodeCount, 0);
	for (int32_t newNode = 0; newNode < nodeCount; ++newNode) {
		const int32_t oldNode = order.newToOld[newNode];
		if (oldNode < 0 || oldNode >= nodeCount || seen[oldNode] != 0 || order.oldToNew[oldNode] != newNode) {
			return false;
		}
		seen[oldNode] = 1;
	}
	return true;
}

double percentageImprovement(int64_t before, int64_t after) {
	if (before == 0) {
		return 0.0;
	}
	return static_cast<double>(after - before) * 100.0 / static_cast<double>(before);
}

#endif

} // namespace

int main() {
	CompileInput input = makeBenchmarkInput();
	SimulationCore baselineCore(false);
	SimulationCore reorderedCore(true);
	if (!compileBenchmarkCore(baselineCore, input, "baseline")) {
		return 1;
	}
	if (!compileBenchmarkCore(reorderedCore, input, "reordered")) {
		return 1;
	}

	const CoreBenchmarkResult baselineResult = benchmarkCore(baselineCore);
	const CoreBenchmarkResult reorderedResult = benchmarkCore(reorderedCore);
	if (baselineResult.stateChecksum != reorderedResult.stateChecksum) {
		std::cerr << "coreBenchmark reordered runtime changed the visible state result\n";
		return 1;
	}
	std::cout << std::fixed << std::setprecision(2);
	std::cout << "Core benchmark: " << BoardWidth << 'x' << BoardHeight << ", " << PipelineCount
			  << " continuously toggling pipelines, warmup=" << WarmupTicks << ", measured=" << MeasurementTicks << " ticks\n";
	std::cout << "SimulationCore TPS: baseline=" << baselineResult.ticksPerSecond
			  << ", reordered=" << reorderedResult.ticksPerSecond
			  << ", improvement=" << percentageImprovement(baselineResult.ticksPerSecond, reorderedResult.ticksPerSecond) << "%\n";
	std::cout << "SimulationCore state checksum: baseline=" << baselineResult.stateChecksum
			  << ", reordered=" << reorderedResult.stateChecksum << '\n';
	const int64_t baselineLocalityScore = baselineCore.getGraphLocalityScore();
	const int64_t reorderedLocalityScore = reorderedCore.getGraphLocalityScore();
	std::cout << "SimulationCore execution graph locality: baseline=" << baselineLocalityScore
			  << ", reordered=" << reorderedLocalityScore;
	if (baselineLocalityScore == 0) {
		std::cout << ", improvement=not_applicable\n";
	} else {
		std::cout << ", improvement=" << percentageImprovement(baselineLocalityScore, reorderedLocalityScore) << "%\n";
	}

#if OCB_HAS_GRAPH_LOCALITY_ORDERER
	const BenchmarkGraph graph = makePipelineGraph();
	const int32_t nodeCount = static_cast<int32_t>(graph.outgoingOffsets.size()) - 1;
	std::vector<int32_t> identityOrder(nodeCount);
	std::iota(identityOrder.begin(), identityOrder.end(), 0);
	const int64_t identityScore = ocb::GraphLocalityOrderer::calculateLocalityScore(
			graph.outgoingOffsets, graph.outgoingTargets, identityOrder);
	const ocb::GraphLocalityOrder order = ocb::GraphLocalityOrderer::order(
			graph.outgoingOffsets, graph.outgoingTargets, graph.incomingOffsets, graph.incomingSources);
	if (!isValidOrder(order, nodeCount)) {
		std::cerr << "coreBenchmark received an invalid GraphLocalityOrder permutation\n";
		return 1;
	}
	const int64_t reorderedScore = ocb::GraphLocalityOrderer::calculateLocalityScore(
			graph.outgoingOffsets, graph.outgoingTargets, order.oldToNew);

	std::cout << "Reference pipeline graph locality: identity=" << identityScore << ", reordered=" << reorderedScore
			  << ", improvement=" << percentageImprovement(identityScore, reorderedScore) << "%\n";
#else
	std::cout << "Execution graph locality comparison unavailable: GraphLocalityOrderer was not compiled.\n";
#endif

	return 0;
}
