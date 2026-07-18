#pragma once

#include <algorithm>
#include <array>
#include <cassert>
#include <cstddef>
#include <cstdint>
#include <string>
#include <type_traits>
#include <vector>

#if defined(_MSC_VER)
#include <intrin.h>
#endif

namespace ocb {

enum class ToolKind : int32_t {
	Empty = 0,
	Trace = 1,
	TraceRed = 2,
	TraceGreen = 3,
	TraceBlue = 4,
	TraceCyan = 5,
	TraceMagenta = 6,
	Bus = 7,
	BusRed = 8,
	BusGreen = 9,
	BusYellow = 10,
	BusCyan = 11,
	BusMagenta = 12,
	Cross = 13,
	Mesh = 14,
	Read = 15,
	Write = 16,
	Buffer = 17,
	And = 18,
	Or = 19,
	Xor = 20,
	Not = 21,
	Nand = 22,
	Nor = 23,
	Xnor = 24,
	Latch = 25,
	Clock = 26,
	Led = 27,
};

struct CompileInput {
	std::vector<int32_t> kinds;
	std::vector<int32_t> initialStates;
	std::vector<int32_t> clockHoldTicks;
	std::vector<int32_t> meshIds;
	int32_t width = 0;
	int32_t height = 0;
};

struct CompileError {
	int32_t errorX = -1;
	int32_t errorY = -1;
	std::string errorReason;
};

class SimulationCore {
public:
	explicit SimulationCore(bool useGraphLocalityOrdering = false);

	bool compile(const CompileInput &input, CompileError &error);
	std::vector<int32_t> advanceTick();
	std::vector<int32_t> advanceTicks(int32_t tickCount);
	void advanceTicksSilent(int32_t tickCount);
	// These views write into caller-owned POD storage so presentation does not allocate in the runtime loop.
	size_t drainStateChangesTo(int32_t *changes, size_t capacity);
	bool copyVisibleStates(uint8_t *states, size_t capacity) const;
	int32_t getVisibleCellCount() const;
	bool beginDeferredVisualTracking();
	void endDeferredVisualTracking();
	std::vector<int32_t> drainStateChanges();
	std::vector<int32_t> getStates() const;
	bool toggleLatch(int32_t cellIndex, std::string &errorReason);
	bool toggleLatch(int32_t cellIndex, std::vector<int32_t> &changes, std::string &errorReason);
	void resetSilent();
	std::vector<int32_t> reset();
	std::vector<uint8_t> captureState() const;
	bool restoreState(const std::vector<uint8_t> &snapshot, std::string &errorReason);
	bool isCompiled() const;
	bool isGraphLocalityOrderingApplied() const;
	int64_t getGraphLocalityScore() const;

private:
	enum class EvaluationMode : uint8_t {
		State,
		High,
		Low,
		AllHigh,
		NotAllHigh,
		OddParity,
		EvenParity,
		LatchToggle,
	};
	static constexpr size_t EvaluationModeCount = static_cast<size_t>(EvaluationMode::LatchToggle) + 1U;
	static constexpr size_t SignalColorCount = 6U;
	static constexpr size_t CrossChannelCount = SignalColorCount * 2U;
	static constexpr size_t GateFrontierSparseClearDivisor = 4U;

	struct Component {
		ToolKind kind = ToolKind::Empty;
		std::vector<int32_t> cells;
		int32_t clockHoldTicks = 0;
		uint8_t latchInitialState = 0;
	};

	struct ConnectorEventQueue {
		void clear() {
			size_ = 0;
		}

		void prepare(size_t capacity) {
			if (storage_.size() < capacity) {
				storage_.resize(capacity);
			}
			size_ = 0;
		}

		size_t size() const {
			return size_;
		}

		int32_t operator[](size_t index) const {
			return storage_[index];
		}

		void push_back(int32_t event) {
			assert(size_ < storage_.size());
			storage_[size_++] = event;
		}

	private:
		// Retain constructed slots so repeated ticks overwrite the high-water range.
		std::vector<int32_t> storage_;
		size_t size_ = 0;
	};

