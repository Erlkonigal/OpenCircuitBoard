#pragma once

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
	struct Component {
		ToolKind kind = ToolKind::Empty;
		std::vector<int32_t> cells;
		int32_t clockHoldTicks = 0;
		uint8_t latchInitialState = 0;
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

	static bool isKnownKind(int32_t kind);
	static bool isTrace(ToolKind kind);
	static bool isBus(ToolKind kind);
	static bool isConductor(ToolKind kind);
	static bool isDevice(ToolKind kind);
	static bool isReadSource(ToolKind kind);
	static bool isWriteTarget(ToolKind kind);
	static bool allowsMultipleWrites(ToolKind kind);
	static int32_t colorForKind(ToolKind kind);

	uint8_t evaluateComponent(int32_t node) const;
	void buildExecutionGraph();
	void rebuildDerivedState(const std::vector<uint8_t> &componentStates);
	void propagateStateChange(int32_t sourceNode, uint8_t oldState, uint8_t newState);
	void drainConnectorQueue();
	void enqueueGate(int32_t node);
	void setNodeState(int32_t node, uint8_t state);
	void markVisibleNodeDirty(int32_t node);
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
	std::vector<int32_t> nodeInputCounts_;
	std::vector<int32_t> nodeInputHighCounts_;
	std::vector<int32_t> outgoingOffsets_;
	std::vector<int32_t> outgoingTargets_;
	std::vector<int32_t> incomingOffsets_;
	std::vector<int32_t> incomingSources_;
	std::vector<int32_t> componentNodes_;
	std::vector<int32_t> gateIndexByNode_;
	std::vector<int32_t> connectorNodes_;
	std::vector<int32_t> snapshotComponentNodes_;
	std::vector<int32_t> snapshotConnectorNodes_;
	std::vector<int32_t> clockNodes_;
	std::vector<uint64_t> nextGateWords_;
	std::vector<uint64_t> nextGateSummaryWords_;
	std::vector<uint64_t> currentGateWords_;
	std::vector<uint64_t> currentGateSummaryWords_;
	std::vector<int32_t> pendingStateNodes_;
	std::vector<uint8_t> pendingNextStates_;
	std::vector<int32_t> connectorQueueNodes_;
	std::vector<int8_t> connectorQueueDeltas_;
	std::vector<size_t> visibleCellOffsets_;
	std::vector<int32_t> visibleCellIndices_;
	std::vector<int32_t> cellPrimaryNode_;
	std::vector<int32_t> cellSecondaryNode_;
	mutable std::vector<uint32_t> dirtyNodeStamps_;
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
