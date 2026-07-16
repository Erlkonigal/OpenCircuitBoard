#include "SimulationCore.hpp"

#include <algorithm>
#include <array>
#include <limits>
#include <unordered_map>

namespace ocb {
namespace {

constexpr uint32_t SnapshotMagic = 0x4f434253;
constexpr uint32_t SnapshotVersion = 1;
constexpr uint64_t FnvOffsetBasis = 1469598103934665603ULL;
constexpr uint64_t FnvPrime = 1099511628211ULL;

class DisjointSet {
public:
	explicit DisjointSet(int32_t count) {
		parent_.resize(count);
		rank_.assign(count, 0);
		for (int32_t index = 0; index < count; ++index) {
			parent_[index] = index;
		}
	}

	int32_t add() {
		const int32_t index = static_cast<int32_t>(parent_.size());
		parent_.push_back(index);
		rank_.push_back(0);
		return index;
	}

	int32_t find(int32_t index) {
		int32_t root = index;
		while (parent_[root] != root) {
			root = parent_[root];
		}
		while (parent_[index] != index) {
			const int32_t next = parent_[index];
			parent_[index] = root;
			index = next;
		}
		return root;
	}

	void unite(int32_t left, int32_t right) {
		left = find(left);
		right = find(right);
		if (left == right) {
			return;
		}
		if (rank_[left] < rank_[right]) {
			std::swap(left, right);
		}
		parent_[right] = left;
		if (rank_[left] == rank_[right]) {
			++rank_[left];
		}
	}

private:
	std::vector<int32_t> parent_;
	std::vector<uint8_t> rank_;
};

void appendU32(std::vector<uint8_t> &bytes, uint32_t value) {
	for (int32_t shift = 0; shift < 32; shift += 8) {
		bytes.push_back(static_cast<uint8_t>((value >> shift) & 0xffU));
	}
}

void appendU64(std::vector<uint8_t> &bytes, uint64_t value) {
	for (int32_t shift = 0; shift < 64; shift += 8) {
		bytes.push_back(static_cast<uint8_t>((value >> shift) & 0xffU));
	}
}

bool readU32(const std::vector<uint8_t> &bytes, size_t &offset, uint32_t &value) {
	if (offset > bytes.size() || bytes.size() - offset < 4) {
		return false;
	}
	value = 0;
	for (int32_t shift = 0; shift < 32; shift += 8) {
		value |= static_cast<uint32_t>(bytes[offset++]) << shift;
	}
	return true;
}

bool readU64(const std::vector<uint8_t> &bytes, size_t &offset, uint64_t &value) {
	if (offset > bytes.size() || bytes.size() - offset < 8) {
		return false;
	}
	value = 0;
	for (int32_t shift = 0; shift < 64; shift += 8) {
		value |= static_cast<uint64_t>(bytes[offset++]) << shift;
	}
	return true;
}

bool appendUnique(std::vector<int32_t> &values, int32_t value) {
	if (std::find(values.begin(), values.end(), value) != values.end()) {
		return false;
	}
	values.push_back(value);
	return true;
}

void hashInt(uint64_t &hash, int32_t value) {
	const uint32_t unsignedValue = static_cast<uint32_t>(value);
	for (int32_t shift = 0; shift < 32; shift += 8) {
		hash ^= (unsignedValue >> shift) & 0xffU;
		hash *= FnvPrime;
	}
}

} // namespace

bool SimulationCore::isKnownKind(int32_t kind) {
	return kind >= static_cast<int32_t>(ToolKind::Empty) && kind <= static_cast<int32_t>(ToolKind::Led);
}

bool SimulationCore::isTrace(ToolKind kind) {
	return kind >= ToolKind::Trace && kind <= ToolKind::TraceMagenta;
}

bool SimulationCore::isBus(ToolKind kind) {
	return kind >= ToolKind::Bus && kind <= ToolKind::BusMagenta;
}

bool SimulationCore::isConductor(ToolKind kind) {
	return isTrace(kind) || isBus(kind);
}

bool SimulationCore::isDevice(ToolKind kind) {
	return kind >= ToolKind::Buffer && kind <= ToolKind::Led;
}

bool SimulationCore::isReadSource(ToolKind kind) {
	return isDevice(kind) || kind == ToolKind::Write;
}

bool SimulationCore::isWriteTarget(ToolKind kind) {
	return (isDevice(kind) && kind != ToolKind::Clock) || kind == ToolKind::Read;
}

bool SimulationCore::allowsMultipleWrites(ToolKind kind) {
	switch (kind) {
		case ToolKind::And:
		case ToolKind::Nand:
		case ToolKind::Or:
		case ToolKind::Nor:
		case ToolKind::Xor:
		case ToolKind::Xnor:
			return true;
		default:
			return false;
	}
}

int32_t SimulationCore::colorForKind(ToolKind kind) {
	switch (kind) {
		case ToolKind::Trace:
		case ToolKind::BusYellow:
			return 1;
		case ToolKind::TraceRed:
		case ToolKind::BusRed:
			return 2;
		case ToolKind::TraceGreen:
		case ToolKind::BusGreen:
			return 3;
		case ToolKind::TraceBlue:
		case ToolKind::Bus:
			return 4;
		case ToolKind::TraceCyan:
		case ToolKind::BusCyan:
			return 5;
		case ToolKind::TraceMagenta:
		case ToolKind::BusMagenta:
			return 6;
		default:
			return 0;
	}
}

void SimulationCore::clear() {
	width_ = 0;
	height_ = 0;
	compiled_ = false;
	topologySignature_ = 0;
	tickCount_ = 0;
	kinds_.clear();
	initialStates_.clear();
	clockHoldTicks_.clear();
	meshIds_.clear();
	components_.clear();
	readBindings_.clear();
	writeBindings_.clear();
	componentInputNetworks_.clear();
	cellToComponent_.clear();
	cellNetwork_.clear();
	meshNetworkByCell_.clear();
	crossHorizontalNetworkByCell_.clear();
	crossVerticalNetworkByCell_.clear();
	readBindingByCell_.clear();
	writeNetworkByCell_.clear();
	componentStates_.clear();
	networkStates_.clear();
	clockPhases_.clear();
	nextComponentStates_.clear();
	nextNetworkStates_.clear();
	nextClockPhases_.clear();
}

bool SimulationCore::compile(const CompileInput &input, CompileError &error) {
	clear();
	error = CompileError();
	const auto fail = [&](int32_t cell, const char *reason) {
		error.errorX = cell >= 0 && width_ > 0 ? cell % width_ : -1;
		error.errorY = cell >= 0 && width_ > 0 ? cell / width_ : -1;
		error.errorReason = reason;
		clear();
		return false;
	};

	if (input.width <= 0 || input.height <= 0) {
		return fail(-1, "invalid_grid_size");
	}
	const int64_t cellCount64 = static_cast<int64_t>(input.width) * static_cast<int64_t>(input.height);
	if (cellCount64 > std::numeric_limits<int32_t>::max()) {
		return fail(-1, "grid_too_large");
	}
	const int32_t cellCount = static_cast<int32_t>(cellCount64);
	if (static_cast<int32_t>(input.kinds.size()) != cellCount ||
			static_cast<int32_t>(input.initialStates.size()) != cellCount ||
			static_cast<int32_t>(input.clockHoldTicks.size()) != cellCount ||
			static_cast<int32_t>(input.meshIds.size()) != cellCount) {
		return fail(-1, "array_size_mismatch");
	}

	width_ = input.width;
	height_ = input.height;
	kinds_ = input.kinds;
	initialStates_ = input.initialStates;
	clockHoldTicks_ = input.clockHoldTicks;
	meshIds_ = input.meshIds;

	for (int32_t cell = 0; cell < cellCount; ++cell) {
		const ToolKind kind = static_cast<ToolKind>(kinds_[cell]);
		if (!isKnownKind(kinds_[cell])) {
			return fail(cell, "unknown_kind");
		}
		if (kind == ToolKind::Clock && clockHoldTicks_[cell] <= 0) {
			return fail(cell, "invalid_clock_hold_ticks");
		}
		if (kind == ToolKind::Mesh && meshIds_[cell] <= 0) {
			return fail(cell, "missing_mesh_id");
		}
	}

	const auto neighborAt = [&](int32_t cell, int32_t dx, int32_t dy) {
		const int32_t x = cell % width_;
		const int32_t y = cell / width_;
		const int32_t nextX = x + dx;
		const int32_t nextY = y + dy;
		if (nextX < 0 || nextX >= width_ || nextY < 0 || nextY >= height_) {
			return -1;
		}
		return nextY * width_ + nextX;
	};
	const std::array<std::array<int32_t, 2>, 4> directions = {{{-1, 0}, {1, 0}, {0, -1}, {0, 1}}};
	DisjointSet componentSet(cellCount);
	for (int32_t cell = 0; cell < cellCount; ++cell) {
		const ToolKind kind = static_cast<ToolKind>(kinds_[cell]);
		if (!isDevice(kind)) {
			continue;
		}
		for (const std::array<int32_t, 2> direction : {std::array<int32_t, 2>{1, 0}, std::array<int32_t, 2>{0, 1}}) {
			const int32_t neighbor = neighborAt(cell, direction[0], direction[1]);
			if (neighbor < 0 || static_cast<ToolKind>(kinds_[neighbor]) != kind) {
				continue;
			}
			if (kind == ToolKind::Clock && clockHoldTicks_[cell] != clockHoldTicks_[neighbor]) {
				continue;
			}
			if (kind == ToolKind::Latch && (initialStates_[cell] != 0) != (initialStates_[neighbor] != 0)) {
				continue;
			}
			componentSet.unite(cell, neighbor);
		}
	}

	cellToComponent_.assign(cellCount, -1);
	std::unordered_map<int32_t, int32_t> componentByRoot;
	for (int32_t cell = 0; cell < cellCount; ++cell) {
		const ToolKind kind = static_cast<ToolKind>(kinds_[cell]);
		if (!isDevice(kind)) {
			continue;
		}
		const int32_t root = componentSet.find(cell);
		auto found = componentByRoot.find(root);
		int32_t componentId = -1;
		if (found == componentByRoot.end()) {
			componentId = static_cast<int32_t>(components_.size());
			componentByRoot.emplace(root, componentId);
			Component component;
			component.kind = kind;
			component.clockHoldTicks = kind == ToolKind::Clock ? clockHoldTicks_[cell] : 0;
			component.latchInitialState = initialStates_[cell] != 0 ? 1 : 0;
			components_.push_back(std::move(component));
		} else {
			componentId = found->second;
		}
		Component &component = components_[componentId];
		component.cells.push_back(cell);
		cellToComponent_[cell] = componentId;
	}

	DisjointSet conductorSet(cellCount);
	for (int32_t cell = 0; cell < cellCount; ++cell) {
		const ToolKind kind = static_cast<ToolKind>(kinds_[cell]);
		if (!isConductor(kind)) {
			continue;
		}
		for (const std::array<int32_t, 2> direction : {std::array<int32_t, 2>{1, 0}, std::array<int32_t, 2>{0, 1}}) {
			const int32_t neighbor = neighborAt(cell, direction[0], direction[1]);
			if (neighbor >= 0 && isConductor(static_cast<ToolKind>(kinds_[neighbor])) &&
					colorForKind(kind) == colorForKind(static_cast<ToolKind>(kinds_[neighbor]))) {
				conductorSet.unite(cell, neighbor);
			}
		}
	}

	std::vector<int32_t> crossHorizontalRepresentative(cellCount, -1);
	std::vector<int32_t> crossVerticalRepresentative(cellCount, -1);
	const auto connectCrossPair = [&](int32_t cross, int32_t first, int32_t second, std::vector<int32_t> &representatives) {
		if (first < 0 || second < 0) {
			return;
		}
		const ToolKind firstKind = static_cast<ToolKind>(kinds_[first]);
		const ToolKind secondKind = static_cast<ToolKind>(kinds_[second]);
		if (!isConductor(firstKind) || !isConductor(secondKind)) {
			return;
		}
		if (colorForKind(firstKind) != colorForKind(secondKind)) {
			return;
		}
		conductorSet.unite(first, second);
		representatives[cross] = first;
	};
	for (int32_t cell = 0; cell < cellCount; ++cell) {
		if (static_cast<ToolKind>(kinds_[cell]) != ToolKind::Cross) {
			continue;
		}
		connectCrossPair(cell, neighborAt(cell, -1, 0), neighborAt(cell, 1, 0), crossHorizontalRepresentative);
		connectCrossPair(cell, neighborAt(cell, 0, -1), neighborAt(cell, 0, 1), crossVerticalRepresentative);
	}

	std::vector<int32_t> meshAnchorRepresentative(cellCount, -1);
	std::unordered_map<uint64_t, int32_t> meshAnchors;
	for (int32_t cell = 0; cell < cellCount; ++cell) {
		if (static_cast<ToolKind>(kinds_[cell]) != ToolKind::Mesh) {
			continue;
		}
		std::vector<int32_t> traceNeighbors;
		// A Mesh carries one channel, selected by the first Trace in W/E/N/S order.
		int32_t color = 0;
		for (const std::array<int32_t, 2> &direction : directions) {
			const int32_t neighbor = neighborAt(cell, direction[0], direction[1]);
			if (neighbor < 0 || !isTrace(static_cast<ToolKind>(kinds_[neighbor]))) {
				continue;
			}
			const int32_t neighborColor = colorForKind(static_cast<ToolKind>(kinds_[neighbor]));
			if (color == 0) {
				color = neighborColor;
			}
			if (color == neighborColor) {
				traceNeighbors.push_back(neighbor);
			}
		}
		if (traceNeighbors.empty()) {
			continue;
		}
		const uint64_t key = (static_cast<uint64_t>(static_cast<uint32_t>(meshIds_[cell])) << 8U) | static_cast<uint64_t>(color);
		auto found = meshAnchors.find(key);
		int32_t anchor = -1;
		if (found == meshAnchors.end()) {
			anchor = conductorSet.add();
			meshAnchors.emplace(key, anchor);
		} else {
			anchor = found->second;
		}
		meshAnchorRepresentative[cell] = anchor;
		for (int32_t neighbor : traceNeighbors) {
			conductorSet.unite(anchor, neighbor);
		}
	}

	cellNetwork_.assign(cellCount, -1);
	meshNetworkByCell_.assign(cellCount, -1);
	crossHorizontalNetworkByCell_.assign(cellCount, -1);
	crossVerticalNetworkByCell_.assign(cellCount, -1);
	std::unordered_map<int32_t, int32_t> networkByRoot;
	const auto getNetwork = [&](int32_t node) {
		const int32_t root = conductorSet.find(node);
		auto found = networkByRoot.find(root);
		if (found != networkByRoot.end()) {
			return found->second;
		}
		const int32_t network = static_cast<int32_t>(networkByRoot.size());
		networkByRoot.emplace(root, network);
		return network;
	};
	for (int32_t cell = 0; cell < cellCount; ++cell) {
		if (isConductor(static_cast<ToolKind>(kinds_[cell]))) {
			cellNetwork_[cell] = getNetwork(cell);
		}
		if (meshAnchorRepresentative[cell] >= 0) {
			meshNetworkByCell_[cell] = getNetwork(meshAnchorRepresentative[cell]);
		}
		if (crossHorizontalRepresentative[cell] >= 0) {
			crossHorizontalNetworkByCell_[cell] = getNetwork(crossHorizontalRepresentative[cell]);
		}
		if (crossVerticalRepresentative[cell] >= 0) {
			crossVerticalNetworkByCell_[cell] = getNetwork(crossVerticalRepresentative[cell]);
		}
	}
	networkStates_.assign(networkByRoot.size(), 0);

	readBindingByCell_.assign(cellCount, -1);
	writeNetworkByCell_.assign(cellCount, -1);
	componentInputNetworks_.resize(components_.size());
	struct ReadPort {
		int32_t sourceComponent = -1;
		int32_t sourceWriteCell = -1;
		std::vector<int32_t> outputNetworks;
		std::vector<int32_t> adjacentWriteCells;
	};
	struct WritePort {
		int32_t inputNetwork = -1;
		int32_t inputReadCell = -1;
		std::vector<int32_t> targetComponents;
		std::vector<int32_t> adjacentReadCells;
	};
	std::vector<ReadPort> readPorts(cellCount);
	std::vector<WritePort> writePorts(cellCount);
	for (int32_t cell = 0; cell < cellCount; ++cell) {
		const ToolKind kind = static_cast<ToolKind>(kinds_[cell]);
		if (kind == ToolKind::Read) {
			ReadPort &port = readPorts[cell];
			for (const std::array<int32_t, 2> &direction : directions) {
				const int32_t neighbor = neighborAt(cell, direction[0], direction[1]);
				if (neighbor < 0) {
					continue;
				}
				const ToolKind neighborKind = static_cast<ToolKind>(kinds_[neighbor]);
				if (isTrace(neighborKind)) {
					appendUnique(port.outputNetworks, cellNetwork_[neighbor]);
				} else if (neighborKind == ToolKind::Write) {
					appendUnique(port.adjacentWriteCells, neighbor);
				} else if (isReadSource(neighborKind)) {
					const int32_t component = cellToComponent_[neighbor];
					if (port.sourceComponent >= 0 && port.sourceComponent != component) {
						return fail(cell, "read_requires_one_source");
					}
					port.sourceComponent = component;
				}
			}
			continue;
		}
		if (kind != ToolKind::Write) {
			continue;
		}
		WritePort &port = writePorts[cell];
		int32_t traceSides = 0;
		for (const std::array<int32_t, 2> &direction : directions) {
			const int32_t neighbor = neighborAt(cell, direction[0], direction[1]);
			if (neighbor < 0) {
				continue;
			}
			const ToolKind neighborKind = static_cast<ToolKind>(kinds_[neighbor]);
			if (isTrace(neighborKind)) {
				++traceSides;
				port.inputNetwork = cellNetwork_[neighbor];
			} else if (neighborKind == ToolKind::Read) {
				appendUnique(port.adjacentReadCells, neighbor);
			} else if (isWriteTarget(neighborKind)) {
				appendUnique(port.targetComponents, cellToComponent_[neighbor]);
			}
		}
		if (traceSides > 1) {
			return fail(cell, "write_requires_one_input");
		}
	}

	for (int32_t cell = 0; cell < cellCount; ++cell) {
		if (static_cast<ToolKind>(kinds_[cell]) != ToolKind::Read) {
			continue;
		}
		ReadPort &readPort = readPorts[cell];
		for (int32_t writeCell : readPort.adjacentWriteCells) {
			if (writePorts[writeCell].inputNetwork < 0) {
				continue;
			}
			if (readPort.sourceComponent >= 0 || (readPort.sourceWriteCell >= 0 && readPort.sourceWriteCell != writeCell)) {
				return fail(cell, "read_requires_one_source");
			}
			readPort.sourceWriteCell = writeCell;
		}
	}

	// Resolve direct connector direction from device or Trace inputs: Read drives Write, then Write drives Read.
	bool changed = true;
	while (changed) {
		changed = false;
		for (int32_t cell = 0; cell < cellCount; ++cell) {
			if (static_cast<ToolKind>(kinds_[cell]) != ToolKind::Read) {
				continue;
			}
			const ReadPort &readPort = readPorts[cell];
			if (readPort.sourceComponent < 0 && readPort.sourceWriteCell < 0) {
				continue;
			}
			for (int32_t writeCell : readPort.adjacentWriteCells) {
				WritePort &writePort = writePorts[writeCell];
				if (readPort.sourceWriteCell == writeCell) {
					continue;
				}
				if (writePort.inputNetwork >= 0) {
					continue;
				}
				if (writePort.inputReadCell >= 0) {
					if (writePort.inputReadCell != cell) {
						return fail(writeCell, "write_requires_one_input");
					}
					continue;
				}
				writePort.inputReadCell = cell;
				changed = true;
			}
		}
		for (int32_t cell = 0; cell < cellCount; ++cell) {
			if (static_cast<ToolKind>(kinds_[cell]) != ToolKind::Write) {
				continue;
			}
			const WritePort &writePort = writePorts[cell];
			if (writePort.inputNetwork < 0 && writePort.inputReadCell < 0) {
				continue;
			}
			for (int32_t readCell : writePort.adjacentReadCells) {
				if (readCell == writePort.inputReadCell) {
					continue;
				}
				ReadPort &readPort = readPorts[readCell];
				if (readPort.sourceComponent >= 0 || (readPort.sourceWriteCell >= 0 && readPort.sourceWriteCell != cell)) {
					return fail(readCell, "read_requires_one_source");
				}
				if (readPort.sourceWriteCell < 0) {
					readPort.sourceWriteCell = cell;
					changed = true;
				}
			}
		}
	}

	for (int32_t cell = 0; cell < cellCount; ++cell) {
		if (static_cast<ToolKind>(kinds_[cell]) != ToolKind::Read) {
			continue;
		}
		const ReadPort &readPort = readPorts[cell];
		if ((readPort.sourceComponent >= 0) == (readPort.sourceWriteCell >= 0)) {
			return fail(cell, "read_requires_one_source");
		}
		bool hasDirectWriteOutput = false;
		for (int32_t writeCell : readPort.adjacentWriteCells) {
			if (writePorts[writeCell].inputReadCell == cell) {
				hasDirectWriteOutput = true;
				break;
			}
		}
		if (readPort.outputNetworks.empty() && !hasDirectWriteOutput) {
			return fail(cell, "read_requires_output");
		}
		ReadBinding readBinding;
		readBinding.sourceComponent = readPort.sourceComponent;
		readBinding.sourceWriteCell = readPort.sourceWriteCell;
		readBinding.outputNetworks = readPort.outputNetworks;
		const int32_t bindingId = static_cast<int32_t>(readBindings_.size());
		readBindingByCell_[cell] = bindingId;
		readBindings_.push_back(std::move(readBinding));
	}

	for (int32_t cell = 0; cell < cellCount; ++cell) {
		if (static_cast<ToolKind>(kinds_[cell]) != ToolKind::Write) {
			continue;
		}
		const WritePort &writePort = writePorts[cell];
		if (writePort.inputNetwork < 0 && writePort.inputReadCell < 0) {
			return fail(cell, "write_requires_one_input");
		}
		bool hasDirectedReadTarget = false;
		for (int32_t readCell : writePort.adjacentReadCells) {
			if (readCell != writePort.inputReadCell && readPorts[readCell].sourceWriteCell == cell) {
				hasDirectedReadTarget = true;
				break;
			}
		}
		if (writePort.targetComponents.empty() && !hasDirectedReadTarget) {
			return fail(cell, "write_requires_target");
		}
		WriteBinding binding;
		binding.cell = cell;
		binding.inputNetwork = writePort.inputNetwork;
		binding.inputReadCell = writePort.inputReadCell;
		binding.targetComponents = writePort.targetComponents;
		writeBindings_.push_back(std::move(binding));
	}

	for (ReadBinding &binding : readBindings_) {
		binding.signalNetwork = static_cast<int32_t>(networkStates_.size());
		networkStates_.push_back(0);
	}

	for (WriteBinding &binding : writeBindings_) {
		if (binding.inputReadCell >= 0) {
			const int32_t readBindingId = readBindingByCell_[binding.inputReadCell];
			if (readBindingId < 0) {
				return fail(binding.inputReadCell, "write_requires_one_input");
			}
			binding.inputNetwork = readBindings_[readBindingId].signalNetwork;
		}
		writeNetworkByCell_[binding.cell] = binding.inputNetwork;
		for (int32_t component : binding.targetComponents) {
			componentInputNetworks_[component].push_back(binding.inputNetwork);
		}
	}

	for (ReadBinding &binding : readBindings_) {
		if (binding.sourceWriteCell < 0) {
			continue;
		}
		binding.sourceNetwork = writeNetworkByCell_[binding.sourceWriteCell];
		if (binding.sourceNetwork < 0) {
			return fail(binding.sourceWriteCell, "read_requires_one_source");
		}
	}

	for (int32_t component = 0; component < static_cast<int32_t>(components_.size()); ++component) {
		if (!allowsMultipleWrites(components_[component].kind) && componentInputNetworks_[component].size() > 1) {
			return fail(components_[component].cells.front(), "multiple_write_inputs");
		}
	}

	componentStates_.assign(components_.size(), 0);
	clockPhases_.assign(components_.size(), 0);
	topologySignature_ = makeTopologySignature();
	resetInternal();
	compiled_ = true;
	return true;
}

uint8_t SimulationCore::evaluateComponent(int32_t componentId, const std::vector<uint8_t> &networkStates, uint8_t currentState) const {
	const Component &component = components_[componentId];
	const std::vector<int32_t> &inputs = componentInputNetworks_[componentId];
	const auto firstInput = [&]() {
		return inputs.empty() ? static_cast<uint8_t>(0) : networkStates[inputs.front()];
	};
	bool allHigh = true;
	bool anyHigh = false;
	bool parity = false;
	for (int32_t network : inputs) {
		const bool value = networkStates[network] != 0;
		allHigh = allHigh && value;
		anyHigh = anyHigh || value;
		parity = parity != value;
	}

	switch (component.kind) {
		case ToolKind::Buffer:
			return firstInput();
		case ToolKind::And:
			return allHigh ? 1 : 0;
		case ToolKind::Or:
			return anyHigh ? 1 : 0;
		case ToolKind::Xor:
			return parity ? 1 : 0;
		case ToolKind::Not:
			return firstInput() == 0 ? 1 : 0;
		case ToolKind::Nand:
			return allHigh ? 0 : 1;
		case ToolKind::Nor:
			return anyHigh ? 0 : 1;
		case ToolKind::Xnor:
			return parity ? 0 : 1;
		case ToolKind::Latch:
			return inputs.empty() ? currentState : firstInput();
		case ToolKind::Led:
			return firstInput();
		default:
			return currentState;
	}
}

void SimulationCore::resolveConnectorNetworks(const std::vector<uint8_t> &componentStates, std::vector<uint8_t> &networkStates) const {
	networkStates.assign(networkStates_.size(), 0);
	for (int32_t pass = 0; pass <= static_cast<int32_t>(readBindings_.size()); ++pass) {
		bool changed = false;
		for (const ReadBinding &binding : readBindings_) {
			uint8_t sourceState = 0;
			if (binding.sourceComponent >= 0) {
				sourceState = componentStates[binding.sourceComponent];
			} else if (binding.sourceNetwork >= 0) {
				sourceState = networkStates[binding.sourceNetwork];
			}
			if (sourceState == 0) {
				continue;
			}
			for (int32_t network : binding.outputNetworks) {
				if (networkStates[network] == 0) {
					networkStates[network] = 1;
					changed = true;
				}
			}
			if (networkStates[binding.signalNetwork] == 0) {
				networkStates[binding.signalNetwork] = 1;
				changed = true;
			}
		}
		if (!changed) {
			return;
		}
	}
}

void SimulationCore::resetInternal() {
	tickCount_ = 0;
	std::fill(networkStates_.begin(), networkStates_.end(), 0);
	std::fill(clockPhases_.begin(), clockPhases_.end(), 0);
	for (int32_t component = 0; component < static_cast<int32_t>(components_.size()); ++component) {
		const Component &definition = components_[component];
		if (definition.kind == ToolKind::Latch) {
			componentStates_[component] = definition.latchInitialState;
		} else if (definition.kind == ToolKind::Clock) {
			componentStates_[component] = 0;
		} else {
			componentStates_[component] = evaluateComponent(component, networkStates_, 0);
		}
	}
	resolveConnectorNetworks(componentStates_, networkStates_);
}

std::vector<int32_t> SimulationCore::getStates() const {
	if (!compiled_) {
		return {};
	}
	std::vector<int32_t> states(kinds_.size(), 0);
	for (int32_t cell = 0; cell < static_cast<int32_t>(kinds_.size()); ++cell) {
		const ToolKind kind = static_cast<ToolKind>(kinds_[cell]);
		if (isConductor(kind)) {
			states[cell] = cellNetwork_[cell] >= 0 ? networkStates_[cellNetwork_[cell]] : 0;
		} else if (kind == ToolKind::Mesh) {
			states[cell] = meshNetworkByCell_[cell] >= 0 ? networkStates_[meshNetworkByCell_[cell]] : 0;
		} else if (kind == ToolKind::Cross) {
			const bool horizontal = crossHorizontalNetworkByCell_[cell] >= 0 && networkStates_[crossHorizontalNetworkByCell_[cell]] != 0;
			const bool vertical = crossVerticalNetworkByCell_[cell] >= 0 && networkStates_[crossVerticalNetworkByCell_[cell]] != 0;
			states[cell] = horizontal || vertical ? 1 : 0;
		} else if (kind == ToolKind::Read) {
			const int32_t bindingId = readBindingByCell_[cell];
			if (bindingId >= 0) {
				const ReadBinding &binding = readBindings_[bindingId];
				if (binding.sourceComponent >= 0) {
					states[cell] = componentStates_[binding.sourceComponent];
				} else if (binding.sourceNetwork >= 0) {
					states[cell] = networkStates_[binding.sourceNetwork];
				}
			}
		} else if (kind == ToolKind::Write) {
			states[cell] = writeNetworkByCell_[cell] >= 0 ? networkStates_[writeNetworkByCell_[cell]] : 0;
		} else if (isDevice(kind)) {
			states[cell] = cellToComponent_[cell] >= 0 ? componentStates_[cellToComponent_[cell]] : 0;
		}
	}
	return states;
}

std::vector<int32_t> SimulationCore::makeStateDeltas(const std::vector<int32_t> &previousStates) const {
	const std::vector<int32_t> currentStates = getStates();
	std::vector<int32_t> deltas;
	for (int32_t cell = 0; cell < static_cast<int32_t>(currentStates.size()); ++cell) {
		if (cell >= static_cast<int32_t>(previousStates.size()) || previousStates[cell] != currentStates[cell]) {
			deltas.push_back(cell);
			deltas.push_back(currentStates[cell]);
		}
	}
	return deltas;
}

bool SimulationCore::toggleLatch(int32_t cellIndex, std::vector<int32_t> &changes, std::string &errorReason) {
	changes.clear();
	errorReason.clear();
	if (!compiled_) {
		errorReason = "simulation_not_compiled";
		return false;
	}
	if (cellIndex < 0 || cellIndex >= static_cast<int32_t>(kinds_.size())) {
		errorReason = "cell_out_of_bounds";
		return false;
	}
	const int32_t componentId = cellToComponent_[cellIndex];
	if (componentId < 0 || components_[componentId].kind != ToolKind::Latch) {
		errorReason = "not_latch";
		return false;
	}

	const std::vector<int32_t> previousStates = getStates();
	componentStates_[componentId] = componentStates_[componentId] == 0 ? 1 : 0;
	resolveConnectorNetworks(componentStates_, networkStates_);
	changes = makeStateDeltas(previousStates);
	return true;
}

void SimulationCore::advanceState() {
	nextComponentStates_ = componentStates_;
	nextClockPhases_ = clockPhases_;
	for (int32_t component = 0; component < static_cast<int32_t>(components_.size()); ++component) {
		const Component &definition = components_[component];
		if (definition.kind == ToolKind::Clock) {
			int32_t phase = clockPhases_[component] + 1;
			if (phase >= definition.clockHoldTicks) {
				phase = 0;
				nextComponentStates_[component] = componentStates_[component] == 0 ? 1 : 0;
			}
			nextClockPhases_[component] = phase;
		} else {
			nextComponentStates_[component] = evaluateComponent(component, networkStates_, componentStates_[component]);
		}
	}

	resolveConnectorNetworks(nextComponentStates_, nextNetworkStates_);

	componentStates_.swap(nextComponentStates_);
	networkStates_.swap(nextNetworkStates_);
	clockPhases_.swap(nextClockPhases_);
	++tickCount_;
}

std::vector<int32_t> SimulationCore::advanceTick() {
	return advanceTicks(1);
}

std::vector<int32_t> SimulationCore::advanceTicks(int32_t tickCount) {
	if (!compiled_ || tickCount <= 0) {
		return {};
	}
	const std::vector<int32_t> previousStates = getStates();
	for (int32_t tick = 0; tick < tickCount; ++tick) {
		advanceState();
	}
	return makeStateDeltas(previousStates);
}

std::vector<int32_t> SimulationCore::reset() {
	if (!compiled_) {
		return {};
	}
	const std::vector<int32_t> previousStates = getStates();
	resetInternal();
	return makeStateDeltas(previousStates);
}

uint64_t SimulationCore::makeTopologySignature() const {
	uint64_t hash = FnvOffsetBasis;
	hashInt(hash, width_);
	hashInt(hash, height_);
	for (int32_t cell = 0; cell < static_cast<int32_t>(kinds_.size()); ++cell) {
		hashInt(hash, kinds_[cell]);
		hashInt(hash, initialStates_[cell]);
		hashInt(hash, clockHoldTicks_[cell]);
		hashInt(hash, meshIds_[cell]);
	}
	return hash;
}

std::vector<uint8_t> SimulationCore::captureState() const {
	if (!compiled_) {
		return {};
	}
	std::vector<uint8_t> snapshot;
	snapshot.reserve(32 + componentStates_.size() * 5 + networkStates_.size());
	appendU32(snapshot, SnapshotMagic);
	appendU32(snapshot, SnapshotVersion);
	appendU64(snapshot, topologySignature_);
	appendU32(snapshot, static_cast<uint32_t>(componentStates_.size()));
	appendU32(snapshot, static_cast<uint32_t>(networkStates_.size()));
	appendU64(snapshot, tickCount_);
	snapshot.insert(snapshot.end(), componentStates_.begin(), componentStates_.end());
	snapshot.insert(snapshot.end(), networkStates_.begin(), networkStates_.end());
	for (int32_t phase : clockPhases_) {
		appendU32(snapshot, static_cast<uint32_t>(phase));
	}
	return snapshot;
}

bool SimulationCore::restoreState(const std::vector<uint8_t> &snapshot, std::string &errorReason) {
	errorReason.clear();
	if (!compiled_) {
		errorReason = "simulation_not_compiled";
		return false;
	}
	size_t offset = 0;
	uint32_t magic = 0;
	uint32_t version = 0;
	uint64_t signature = 0;
	uint32_t componentCount = 0;
	uint32_t networkCount = 0;
	uint64_t tickCount = 0;
	if (!readU32(snapshot, offset, magic) || !readU32(snapshot, offset, version) || !readU64(snapshot, offset, signature) ||
			!readU32(snapshot, offset, componentCount) || !readU32(snapshot, offset, networkCount) || !readU64(snapshot, offset, tickCount)) {
		errorReason = "invalid_snapshot";
		return false;
	}
	if (magic != SnapshotMagic || version != SnapshotVersion) {
		errorReason = "unsupported_snapshot";
		return false;
	}
	if (signature != topologySignature_ || componentCount != componentStates_.size() || networkCount != networkStates_.size()) {
		errorReason = "snapshot_topology_mismatch";
		return false;
	}
	const size_t expectedTail = static_cast<size_t>(componentCount) + static_cast<size_t>(networkCount) + static_cast<size_t>(componentCount) * 4U;
	if (offset > snapshot.size() || snapshot.size() - offset != expectedTail) {
		errorReason = "invalid_snapshot";
		return false;
	}
	std::vector<uint8_t> componentStates(componentCount);
	std::vector<uint8_t> networkStates(networkCount);
	for (uint32_t component = 0; component < componentCount; ++component) {
		componentStates[component] = snapshot[offset++];
		if (componentStates[component] > 1) {
			errorReason = "invalid_snapshot_state";
			return false;
		}
	}
	for (uint32_t network = 0; network < networkCount; ++network) {
		networkStates[network] = snapshot[offset++];
		if (networkStates[network] > 1) {
			errorReason = "invalid_snapshot_state";
			return false;
		}
	}
	std::vector<int32_t> clockPhases(componentCount, 0);
	for (uint32_t component = 0; component < componentCount; ++component) {
		uint32_t phase = 0;
		if (!readU32(snapshot, offset, phase)) {
			errorReason = "invalid_snapshot";
			return false;
		}
		if (phase > static_cast<uint32_t>(std::numeric_limits<int32_t>::max())) {
			errorReason = "invalid_snapshot_state";
			return false;
		}
		if (components_[component].kind == ToolKind::Clock && phase >= static_cast<uint32_t>(components_[component].clockHoldTicks)) {
			errorReason = "invalid_snapshot_state";
			return false;
		}
		clockPhases[component] = static_cast<int32_t>(phase);
	}
	componentStates_ = std::move(componentStates);
	networkStates_ = std::move(networkStates);
	clockPhases_ = std::move(clockPhases);
	tickCount_ = tickCount;
	return true;
}

bool SimulationCore::isCompiled() const {
	return compiled_;
}

} // namespace ocb