	struct ComponentRuntimeState {
		int32_t inputHighCount;
		int32_t inputDelta;
		int32_t risingCount;
		int32_t nextPending;
		uint32_t inputStamp;
	};

	struct ConnectorRuntimeState {
		int32_t inputHighCount;
		int32_t delta;
		uint32_t stamp;
	};

	static_assert(std::is_standard_layout_v<ComponentRuntimeState> && std::is_trivially_copyable_v<ComponentRuntimeState>);
	static_assert(std::is_standard_layout_v<ConnectorRuntimeState> && std::is_trivially_copyable_v<ConnectorRuntimeState>);

	struct ReadBinding {
		std::vector<int32_t> cells;
		std::vector<int32_t> sourceComponents;
		int32_t signalNetwork = -1;
		std::vector<int32_t> outputNetworks;
		std::vector<int32_t> adjacentWriteBindings;
	};

	struct WriteBinding {
		std::vector<int32_t> cells;
		std::vector<int32_t> inputNetworks;
		int32_t signalNetwork = -1;
		std::vector<int32_t> targetComponents;
		std::vector<int32_t> adjacentReadBindings;
	};

	static constexpr uint8_t ForcedVisibleNodeInitialState = 2;

	static bool isKnownKind(int32_t kind);
	static bool isTrace(ToolKind kind);
	static bool isBus(ToolKind kind);
	static bool isConductor(ToolKind kind);
	static bool isDevice(ToolKind kind);
	static bool isReadSource(ToolKind kind);
	static bool isWriteTarget(ToolKind kind);
	static int32_t colorForKind(ToolKind kind);
	// Nonnegative events encode high states; bitwise complements encode low states.
	static int32_t encodeConnectorEvent(int32_t node, uint8_t state) {
		return state != 0 ? node : ~node;
	}
	static int32_t countTrailingZeros(uint64_t value) {
#if defined(_MSC_VER)
		unsigned long index = 0;
		_BitScanForward64(&index, value);
		return static_cast<int32_t>(index);
#else
		return static_cast<int32_t>(__builtin_ctzll(value));
#endif
	}
	uint8_t evaluateComponent(int32_t node) const;
	uint8_t evaluateComponent(int32_t node, int32_t highInputCount) const;
	uint8_t evaluateComponent(int32_t node, int32_t highInputCount, uint8_t evaluationPolicy) const;
	void buildExecutionGraph();
	void rebuildDerivedState(const std::vector<uint8_t> &componentStates);
	void propagateStateChange(int32_t sourceNode, uint8_t oldState, uint8_t newState);
	void drainConnectorQueue();
	void beginPropagationBatch(bool nextGateFrontierIsEmpty);
	void finishPropagationBatch(bool nextGateFrontierIsEmpty);
	void flushQueuedComponentInputDeltas();
	void flushUnqueuedComponentInputDeltas();
	void clearNextGateFrontier();
	void drainConnectorWorkWord(size_t workWordIndex);
	void initializeConnectorWorkWordHierarchy(size_t workWordCount);
	bool hasActiveConnectorWorkWords() const {
		return !connectorActiveWordLevelOffsets_.empty() &&
				connectorActiveWordHierarchy_[connectorActiveWordLevelOffsets_.back()] != 0;
	}
	void activateConnectorWorkWord(size_t workWordIndex) {
		size_t index = workWordIndex;
		for (size_t level = 0; level < connectorActiveWordLevelOffsets_.size(); ++level) {
			const size_t wordIndex = index / 64U;
			const uint64_t mask = uint64_t{1} << (index % 64U);
			uint64_t &word = connectorActiveWordHierarchy_[connectorActiveWordLevelOffsets_[level] + wordIndex];
			if ((word & mask) != 0) {
				return;
			}
			const bool wasEmpty = word == 0;
			word |= mask;
			if (!wasEmpty) {
				return;
			}
			index = wordIndex;
		}
	}
	void deactivateConnectorWorkWord(size_t workWordIndex) {
		size_t index = workWordIndex;
		for (size_t level = 0; level < connectorActiveWordLevelOffsets_.size(); ++level) {
			const size_t wordIndex = index / 64U;
			const uint64_t mask = uint64_t{1} << (index % 64U);
			uint64_t &word = connectorActiveWordHierarchy_[connectorActiveWordLevelOffsets_[level] + wordIndex];
			assert((word & mask) != 0);
			word &= ~mask;
			if (word != 0 || level + 1U == connectorActiveWordLevelOffsets_.size()) {
				return;
			}
			index = wordIndex;
		}
	}
	size_t firstActiveConnectorWorkWord() const {
		assert(hasActiveConnectorWorkWords());
		size_t wordIndex = 0;
		for (size_t level = connectorActiveWordLevelOffsets_.size(); level > 0; --level) {
			const uint64_t word = connectorActiveWordHierarchy_[connectorActiveWordLevelOffsets_[level - 1U] + wordIndex];
			assert(word != 0);
			wordIndex = wordIndex * 64U + static_cast<size_t>(countTrailingZeros(word));
		}
		assert(wordIndex < connectorWorkWords_.size());
		return wordIndex;
	}
	bool isComponentGateQueued(int32_t componentNode) const {
		const size_t gateIndex = static_cast<size_t>(componentNode);
		return (nextGateWords_[gateIndex / 64U] & (uint64_t{1} << (gateIndex % 64U))) != 0;
	}
	void accumulateComponentInputDelta(int32_t componentNode, int32_t stateDelta) {
		ComponentRuntimeState &pending = componentRuntimeStates_[static_cast<size_t>(componentNode)];
		if (pending.inputStamp != propagationStamp_) {
			pending.inputStamp = propagationStamp_;
			pending.inputDelta = stateDelta;
			const EvaluationMode mode = static_cast<EvaluationMode>(nodeEvaluationPolicies_[componentNode]);
			pending.risingCount =
					!suppressLatchInputEdges_ && mode == EvaluationMode::LatchToggle && stateDelta > 0 ? 1 : 0;
			const size_t modeIndex = static_cast<size_t>(mode);
			pending.nextPending = -1;
			if (pendingComponentTails_[modeIndex] >= 0) {
				componentRuntimeStates_[static_cast<size_t>(pendingComponentTails_[modeIndex])].nextPending = componentNode;
			} else {
				pendingComponentHeads_[modeIndex] = componentNode;
			}
			pendingComponentTails_[modeIndex] = componentNode;
			return;
		}
		pending.inputDelta += stateDelta;
		if (!suppressLatchInputEdges_ &&
				static_cast<EvaluationMode>(nodeEvaluationPolicies_[componentNode]) == EvaluationMode::LatchToggle && stateDelta > 0) {
			++pending.risingCount;
		}
	}
	void accumulateConnectorDelta(int32_t connectorRank, int32_t stateDelta) {
		ConnectorRuntimeState &pending = connectorRuntimeStates_[static_cast<size_t>(connectorRank)];
		if (pending.stamp == propagationStamp_) {
			pending.delta += stateDelta;
			return;
		}
		pending.stamp = propagationStamp_;
		pending.delta = stateDelta;
		const size_t workWordIndex = static_cast<size_t>(connectorRank) / 64U;
		uint64_t &workWord = connectorWorkWords_[workWordIndex];
		if (connectorWorkWordStamps_[workWordIndex] != propagationStamp_) {
			connectorWorkWordStamps_[workWordIndex] = propagationStamp_;
			workWord = 0;
		}
		const bool workWordWasEmpty = workWord == 0;
		workWord |= uint64_t{1} << (static_cast<size_t>(connectorRank) % 64U);
		if (workWordWasEmpty) {
			activateConnectorWorkWord(workWordIndex);
		}
	}
	inline void seedSourceDelta(int32_t sourceNode, int32_t stateDelta) {
		const int32_t componentEdgeEnd = outgoingComponentEnds_[sourceNode];
		if (componentEdgeEnd < 0) {
			accumulateComponentInputDelta(-componentEdgeEnd - 1, stateDelta);
			return;
		}
		for (int32_t edge = outgoingOffsets_[sourceNode]; edge < componentEdgeEnd; ++edge) {
			accumulateComponentInputDelta(outgoingTargets_[edge], stateDelta);
		}
		for (int32_t edge = componentEdgeEnd; edge < outgoingOffsets_[sourceNode + 1]; ++edge) {
			accumulateConnectorDelta(outgoingTargets_[edge], stateDelta);
		}
	}
	void enqueueComponentGate(int32_t componentNode, uint8_t nextState) {
		nextGateStates_[componentNode] = nextState;
		const size_t gateIndex = static_cast<size_t>(componentNode);
		const size_t wordIndex = gateIndex / 64U;
		const uint64_t gateMask = uint64_t{1} << (gateIndex % 64U);
		uint64_t &gateWord = nextGateWords_[wordIndex];
		if ((gateWord & gateMask) != 0) {
			return;
		}
		const bool firstGateInWord = gateWord == 0;
		gateWord |= gateMask;
		if (!firstGateInWord) {
			return;
		}
		const size_t summaryWordIndex = wordIndex / 64U;
		uint64_t &summaryWord = nextGateSummaryWords_[summaryWordIndex];
		if (summaryWord == 0) {
			assert(nextGateActiveSummaryWordIndices_.size() < nextGateActiveSummaryWordIndices_.capacity());
			nextGateActiveSummaryWordIndices_.push_back(static_cast<uint32_t>(summaryWordIndex));
		}
		summaryWord |= uint64_t{1} << (wordIndex % 64U);
	}
	void enqueueNewComponentGate(int32_t componentNode, uint8_t nextState) {
		// Normal propagation starts with an empty frontier and visits each pending component once.
		nextGateStates_[componentNode] = nextState;
		const size_t gateIndex = static_cast<size_t>(componentNode);
		const size_t wordIndex = gateIndex / 64U;
		const uint64_t gateMask = uint64_t{1} << (gateIndex % 64U);
		uint64_t &gateWord = nextGateWords_[wordIndex];
		assert((gateWord & gateMask) == 0);
		const bool firstGateInWord = gateWord == 0;
		gateWord |= gateMask;
		if (!firstGateInWord) {
			return;
		}
		const size_t summaryWordIndex = wordIndex / 64U;
		uint64_t &summaryWord = nextGateSummaryWords_[summaryWordIndex];
		if (summaryWord == 0) {
			assert(nextGateActiveSummaryWordIndices_.size() < nextGateActiveSummaryWordIndices_.capacity());
			nextGateActiveSummaryWordIndices_.push_back(static_cast<uint32_t>(summaryWordIndex));
		}
		summaryWord |= uint64_t{1} << (wordIndex % 64U);
	}
	void markVisibleNodeDirty(int32_t node, uint8_t initialState, bool forceMaterialization = false);
	void setChangedNodeState(int32_t node, uint8_t state) {
		const uint8_t previousState = nodeStates_[node];
		if (!isVisualTrackingDeferred_ && nodeHasVisibleCells_[node] != 0) {
			markVisibleNodeDirty(node, previousState);
		}
		nodeStates_[node] = state;
	}
	void setNodeState(int32_t node, uint8_t state);
	void markAllVisibleNodesDirty();
	void materializeVisibleStates() const;
	uint8_t resolveVisibleCellState(int32_t cell) const;
	void updateVisibleCell(int32_t cell) const;
	void resetChangeCollector();
	void advanceState();
	void resetInternal();
	uint64_t makeTopologySignature() const;
	void clear();

