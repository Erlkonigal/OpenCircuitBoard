#pragma once

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
	bool compile(const CompileInput &input, CompileError &error);
	std::vector<int32_t> advanceTick();
	std::vector<int32_t> getStates() const;
	std::vector<int32_t> reset();
	std::vector<uint8_t> captureState() const;
	bool restoreState(const std::vector<uint8_t> &snapshot, std::string &errorReason);
	bool isCompiled() const;

private:
	struct Component {
		ToolKind kind = ToolKind::Empty;
		std::vector<int32_t> cells;
		int32_t clockHoldTicks = 0;
		uint8_t latchInitialState = 0;
	};

	struct ReadBinding {
		int32_t sourceComponent = -1;
		std::vector<int32_t> outputNetworks;
	};

	struct WriteBinding {
		int32_t inputNetwork = -1;
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

	uint8_t evaluateComponent(int32_t componentId, const std::vector<uint8_t> &networkStates, uint8_t currentState) const;
	void resetInternal();
	std::vector<int32_t> makeStateDeltas(const std::vector<int32_t> &previousStates) const;
	uint64_t makeTopologySignature() const;
	void clear();

	int32_t width_ = 0;
	int32_t height_ = 0;
	bool compiled_ = false;
	uint64_t topologySignature_ = 0;
	uint64_t tickCount_ = 0;
	std::vector<int32_t> kinds_;
	std::vector<int32_t> initialStates_;
	std::vector<int32_t> clockHoldTicks_;
	std::vector<int32_t> meshIds_;
	std::vector<Component> components_;
	std::vector<ReadBinding> readBindings_;
	std::vector<WriteBinding> writeBindings_;
	std::vector<std::vector<int32_t>> networkReadBindings_;
	std::vector<std::vector<int32_t>> componentInputNetworks_;
	std::vector<int32_t> cellToComponent_;
	std::vector<int32_t> cellNetwork_;
	std::vector<int32_t> meshNetworkByCell_;
	std::vector<int32_t> crossHorizontalNetworkByCell_;
	std::vector<int32_t> crossVerticalNetworkByCell_;
	std::vector<int32_t> readSourceByCell_;
	std::vector<int32_t> writeNetworkByCell_;
	std::vector<uint8_t> componentStates_;
	std::vector<uint8_t> networkStates_;
	std::vector<int32_t> clockPhases_;
};

} // namespace ocb
