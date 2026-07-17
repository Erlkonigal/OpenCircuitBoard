#pragma once

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

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
	std::vector<int32_t> advanceTicksSilent(int32_t tickCount);
	std::vector<int32_t> drainStateChanges();
	std::vector<int32_t> getStates() const;
	bool toggleLatch(int32_t cellIndex, std::vector<int32_t> &changes, std::string &errorReason);
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
	};

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

		void reserve(size_t capacity) {
			storage_.reserve(capacity);
		}

		size_t size() const {
			return size_;
		}

		int32_t operator[](size_t index) const {
			return storage_[index];
		}

		void push_back(int32_t event) {
			if (size_ < storage_.size()) {
				storage_[size_] = event;
			} else {
				storage_.push_back(event);
			}
			++size_;
		}

	private:
		// Retain constructed slots so repeated ticks overwrite the high-water range.
		std::vector<int32_t> storage_;
		size_t size_ = 0;
	};

	struct ReadBinding {
		int32_t sourceComponent = -1;
		int32_t sourceWriteCell = -1;
		int32_t sourceNetwork = -1;
		int32_t signalNetwork = -1;
		std::vector<int32_t> outputNetworks;
	};

	struct WriteBinding {
		int32_t cell = -1;
		int32_t inputNetwork = -1;
		int32_t inputReadCell = -1;
		std::vector<int32_t> targetComponents;
	};

	static constexpr uint8_t ForcedVisibleNodeInitialState = 2;

	static bool isKnownKind(int32_t kind);
	static bool isTrace(ToolKind kind);
	static bool isBus(ToolKind kind);
	static bool isConductor(ToolKind kind);
	static bool isDevice(ToolKind kind);
	static bool isReadSource(ToolKind kind);
	static bool isWriteTarget(ToolKind kind);
	static bool allowsMultipleWrites(ToolKind kind);
	static int32_t colorForKind(ToolKind kind);
	// Nonnegative events encode high states; bitwise complements encode low states.
	static int32_t encodeConnectorEvent(int32_t node, uint8_t state) {
		return state != 0 ? node : ~node;
	}

	uint8_t evaluateComponent(int32_t node) const;
	uint8_t evaluateComponent(int32_t node, int32_t highInputCount) const;
	void buildExecutionGraph();
	void rebuildDerivedState(const std::vector<uint8_t> &componentStates);
	void propagateStateChange(int32_t sourceNode, uint8_t oldState, uint8_t newState);
	void drainConnectorQueue();
	void beginPropagationBatch();
	void flushComponentInputDeltas();
	bool isComponentGateQueued(int32_t componentNode) const {
		const size_t gateIndex = static_cast<size_t>(componentNode);
		return (nextGateWords_[gateIndex / 64U] & (uint64_t{1} << (gateIndex % 64U))) != 0;
	}
	void accumulateComponentInputDelta(int32_t componentNode, int32_t stateDelta) {
		if (componentInputStamps_[componentNode] != propagationStamp_) {
			componentInputStamps_[componentNode] = propagationStamp_;
			pendingComponentInputDeltas_[componentNode] = stateDelta;
			pendingComponentInputs_.push_back(componentNode);
			return;
		}
		pendingComponentInputDeltas_[componentNode] += stateDelta;
	}
	void accumulateConnectorDelta(int32_t connectorNode, int32_t stateDelta) {
		if (connectorDeltaStamps_[connectorNode] == propagationStamp_) {
			pendingConnectorDeltas_[connectorNode] += stateDelta;
			return;
		}
		connectorDeltaStamps_[connectorNode] = propagationStamp_;
		pendingConnectorDeltas_[connectorNode] = stateDelta;
		const int32_t connectorRank = connectorTopologicalRanks_[connectorNode];
		const size_t workWordIndex = static_cast<size_t>(connectorRank) / 64U;
		uint64_t &workWord = connectorWorkWords_[workWordIndex];
		if (connectorWorkWordStamps_[workWordIndex] != propagationStamp_) {
			connectorWorkWordStamps_[workWordIndex] = propagationStamp_;
			workWord = 0;
			connectorActiveWordHeap_.push_back(static_cast<int32_t>(workWordIndex));
			const auto laterWorkWord = [](int32_t left, int32_t right) {
				return left > right;
			};
			std::push_heap(connectorActiveWordHeap_.begin(), connectorActiveWordHeap_.end(), laterWorkWord);
		}
		workWord |= uint64_t{1} << (static_cast<size_t>(connectorRank) % 64U);
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
		nextGateSummaryWords_[summaryWordIndex] |= uint64_t{1} << (wordIndex % 64U);
	}
	void markVisibleNodeDirty(int32_t node, uint8_t initialState, bool forceMaterialization = false);
	void setChangedNodeState(int32_t node, uint8_t state) {
		const uint8_t previousState = nodeStates_[node];
		if (nodeHasVisibleCells_[node] != 0) {
			markVisibleNodeDirty(node, previousState);
		}
		nodeStates_[node] = state;
	}
	void setNodeState(int32_t node, uint8_t state);
	void markAllVisibleNodesDirty();
	void materializeVisibleStates() const;
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
	std::vector<int32_t> kinds_;
	std::vector<int32_t> initialStates_;
	std::vector<int32_t> clockHoldTicks_;
	std::vector<int32_t> meshIds_;
	std::vector<Component> components_;
	std::vector<ReadBinding> readBindings_;
	std::vector<WriteBinding> writeBindings_;
	std::vector<std::vector<int32_t>> componentInputNetworks_;
	std::vector<int32_t> cellToComponent_;
	std::vector<int32_t> cellNetwork_;
	std::vector<int32_t> meshNetworkByCell_;
	std::vector<int32_t> crossHorizontalNetworkByCell_;
	std::vector<int32_t> crossVerticalNetworkByCell_;
	std::vector<int32_t> readBindingByCell_;
	std::vector<int32_t> writeNetworkByCell_;
	std::vector<int32_t> readVisibleNodeByCell_;
	std::vector<uint8_t> nodeStates_;
	std::vector<uint8_t> networkStates_;
	std::vector<int32_t> clockPhases_;
	std::vector<uint8_t> nodeIsComponent_;
	std::vector<ToolKind> nodeKinds_;
	std::vector<int32_t> nodeClockHoldTicks_;
	std::vector<uint8_t> nodeLatchInitialStates_;
	std::vector<EvaluationMode> nodeEvaluationModes_;
	std::vector<int32_t> nodeInputCounts_;
	std::vector<int32_t> nodeInputHighCounts_;
	std::vector<int32_t> outgoingOffsets_;
	std::vector<int32_t> outgoingComponentEnds_;
	std::vector<int32_t> outgoingTargets_;
	std::vector<int32_t> incomingOffsets_;
	std::vector<int32_t> incomingSources_;
	std::vector<int32_t> componentNodes_;
	std::vector<int32_t> connectorNodes_;
	std::vector<int32_t> connectorTopologicalRanks_;
	std::vector<int32_t> snapshotComponentNodes_;
	std::vector<int32_t> snapshotConnectorNodes_;
	std::vector<int32_t> clockNodes_;
	std::vector<uint64_t> nextGateWords_;
	std::vector<uint64_t> nextGateSummaryWords_;
	std::vector<uint64_t> currentGateWords_;
	std::vector<uint64_t> currentGateSummaryWords_;
	std::vector<uint8_t> nextGateStates_;
	std::vector<uint8_t> currentGateStates_;
	ConnectorEventQueue connectorQueueEvents_;
	std::vector<int32_t> pendingComponentInputDeltas_;
	std::vector<uint32_t> componentInputStamps_;
	std::vector<int32_t> pendingComponentInputs_;
	std::vector<int32_t> pendingConnectorDeltas_;
	std::vector<uint32_t> connectorDeltaStamps_;
	std::vector<uint64_t> connectorWorkWords_;
	std::vector<uint32_t> connectorWorkWordStamps_;
	std::vector<int32_t> connectorActiveWordHeap_;
	uint32_t propagationStamp_ = 1;
	std::vector<size_t> visibleCellOffsets_;
	std::vector<int32_t> visibleCellIndices_;
	std::vector<int32_t> cellPrimaryNode_;
	std::vector<int32_t> cellSecondaryNode_;
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