	int32_t width_ = 0;
	int32_t height_ = 0;
	bool compiled_ = false;
	bool graphLocalityOrderingApplied_ = false;
	uint64_t topologySignature_ = 0;
	uint64_t tickCount_ = 0;
	int64_t graphLocalityScore_ = 0;
	bool useGraphLocalityOrdering_ = false;
	bool isVisualTrackingDeferred_ = false;
	std::vector<int32_t> kinds_;
	std::vector<int32_t> initialStates_;
	std::vector<int32_t> clockHoldTicks_;
	std::vector<int32_t> meshIds_;
	std::vector<Component> components_;
	std::vector<ReadBinding> readBindings_;
	std::vector<WriteBinding> writeBindings_;
	std::vector<int32_t> cellToComponent_;
	std::vector<int32_t> cellNetwork_;
	std::vector<std::array<int32_t, SignalColorCount>> meshNetworksByCell_;
	std::vector<std::array<int32_t, CrossChannelCount>> crossNetworksByCell_;
	std::vector<int32_t> readBindingByCell_;
	std::vector<int32_t> writeBindingByCell_;
	std::vector<uint8_t> nodeStates_;
	std::vector<uint8_t> networkStates_;
	std::vector<int32_t> clockPhases_;
	std::vector<uint8_t> nodeIsComponent_;
	std::vector<ToolKind> nodeKinds_;
	std::vector<int32_t> nodeClockHoldTicks_;
	std::vector<uint8_t> nodeLatchInitialStates_;
	std::vector<uint8_t> nodeEvaluationPolicies_;
	std::vector<int32_t> componentInputCounts_;
	std::vector<int32_t> outgoingOffsets_;
	std::vector<int32_t> outgoingComponentEnds_;
	std::vector<int32_t> outgoingTargets_;
	std::vector<int32_t> incomingOffsets_;
	std::vector<int32_t> incomingSources_;
	std::vector<int32_t> componentNodes_;
	std::vector<int32_t> connectorNodes_;
	std::vector<int32_t> snapshotComponentNodes_;
	std::vector<int32_t> snapshotConnectorNodes_;
	std::vector<int32_t> clockNodes_;
	std::vector<uint64_t> nextGateWords_;
	std::vector<uint64_t> nextGateSummaryWords_;
	std::vector<uint64_t> currentGateWords_;
	std::vector<uint64_t> currentGateSummaryWords_;
	std::vector<uint32_t> nextGateActiveSummaryWordIndices_;
	std::vector<uint32_t> currentGateActiveSummaryWordIndices_;
	std::vector<uint8_t> nextGateStates_;
	std::vector<uint8_t> currentGateStates_;
	ConnectorEventQueue connectorQueueEvents_;
	std::vector<ComponentRuntimeState> componentRuntimeStates_;
	std::vector<ConnectorRuntimeState> connectorRuntimeStates_;
	std::array<int32_t, EvaluationModeCount> pendingComponentHeads_;
	std::array<int32_t, EvaluationModeCount> pendingComponentTails_;
	std::vector<uint64_t> connectorWorkWords_;
	std::vector<uint32_t> connectorWorkWordStamps_;
	std::vector<uint64_t> connectorActiveWordHierarchy_;
	std::vector<size_t> connectorActiveWordLevelOffsets_;
	uint32_t propagationStamp_ = 1;
	bool suppressLatchInputEdges_ = false;
	std::vector<size_t> visibleCellOffsets_;
	std::vector<int32_t> visibleCellIndices_;
	std::vector<size_t> cellVisibleNodeOffsets_;
	std::vector<int32_t> cellVisibleNodes_;
	std::vector<uint8_t> nodeHasVisibleCells_;
	mutable std::vector<uint32_t> dirtyNodeStamps_;
	mutable std::vector<uint8_t> dirtyNodeInitialStates_;
	mutable std::vector<int32_t> dirtyNodes_;
	mutable uint32_t dirtyNodeStamp_ = 1;
	mutable std::vector<uint32_t> materializedCellStamps_;
	mutable uint32_t materializedCellStamp_ = 1;
	mutable std::vector<uint8_t> visibleStates_;
	std::vector<uint8_t> reportedVisibleStates_;
	mutable std::vector<uint32_t> changedCellStamps_;
	mutable std::vector<int32_t> changedCells_;
	mutable uint32_t changeStamp_ = 1;
};

} // namespace ocb
