#include "SimulationCore.hpp"

#include "GraphLocalityOrderer.hpp"

#include <algorithm>
#include <array>
#include <cassert>
#include <limits>
#include <numeric>
#include <unordered_map>

namespace ocb {
namespace {

constexpr uint32_t SnapshotMagic = 0x4f434253;
constexpr uint32_t SnapshotVersion = 2;
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

GraphLocalityOrder makeTypeStableOrder(const GraphLocalityOrder &gorderOrder, int32_t componentCount) {
	GraphLocalityOrder result;
	result.newToOld.reserve(gorderOrder.newToOld.size());
	result.oldToNew.resize(gorderOrder.oldToNew.size(), -1);
	for (int32_t oldNode : gorderOrder.newToOld) {
		if (oldNode < componentCount) {
			result.oldToNew[oldNode] = static_cast<int32_t>(result.newToOld.size());
			result.newToOld.push_back(oldNode);
		}
	}
	for (int32_t oldNode : gorderOrder.newToOld) {
		if (oldNode >= componentCount) {
			result.oldToNew[oldNode] = static_cast<int32_t>(result.newToOld.size());
			result.newToOld.push_back(oldNode);
		}
	}
	return result;
}

void hashInt(uint64_t &hash, int32_t value) {
	const uint32_t unsignedValue = static_cast<uint32_t>(value);
	for (int32_t shift = 0; shift < 32; shift += 8) {
		hash ^= (unsignedValue >> shift) & 0xffU;
		hash *= FnvPrime;
	}
}

struct ConnectorCondensation {
	std::vector<int32_t> rawToComponent;
	int32_t componentCount = 0;
};

ConnectorCondensation condenseConnectorGraph(int32_t connectorCount, const std::vector<std::pair<int32_t, int32_t>> &edges) {
	ConnectorCondensation result;
	result.rawToComponent.assign(connectorCount, -1);
	if (connectorCount == 0) {
		return result;
	}

	std::vector<std::vector<int32_t>> outgoing(connectorCount);
	std::vector<std::vector<int32_t>> incoming(connectorCount);
	for (const std::pair<int32_t, int32_t> &edge : edges) {
		if (edge.first < 0 || edge.second < 0 || edge.first >= connectorCount || edge.second >= connectorCount) {
			continue;
		}
		outgoing[edge.first].push_back(edge.second);
		incoming[edge.second].push_back(edge.first);
	}
	for (int32_t node = 0; node < connectorCount; ++node) {
		std::sort(outgoing[node].begin(), outgoing[node].end());
		outgoing[node].erase(std::unique(outgoing[node].begin(), outgoing[node].end()), outgoing[node].end());
		std::sort(incoming[node].begin(), incoming[node].end());
		incoming[node].erase(std::unique(incoming[node].begin(), incoming[node].end()), incoming[node].end());
	}

	std::vector<uint8_t> visited(connectorCount, 0);
	std::vector<int32_t> finishOrder;
	finishOrder.reserve(connectorCount);
	for (int32_t start = 0; start < connectorCount; ++start) {
		if (visited[start] != 0) {
			continue;
		}
		std::vector<std::pair<int32_t, int32_t>> stack;
		stack.emplace_back(start, 0);
		visited[start] = 1;
		while (!stack.empty()) {
			int32_t &nextEdge = stack.back().second;
			const int32_t node = stack.back().first;
			if (nextEdge < static_cast<int32_t>(outgoing[node].size())) {
				const int32_t target = outgoing[node][nextEdge++];
				if (visited[target] == 0) {
					visited[target] = 1;
					stack.emplace_back(target, 0);
				}
				continue;
			}
			finishOrder.push_back(node);
			stack.pop_back();
		}
	}

	std::vector<int32_t> componentMinimum;
	for (auto iterator = finishOrder.rbegin(); iterator != finishOrder.rend(); ++iterator) {
		const int32_t start = *iterator;
		if (result.rawToComponent[start] >= 0) {
			continue;
		}
		const int32_t component = result.componentCount++;
		int32_t minimumNode = start;
		std::vector<int32_t> stack = {start};
		result.rawToComponent[start] = component;
		while (!stack.empty()) {
			const int32_t node = stack.back();
			stack.pop_back();
			minimumNode = std::min(minimumNode, node);
			for (int32_t source : incoming[node]) {
				if (result.rawToComponent[source] >= 0) {
					continue;
				}
				result.rawToComponent[source] = component;
				stack.push_back(source);
			}
		}
		componentMinimum.push_back(minimumNode);
	}

	std::vector<int32_t> orderedComponents(result.componentCount);
	std::iota(orderedComponents.begin(), orderedComponents.end(), 0);
	std::sort(orderedComponents.begin(), orderedComponents.end(), [&](int32_t left, int32_t right) {
		return componentMinimum[left] < componentMinimum[right];
	});
	std::vector<int32_t> remap(result.componentCount, -1);
	for (int32_t component = 0; component < result.componentCount; ++component) {
		remap[orderedComponents[component]] = component;
	}
	for (int32_t &component : result.rawToComponent) {
		component = remap[component];
	}
	return result;
}

void appendCsrEdge(std::vector<std::vector<int32_t>> &outgoing, int32_t source, int32_t target) {
	if (source < 0 || target < 0 || source >= static_cast<int32_t>(outgoing.size()) || target >= static_cast<int32_t>(outgoing.size()) || source == target) {
		return;
	}
	outgoing[source].push_back(target);
}

void flattenCsr(
		const std::vector<std::vector<int32_t>> &adjacency,
		std::vector<int32_t> &offsets,
		std::vector<int32_t> &targets) {
	offsets.assign(adjacency.size() + 1U, 0);
	targets.clear();
	for (int32_t node = 0; node < static_cast<int32_t>(adjacency.size()); ++node) {
		offsets[node] = static_cast<int32_t>(targets.size());
		targets.insert(targets.end(), adjacency[node].begin(), adjacency[node].end());
	}
	offsets[adjacency.size()] = static_cast<int32_t>(targets.size());
}

} // namespace

bool SimulationCore::isKnownKind(int32_t kind) {
	return kind >= static_cast<int32_t>(ToolKind::Empty) && kind <= static_cast<int32_t>(ToolKind::Led);
}

SimulationCore::SimulationCore(bool useGraphLocalityOrdering) : useGraphLocalityOrdering_(useGraphLocalityOrdering) {
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
	graphLocalityOrderingApplied_ = false;
	topologySignature_ = 0;
	tickCount_ = 0;
	graphLocalityScore_ = 0;
	kinds_.clear();
	initialStates_.clear();
	clockHoldTicks_.clear();
	meshIds_.clear();
	components_.clear();
	readBindings_.clear();
	writeBindings_.clear();
	cellToComponent_.clear();
	cellNetwork_.clear();
	meshNetworksByCell_.clear();
	crossNetworksByCell_.clear();
	readBindingByCell_.clear();
	writeBindingByCell_.clear();
	nodeStates_.clear();
	networkStates_.clear();
	clockPhases_.clear();
	nodeIsComponent_.clear();
	nodeKinds_.clear();
	nodeClockHoldTicks_.clear();
	nodeLatchInitialStates_.clear();
	nodeEvaluationPolicies_.clear();
	nodeInputCounts_.clear();
	nodeInputHighCounts_.clear();
	outgoingOffsets_.clear();
	outgoingComponentEnds_.clear();
	outgoingTargets_.clear();
	incomingOffsets_.clear();
	incomingSources_.clear();
	componentNodes_.clear();
	connectorNodes_.clear();
	connectorTopologicalRanks_.clear();
	snapshotComponentNodes_.clear();
	snapshotConnectorNodes_.clear();
	clockNodes_.clear();
	nextGateWords_.clear();
	nextGateSummaryWords_.clear();
	currentGateWords_.clear();
	currentGateSummaryWords_.clear();
	nextGateActiveSummaryWordCount_ = 0;
	currentGateActiveSummaryWordCount_ = 0;
	nextGateStates_.clear();
	currentGateStates_.clear();
	connectorQueueEvents_.clear();
	pendingComponentInputDeltas_.clear();
	pendingComponentRisingCounts_.clear();
	componentInputStamps_.clear();
	for (std::vector<int32_t> &pendingInputs : pendingComponentInputsByMode_) {
		pendingInputs.clear();
	}
	pendingConnectorDeltas_.clear();
	connectorDeltaStamps_.clear();
	connectorWorkWords_.clear();
	connectorWorkWordStamps_.clear();
	connectorActiveWordHierarchy_.clear();
	connectorActiveWordLevelOffsets_.clear();
	propagationStamp_ = 1;
	suppressLatchInputEdges_ = false;
	visibleCellOffsets_.clear();
	visibleCellIndices_.clear();
	cellVisibleNodeOffsets_.clear();
	cellVisibleNodes_.clear();
	nodeHasVisibleCells_.clear();
	dirtyNodeStamps_.clear();
	dirtyNodeInitialStates_.clear();
	dirtyNodes_.clear();
	dirtyNodeStamp_ = 1;
	materializedCellStamps_.clear();
	materializedCellStamp_ = 1;
	visibleStates_.clear();
	reportedVisibleStates_.clear();
	changedCellStamps_.clear();
	changedCells_.clear();
	changeStamp_ = 1;
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

	DisjointSet portSet(cellCount);
	for (int32_t cell = 0; cell < cellCount; ++cell) {
		const ToolKind kind = static_cast<ToolKind>(kinds_[cell]);
		if (kind != ToolKind::Read && kind != ToolKind::Write) {
			continue;
		}
		for (const std::array<int32_t, 2> direction : {std::array<int32_t, 2>{1, 0}, std::array<int32_t, 2>{0, 1}}) {
			const int32_t neighbor = neighborAt(cell, direction[0], direction[1]);
			if (neighbor >= 0 && static_cast<ToolKind>(kinds_[neighbor]) == kind) {
				portSet.unite(cell, neighbor);
			}
		}
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

	const auto makeColorChannels = []() {
		std::array<int32_t, SignalColorCount> channels;
		channels.fill(-1);
		return channels;
	};
	const auto makeCrossChannels = []() {
		std::array<int32_t, CrossChannelCount> channels;
		channels.fill(-1);
		return channels;
	};
	const auto colorIndex = [](int32_t color) {
		return static_cast<size_t>(color - 1);
	};

	std::vector<std::array<int32_t, CrossChannelCount>> crossAnchors(cellCount, makeCrossChannels());
	for (int32_t cell = 0; cell < cellCount; ++cell) {
		if (static_cast<ToolKind>(kinds_[cell]) != ToolKind::Cross) {
			continue;
		}
		for (size_t channel = 0; channel < CrossChannelCount; ++channel) {
			crossAnchors[cell][channel] = conductorSet.add();
		}
	}
	for (int32_t cell = 0; cell < cellCount; ++cell) {
		if (static_cast<ToolKind>(kinds_[cell]) != ToolKind::Cross) {
			continue;
		}
		for (size_t orientation = 0; orientation < 2U; ++orientation) {
			const std::array<std::array<int32_t, 2>, 2> channelDirections = orientation == 0U ?
					std::array<std::array<int32_t, 2>, 2>{{{{-1, 0}}, {{1, 0}}}} :
					std::array<std::array<int32_t, 2>, 2>{{{{0, -1}}, {{0, 1}}}};
			for (int32_t color = 1; color <= static_cast<int32_t>(SignalColorCount); ++color) {
				const size_t channel = orientation * SignalColorCount + colorIndex(color);
				const int32_t anchor = crossAnchors[cell][channel];
				for (const std::array<int32_t, 2> &direction : channelDirections) {
					const int32_t neighbor = neighborAt(cell, direction[0], direction[1]);
					if (neighbor < 0) {
						continue;
					}
					const ToolKind neighborKind = static_cast<ToolKind>(kinds_[neighbor]);
					if (isConductor(neighborKind) && colorForKind(neighborKind) == color) {
						conductorSet.unite(anchor, neighbor);
					} else if (neighborKind == ToolKind::Cross) {
						conductorSet.unite(anchor, crossAnchors[neighbor][channel]);
					}
				}
			}
		}
	}

	std::vector<std::array<int32_t, SignalColorCount>> meshAnchorsByCell(cellCount, makeColorChannels());
	std::unordered_map<uint64_t, int32_t> meshAnchors;
	for (int32_t cell = 0; cell < cellCount; ++cell) {
		if (static_cast<ToolKind>(kinds_[cell]) != ToolKind::Mesh) {
			continue;
		}
		for (const std::array<int32_t, 2> &direction : directions) {
			const int32_t neighbor = neighborAt(cell, direction[0], direction[1]);
			if (neighbor < 0 || !isTrace(static_cast<ToolKind>(kinds_[neighbor]))) {
				continue;
			}
			const int32_t color = colorForKind(static_cast<ToolKind>(kinds_[neighbor]));
			const uint64_t key =
					(static_cast<uint64_t>(static_cast<uint32_t>(meshIds_[cell])) << 8U) | static_cast<uint64_t>(color);
			auto found = meshAnchors.find(key);
			int32_t anchor = -1;
			if (found == meshAnchors.end()) {
				anchor = conductorSet.add();
				meshAnchors.emplace(key, anchor);
			} else {
				anchor = found->second;
			}
			meshAnchorsByCell[cell][colorIndex(color)] = anchor;
			conductorSet.unite(anchor, neighbor);
		}
	}

	cellNetwork_.assign(cellCount, -1);
	meshNetworksByCell_.assign(cellCount, makeColorChannels());
	crossNetworksByCell_.assign(cellCount, makeCrossChannels());
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
		for (size_t color = 0; color < SignalColorCount; ++color) {
			if (meshAnchorsByCell[cell][color] >= 0) {
				meshNetworksByCell_[cell][color] = getNetwork(meshAnchorsByCell[cell][color]);
			}
		}
		for (size_t channel = 0; channel < CrossChannelCount; ++channel) {
			if (crossAnchors[cell][channel] >= 0) {
				crossNetworksByCell_[cell][channel] = getNetwork(crossAnchors[cell][channel]);
			}
		}
	}
	networkStates_.assign(networkByRoot.size(), 0);

	readBindingByCell_.assign(cellCount, -1);
	writeBindingByCell_.assign(cellCount, -1);
	std::unordered_map<int32_t, int32_t> readBindingByRoot;
	std::unordered_map<int32_t, int32_t> writeBindingByRoot;
	for (int32_t cell = 0; cell < cellCount; ++cell) {
		const ToolKind kind = static_cast<ToolKind>(kinds_[cell]);
		if (kind != ToolKind::Read && kind != ToolKind::Write) {
			continue;
		}
		const int32_t root = portSet.find(cell);
		if (kind == ToolKind::Read) {
			auto found = readBindingByRoot.find(root);
			int32_t bindingId = -1;
			if (found == readBindingByRoot.end()) {
				bindingId = static_cast<int32_t>(readBindings_.size());
				readBindingByRoot.emplace(root, bindingId);
				readBindings_.push_back(ReadBinding());
			} else {
				bindingId = found->second;
			}
			readBindings_[bindingId].cells.push_back(cell);
			readBindingByCell_[cell] = bindingId;
			continue;
		}
		auto found = writeBindingByRoot.find(root);
		int32_t bindingId = -1;
		if (found == writeBindingByRoot.end()) {
			bindingId = static_cast<int32_t>(writeBindings_.size());
			writeBindingByRoot.emplace(root, bindingId);
			writeBindings_.push_back(WriteBinding());
		} else {
			bindingId = found->second;
		}
		writeBindings_[bindingId].cells.push_back(cell);
		writeBindingByCell_[cell] = bindingId;
	}

	for (int32_t cell = 0; cell < cellCount; ++cell) {
		const ToolKind kind = static_cast<ToolKind>(kinds_[cell]);
		if (kind != ToolKind::Read && kind != ToolKind::Write) {
			continue;
		}
		for (const std::array<int32_t, 2> &direction : directions) {
			const int32_t neighbor = neighborAt(cell, direction[0], direction[1]);
			if (neighbor < 0) {
				continue;
			}
			const ToolKind neighborKind = static_cast<ToolKind>(kinds_[neighbor]);
			if (kind == ToolKind::Read) {
				ReadBinding &binding = readBindings_[readBindingByCell_[cell]];
				if (isTrace(neighborKind)) {
					appendUnique(binding.outputNetworks, cellNetwork_[neighbor]);
				} else if (neighborKind == ToolKind::Write) {
					appendUnique(binding.adjacentWriteBindings, writeBindingByCell_[neighbor]);
				} else if (isReadSource(neighborKind)) {
					appendUnique(binding.sourceComponents, cellToComponent_[neighbor]);
				}
				continue;
			}
			WriteBinding &binding = writeBindings_[writeBindingByCell_[cell]];
			if (isTrace(neighborKind)) {
				appendUnique(binding.inputNetworks, cellNetwork_[neighbor]);
			} else if (neighborKind == ToolKind::Read) {
				appendUnique(binding.adjacentReadBindings, readBindingByCell_[neighbor]);
			} else if (isWriteTarget(neighborKind)) {
				appendUnique(binding.targetComponents, cellToComponent_[neighbor]);
			}
		}
	}

	std::vector<uint8_t> readHasInput(readBindings_.size(), 0);
	std::vector<uint8_t> writeHasInput(writeBindings_.size(), 0);
	for (int32_t bindingId = 0; bindingId < static_cast<int32_t>(readBindings_.size()); ++bindingId) {
		readHasInput[bindingId] = !readBindings_[bindingId].sourceComponents.empty() ? 1 : 0;
	}
	for (int32_t bindingId = 0; bindingId < static_cast<int32_t>(writeBindings_.size()); ++bindingId) {
		writeHasInput[bindingId] = !writeBindings_[bindingId].inputNetworks.empty() ? 1 : 0;
	}
	bool changed = true;
	while (changed) {
		changed = false;
		for (int32_t bindingId = 0; bindingId < static_cast<int32_t>(readBindings_.size()); ++bindingId) {
			for (int32_t writeBinding : readBindings_[bindingId].adjacentWriteBindings) {
				if (readHasInput[bindingId] != 0 && writeHasInput[writeBinding] == 0) {
					writeHasInput[writeBinding] = 1;
					changed = true;
				}
				if (writeHasInput[writeBinding] != 0 && readHasInput[bindingId] == 0) {
					readHasInput[bindingId] = 1;
					changed = true;
				}
			}
		}
	}
	for (const ReadBinding &binding : readBindings_) {
		if (binding.sourceComponents.empty() && binding.adjacentWriteBindings.empty()) {
			return fail(binding.cells.front(), "read_requires_one_source");
		}
		if (binding.outputNetworks.empty() && binding.adjacentWriteBindings.empty()) {
			return fail(binding.cells.front(), "read_requires_output");
		}
	}
	for (const WriteBinding &binding : writeBindings_) {
		if (binding.inputNetworks.empty() && binding.adjacentReadBindings.empty()) {
			return fail(binding.cells.front(), "write_requires_one_input");
		}
		if (binding.targetComponents.empty() && binding.adjacentReadBindings.empty()) {
			return fail(binding.cells.front(), "write_requires_target");
		}
	}
	for (int32_t bindingId = 0; bindingId < static_cast<int32_t>(readBindings_.size()); ++bindingId) {
		if (readHasInput[bindingId] == 0) {
			return fail(readBindings_[bindingId].cells.front(), "read_requires_one_source");
		}
	}
	for (int32_t bindingId = 0; bindingId < static_cast<int32_t>(writeBindings_.size()); ++bindingId) {
		if (writeHasInput[bindingId] == 0) {
			return fail(writeBindings_[bindingId].cells.front(), "write_requires_one_input");
		}
	}
	for (ReadBinding &binding : readBindings_) {
		binding.signalNetwork = static_cast<int32_t>(networkStates_.size());
		networkStates_.push_back(0);
	}
	for (WriteBinding &binding : writeBindings_) {
		binding.signalNetwork = static_cast<int32_t>(networkStates_.size());
		networkStates_.push_back(0);
	}

	buildExecutionGraph();
	topologySignature_ = makeTopologySignature();
	resetInternal();
	materializeVisibleStates();
	reportedVisibleStates_ = visibleStates_;
	resetChangeCollector();
	compiled_ = true;
	return true;
}

void SimulationCore::buildExecutionGraph() {
	const int32_t originalComponentCount = static_cast<int32_t>(components_.size());
	const int32_t rawConnectorCount = static_cast<int32_t>(networkStates_.size());
	std::vector<std::pair<int32_t, int32_t>> rawEdges;
	const auto addRawEdge = [&](int32_t source, int32_t target) {
		if (source >= 0 && target >= 0) {
			rawEdges.emplace_back(source, target);
		}
	};
	// Directly adjacent Read and Write bindings are one logical port, condensed as one connector signal.
	for (const ReadBinding &binding : readBindings_) {
		for (int32_t source : binding.sourceComponents) {
			addRawEdge(source, originalComponentCount + binding.signalNetwork);
		}
		for (int32_t target : binding.outputNetworks) {
			addRawEdge(originalComponentCount + binding.signalNetwork, originalComponentCount + target);
		}
		for (int32_t writeBinding : binding.adjacentWriteBindings) {
			addRawEdge(
					originalComponentCount + binding.signalNetwork,
					originalComponentCount + writeBindings_[writeBinding].signalNetwork);
		}
	}
	for (const WriteBinding &binding : writeBindings_) {
		for (int32_t source : binding.inputNetworks) {
			addRawEdge(originalComponentCount + source, originalComponentCount + binding.signalNetwork);
		}
		for (int32_t readBinding : binding.adjacentReadBindings) {
			addRawEdge(
					originalComponentCount + binding.signalNetwork,
					originalComponentCount + readBindings_[readBinding].signalNetwork);
		}
		for (int32_t target : binding.targetComponents) {
			addRawEdge(originalComponentCount + binding.signalNetwork, target);
		}
	}
	std::sort(rawEdges.begin(), rawEdges.end());
	rawEdges.erase(std::unique(rawEdges.begin(), rawEdges.end()), rawEdges.end());

	std::vector<std::pair<int32_t, int32_t>> connectorEdges;
	for (const std::pair<int32_t, int32_t> &edge : rawEdges) {
		if (edge.first >= originalComponentCount && edge.second >= originalComponentCount) {
			connectorEdges.emplace_back(edge.first - originalComponentCount, edge.second - originalComponentCount);
		}
	}
	const ConnectorCondensation condensation = condenseConnectorGraph(rawConnectorCount, connectorEdges);
	const int32_t originalNodeCount = originalComponentCount + condensation.componentCount;
	std::vector<std::vector<int32_t>> originalOutgoing(originalNodeCount);
	const auto mapRawNode = [&](int32_t rawNode) {
		if (rawNode < originalComponentCount) {
			return rawNode;
		}
		const int32_t rawConnector = rawNode - originalComponentCount;
		return originalComponentCount + condensation.rawToComponent[rawConnector];
	};
	for (const std::pair<int32_t, int32_t> &edge : rawEdges) {
		appendCsrEdge(originalOutgoing, mapRawNode(edge.first), mapRawNode(edge.second));
	}
	for (std::vector<int32_t> &targets : originalOutgoing) {
		std::sort(targets.begin(), targets.end());
		targets.erase(std::unique(targets.begin(), targets.end()), targets.end());
	}
	std::vector<std::vector<int32_t>> originalIncoming(originalNodeCount);
	const auto rebuildOriginalIncoming = [&]() {
		for (std::vector<int32_t> &sources : originalIncoming) {
			sources.clear();
		}
		for (int32_t source = 0; source < originalNodeCount; ++source) {
			for (int32_t target : originalOutgoing[source]) {
				originalIncoming[target].push_back(source);
			}
		}
	};
	rebuildOriginalIncoming();
	std::vector<int32_t> originalNodeAliases(originalNodeCount);
	std::iota(originalNodeAliases.begin(), originalNodeAliases.end(), 0);
	for (int32_t node = originalComponentCount; node < originalNodeCount; ++node) {
		if (!originalOutgoing[node].empty() || originalIncoming[node].size() != 1U) {
			continue;
		}
		const int32_t source = originalIncoming[node].front();
		originalNodeAliases[node] = source;
		std::vector<int32_t> &sourceTargets = originalOutgoing[source];
		sourceTargets.erase(std::remove(sourceTargets.begin(), sourceTargets.end(), node), sourceTargets.end());
	}
	rebuildOriginalIncoming();
	std::vector<int32_t> transparentConnectorCandidates;
	transparentConnectorCandidates.reserve(static_cast<size_t>(originalNodeCount - originalComponentCount));
	for (int32_t node = originalComponentCount; node < originalNodeCount; ++node) {
		if (originalOutgoing[node].size() == 1U && originalIncoming[node].size() == 1U) {
			transparentConnectorCandidates.push_back(node);
		}
	}
	for (size_t cursor = 0; cursor < transparentConnectorCandidates.size(); ++cursor) {
		const int32_t node = transparentConnectorCandidates[cursor];
		if (originalOutgoing[node].size() != 1U || originalIncoming[node].size() != 1U) {
			continue;
		}
		const int32_t source = originalIncoming[node].front();
		const int32_t target = originalOutgoing[node].front();
		if (source == target) {
			continue;
		}
		std::vector<int32_t> &sourceTargets = originalOutgoing[source];
		if (std::binary_search(sourceTargets.begin(), sourceTargets.end(), target)) {
			// A direct edge is a distinct logical input, so retaining this connector preserves T and edge counts.
			continue;
		}

		originalNodeAliases[node] = source;
		sourceTargets.erase(std::remove(sourceTargets.begin(), sourceTargets.end(), node), sourceTargets.end());
		sourceTargets.push_back(target);
		std::sort(sourceTargets.begin(), sourceTargets.end());
		originalOutgoing[node].clear();
		originalIncoming[node].clear();
		std::vector<int32_t> &targetSources = originalIncoming[target];
		targetSources.erase(std::remove(targetSources.begin(), targetSources.end(), node), targetSources.end());
		targetSources.push_back(source);
		std::sort(targetSources.begin(), targetSources.end());
		if (source >= originalComponentCount) {
			transparentConnectorCandidates.push_back(source);
		}
		if (target >= originalComponentCount) {
			transparentConnectorCandidates.push_back(target);
		}
	}
	rebuildOriginalIncoming();
	std::vector<int32_t> originalOutgoingOffsets;
	std::vector<int32_t> originalOutgoingTargets;
	flattenCsr(originalOutgoing, originalOutgoingOffsets, originalOutgoingTargets);
	std::vector<int32_t> originalIncomingOffsets;
	std::vector<int32_t> originalIncomingSources;
	flattenCsr(originalIncoming, originalIncomingOffsets, originalIncomingSources);
	GraphLocalityOrder order;
	order.newToOld.resize(originalNodeCount);
	order.oldToNew.resize(originalNodeCount);
	std::iota(order.newToOld.begin(), order.newToOld.end(), 0);
	std::iota(order.oldToNew.begin(), order.oldToNew.end(), 0);
	if (useGraphLocalityOrdering_) {
		const GraphLocalityOrder gorderOrder = GraphLocalityOrderer::order(
				originalNodeCount,
				originalOutgoingOffsets,
				originalOutgoingTargets,
				originalIncomingOffsets,
				originalIncomingSources);
		GraphLocalityOrder candidateOrder = makeTypeStableOrder(gorderOrder, originalComponentCount);
		const int64_t identityScore = GraphLocalityOrderer::calculateLocalityScore(
				originalNodeCount, originalOutgoingOffsets, originalOutgoingTargets, order.oldToNew);
		const int64_t candidateScore = GraphLocalityOrderer::calculateLocalityScore(
				originalNodeCount, originalOutgoingOffsets, originalOutgoingTargets, candidateOrder.oldToNew);
		if (candidateScore > identityScore) {
			order = std::move(candidateOrder);
			graphLocalityOrderingApplied_ = true;
		}
	}
	graphLocalityScore_ = GraphLocalityOrderer::calculateLocalityScore(
			originalNodeCount,
			originalOutgoingOffsets,
			originalOutgoingTargets,
			order.oldToNew);

	std::vector<std::vector<int32_t>> reorderedOutgoing(originalNodeCount);
	for (int32_t source = 0; source < originalNodeCount; ++source) {
		const int32_t reorderedSource = order.oldToNew[source];
		for (int32_t target : originalOutgoing[source]) {
			reorderedOutgoing[reorderedSource].push_back(order.oldToNew[target]);
		}
	}
	for (std::vector<int32_t> &targets : reorderedOutgoing) {
		std::sort(targets.begin(), targets.end());
		targets.erase(std::unique(targets.begin(), targets.end()), targets.end());
	}
	flattenCsr(reorderedOutgoing, outgoingOffsets_, outgoingTargets_);
	// Type-stable ordering places component nodes before connector nodes.
	outgoingComponentEnds_.resize(originalNodeCount);
	for (int32_t node = 0; node < originalNodeCount; ++node) {
		int32_t edge = outgoingOffsets_[node];
		const int32_t edgeEnd = outgoingOffsets_[node + 1];
		while (edge < edgeEnd && outgoingTargets_[edge] < originalComponentCount) {
			++edge;
		}
		outgoingComponentEnds_[node] = edge;
	}
	std::vector<std::vector<int32_t>> reorderedIncoming(originalNodeCount);
	for (int32_t source = 0; source < originalNodeCount; ++source) {
		for (int32_t target : reorderedOutgoing[source]) {
			reorderedIncoming[target].push_back(source);
		}
	}
	for (std::vector<int32_t> &sources : reorderedIncoming) {
		std::sort(sources.begin(), sources.end());
	}
	flattenCsr(reorderedIncoming, incomingOffsets_, incomingSources_);

	std::vector<Component> originalComponents = std::move(components_);
	components_.assign(originalNodeCount, Component());
	nodeIsComponent_.assign(originalNodeCount, 0);
	nodeKinds_.assign(originalNodeCount, ToolKind::Empty);
	nodeClockHoldTicks_.assign(originalNodeCount, 0);
	nodeLatchInitialStates_.assign(originalNodeCount, 0);
	componentNodes_.clear();
	connectorNodes_.clear();
	clockNodes_.clear();
	snapshotComponentNodes_.resize(originalComponentCount);
	for (int32_t originalComponent = 0; originalComponent < originalComponentCount; ++originalComponent) {
		const int32_t node = order.oldToNew[originalComponent];
		components_[node] = std::move(originalComponents[originalComponent]);
		nodeIsComponent_[node] = 1;
		nodeKinds_[node] = components_[node].kind;
		nodeClockHoldTicks_[node] = components_[node].clockHoldTicks;
		nodeLatchInitialStates_[node] = components_[node].latchInitialState;
		snapshotComponentNodes_[originalComponent] = node;
	}
	for (int32_t node = 0; node < originalNodeCount; ++node) {
		if (nodeIsComponent_[node] == 0) {
			connectorNodes_.push_back(node);
			continue;
		}
		componentNodes_.push_back(node);
		if (nodeKinds_[node] == ToolKind::Clock) {
			clockNodes_.push_back(node);
		}
	}
	// Connector SCCs are condensed above, so their remaining zero-delay edges form a DAG.
	connectorTopologicalRanks_.assign(originalNodeCount, -1);
	std::vector<int32_t> connectorIncomingCounts(originalNodeCount, 0);
	for (int32_t source : connectorNodes_) {
		for (int32_t edge = outgoingComponentEnds_[source]; edge < outgoingOffsets_[source + 1]; ++edge) {
			++connectorIncomingCounts[outgoingTargets_[edge]];
		}
	}
	std::vector<int32_t> connectorTopologicalQueue;
	connectorTopologicalQueue.reserve(connectorNodes_.size());
	for (int32_t node : connectorNodes_) {
		if (connectorIncomingCounts[node] == 0) {
			connectorTopologicalQueue.push_back(node);
		}
	}
	for (size_t cursor = 0; cursor < connectorTopologicalQueue.size(); ++cursor) {
		const int32_t source = connectorTopologicalQueue[cursor];
		connectorTopologicalRanks_[source] = static_cast<int32_t>(cursor);
		for (int32_t edge = outgoingComponentEnds_[source]; edge < outgoingOffsets_[source + 1]; ++edge) {
			const int32_t target = outgoingTargets_[edge];
			if (--connectorIncomingCounts[target] == 0) {
				connectorTopologicalQueue.push_back(target);
			}
		}
	}
	assert(connectorTopologicalQueue.size() == connectorNodes_.size());
	connectorNodes_ = std::move(connectorTopologicalQueue);
#ifndef NDEBUG
	for (int32_t source : connectorNodes_) {
		for (int32_t edge = outgoingComponentEnds_[source]; edge < outgoingOffsets_[source + 1]; ++edge) {
			const int32_t target = outgoingTargets_[edge];
			assert(connectorTopologicalRanks_[source] < connectorTopologicalRanks_[target]);
		}
	}
#endif
	// Runtime propagation only needs the component edge boundary for non-singleton fanout.
	// Encode a sole component target as -(target + 1) to bypass CSR range setup on the hot path.
	for (int32_t source = 0; source < originalNodeCount; ++source) {
		const int32_t edgeBegin = outgoingOffsets_[source];
		const int32_t componentEdgeEnd = outgoingComponentEnds_[source];
		const int32_t edgeEnd = outgoingOffsets_[source + 1];
		if (componentEdgeEnd == edgeBegin + 1 && edgeEnd == componentEdgeEnd) {
			outgoingComponentEnds_[source] = -outgoingTargets_[edgeBegin] - 1;
		}
	}
	for (int32_t &component : cellToComponent_) {
		if (component >= 0) {
			component = order.oldToNew[component];
		}
	}
	const auto remapOriginalNode = [&](int32_t originalNode) {
		while (originalNodeAliases[originalNode] != originalNode) {
			originalNode = originalNodeAliases[originalNode];
		}
		return order.oldToNew[originalNode];
	};
	const auto remapConnector = [&](int32_t rawConnector) {
		if (rawConnector < 0) {
			return -1;
		}
		const int32_t originalNode = originalComponentCount + condensation.rawToComponent[rawConnector];
		return remapOriginalNode(originalNode);
	};
	snapshotConnectorNodes_.resize(rawConnectorCount);
	for (int32_t rawConnector = 0; rawConnector < rawConnectorCount; ++rawConnector) {
		snapshotConnectorNodes_[rawConnector] = remapConnector(rawConnector);
	}
	for (int32_t &network : cellNetwork_) {
		network = remapConnector(network);
	}
	for (std::array<int32_t, SignalColorCount> &channels : meshNetworksByCell_) {
		for (int32_t &network : channels) {
			network = remapConnector(network);
		}
	}
	for (std::array<int32_t, CrossChannelCount> &channels : crossNetworksByCell_) {
		for (int32_t &network : channels) {
			network = remapConnector(network);
		}
	}
	for (ReadBinding &binding : readBindings_) {
		binding.signalNetwork = remapConnector(binding.signalNetwork);
	}
	for (WriteBinding &binding : writeBindings_) {
		binding.signalNetwork = remapConnector(binding.signalNetwork);
	}

	nodeInputCounts_.assign(originalNodeCount, 0);
	nodeInputHighCounts_.assign(originalNodeCount, 0);
	for (int32_t componentIndex = 0; componentIndex < static_cast<int32_t>(componentNodes_.size()); ++componentIndex) {
		const int32_t node = componentNodes_[componentIndex];
		nodeInputCounts_[node] = incomingOffsets_[node + 1] - incomingOffsets_[node];
	}
	nodeEvaluationPolicies_.assign(originalComponentCount, static_cast<uint8_t>(EvaluationMode::State));
	for (int32_t node : componentNodes_) {
		const int32_t inputCount = nodeInputCounts_[node];
		EvaluationMode mode = EvaluationMode::State;
		switch (nodeKinds_[node]) {
			case ToolKind::Buffer:
			case ToolKind::Or:
			case ToolKind::Led:
				mode = EvaluationMode::High;
				break;
			case ToolKind::Not:
			case ToolKind::Nor:
				mode = EvaluationMode::Low;
				break;
			case ToolKind::And:
				mode = inputCount == 1 ? EvaluationMode::High : EvaluationMode::AllHigh;
				break;
			case ToolKind::Nand:
				mode = inputCount == 1 ? EvaluationMode::Low : EvaluationMode::NotAllHigh;
				break;
			case ToolKind::Xor:
				mode = inputCount == 1 ? EvaluationMode::High : EvaluationMode::OddParity;
				break;
			case ToolKind::Xnor:
				mode = inputCount == 1 ? EvaluationMode::Low : EvaluationMode::EvenParity;
				break;
			case ToolKind::Latch:
				mode = EvaluationMode::LatchToggle;
				break;
			default:
				break;
		}
		nodeEvaluationPolicies_[node] = static_cast<uint8_t>(mode);
	}
	const size_t gateWordCount = (componentNodes_.size() + 63U) / 64U;
	const size_t gateSummaryWordCount = (gateWordCount + 63U) / 64U;
	nextGateWords_.assign(gateWordCount, 0);
	nextGateSummaryWords_.assign(gateSummaryWordCount, 0);
	currentGateWords_.assign(gateWordCount, 0);
	currentGateSummaryWords_.assign(gateSummaryWordCount, 0);
	nextGateActiveSummaryWordCount_ = 0;
	currentGateActiveSummaryWordCount_ = 0;
	nextGateStates_.assign(originalComponentCount, 0);
	currentGateStates_.assign(originalComponentCount, 0);
	connectorQueueEvents_.clear();
	connectorQueueEvents_.reserve(originalNodeCount);
	pendingComponentInputDeltas_.assign(originalNodeCount, 0);
	pendingComponentRisingCounts_.assign(originalNodeCount, 0);
	componentInputStamps_.assign(originalNodeCount, 0);
	for (std::vector<int32_t> &pendingInputs : pendingComponentInputsByMode_) {
		pendingInputs.clear();
	}
	pendingConnectorDeltas_.assign(originalNodeCount, 0);
	connectorDeltaStamps_.assign(originalNodeCount, 0);
	const size_t connectorWorkWordCount = (connectorNodes_.size() + 63U) / 64U;
	connectorWorkWords_.assign(connectorWorkWordCount, 0);
	connectorWorkWordStamps_.assign(connectorWorkWordCount, 0);
	initializeConnectorWorkWordHierarchy(connectorWorkWordCount);
	propagationStamp_ = 1;
	nodeStates_.assign(originalNodeCount, 0);
	clockPhases_.assign(originalNodeCount, 0);
	std::vector<std::vector<int32_t>> visibleNodesByCell(kinds_.size());
	for (int32_t cell = 0; cell < static_cast<int32_t>(kinds_.size()); ++cell) {
		const ToolKind kind = static_cast<ToolKind>(kinds_[cell]);
		std::vector<int32_t> &nodes = visibleNodesByCell[cell];
		const auto appendVisibleNode = [&](int32_t node) {
			if (node >= 0) {
				appendUnique(nodes, node);
			}
		};
		if (isConductor(kind)) {
			appendVisibleNode(cellNetwork_[cell]);
		} else if (kind == ToolKind::Mesh) {
			for (int32_t node : meshNetworksByCell_[cell]) {
				appendVisibleNode(node);
			}
		} else if (kind == ToolKind::Cross) {
			for (int32_t node : crossNetworksByCell_[cell]) {
				appendVisibleNode(node);
			}
		} else if (kind == ToolKind::Read) {
			appendVisibleNode(readBindings_[readBindingByCell_[cell]].signalNetwork);
		} else if (kind == ToolKind::Write) {
			appendVisibleNode(writeBindings_[writeBindingByCell_[cell]].signalNetwork);
		} else if (isDevice(kind)) {
			appendVisibleNode(cellToComponent_[cell]);
		}
	}
	cellVisibleNodeOffsets_.assign(kinds_.size() + 1U, 0);
	for (size_t cell = 0; cell < visibleNodesByCell.size(); ++cell) {
		cellVisibleNodeOffsets_[cell + 1U] = cellVisibleNodeOffsets_[cell] + visibleNodesByCell[cell].size();
	}
	cellVisibleNodes_.resize(cellVisibleNodeOffsets_.back());
	for (size_t cell = 0; cell < visibleNodesByCell.size(); ++cell) {
		std::copy(
				visibleNodesByCell[cell].begin(),
				visibleNodesByCell[cell].end(),
				cellVisibleNodes_.begin() + static_cast<std::ptrdiff_t>(cellVisibleNodeOffsets_[cell]));
	}
	visibleCellOffsets_.assign(static_cast<size_t>(originalNodeCount) + 1U, 0);
	for (int32_t node : cellVisibleNodes_) {
		if (node >= 0) {
			++visibleCellOffsets_[static_cast<size_t>(node) + 1U];
		}
	}
	for (size_t node = 1; node < visibleCellOffsets_.size(); ++node) {
		visibleCellOffsets_[node] += visibleCellOffsets_[node - 1U];
	}
	visibleCellIndices_.resize(visibleCellOffsets_.back());
	std::vector<size_t> nextVisibleCellOffsets = visibleCellOffsets_;
	for (int32_t cell = 0; cell < static_cast<int32_t>(kinds_.size()); ++cell) {
		for (size_t offset = cellVisibleNodeOffsets_[cell]; offset < cellVisibleNodeOffsets_[static_cast<size_t>(cell) + 1U]; ++offset) {
			const int32_t node = cellVisibleNodes_[offset];
			visibleCellIndices_[nextVisibleCellOffsets[node]++] = cell;
		}
	}
	nodeHasVisibleCells_.assign(originalNodeCount, 0);
	for (int32_t node = 0; node < originalNodeCount; ++node) {
		nodeHasVisibleCells_[node] =
				visibleCellOffsets_[node] != visibleCellOffsets_[static_cast<size_t>(node) + 1U] ? 1 : 0;
	}
	dirtyNodeStamps_.assign(originalNodeCount, 0);
	dirtyNodeInitialStates_.assign(originalNodeCount, 0);
	dirtyNodes_.clear();
	dirtyNodes_.reserve(originalNodeCount);
	dirtyNodeStamp_ = 1;
	materializedCellStamps_.assign(kinds_.size(), 0);
	materializedCellStamp_ = 1;
	visibleStates_.assign(kinds_.size(), 0);
	reportedVisibleStates_.assign(kinds_.size(), 0);
	changedCellStamps_.assign(kinds_.size(), 0);
	changedCells_.clear();
	changeStamp_ = 1;
	networkStates_.clear();
	components_.clear();
	components_.shrink_to_fit();
}

void SimulationCore::initializeConnectorWorkWordHierarchy(size_t workWordCount) {
	connectorActiveWordHierarchy_.clear();
	connectorActiveWordLevelOffsets_.clear();
	while (workWordCount != 0) {
		connectorActiveWordLevelOffsets_.push_back(connectorActiveWordHierarchy_.size());
		const size_t levelWordCount = (workWordCount + 63U) / 64U;
		connectorActiveWordHierarchy_.insert(
				connectorActiveWordHierarchy_.end(), levelWordCount, uint64_t{0});
		if (levelWordCount == 1U) {
			break;
		}
		workWordCount = levelWordCount;
	}
}

uint8_t SimulationCore::evaluateComponent(int32_t node) const {
	return evaluateComponent(node, nodeInputHighCounts_[node]);
}

uint8_t SimulationCore::evaluateComponent(int32_t node, int32_t highInputCount) const {
	return evaluateComponent(node, highInputCount, nodeEvaluationPolicies_[node]);
}

uint8_t SimulationCore::evaluateComponent(int32_t node, int32_t highInputCount, uint8_t evaluationPolicy) const {
	const EvaluationMode mode = static_cast<EvaluationMode>(evaluationPolicy);
	if (mode == EvaluationMode::High) {
		return highInputCount != 0 ? 1 : 0;
	}
	if (mode == EvaluationMode::Low) {
		return highInputCount == 0 ? 1 : 0;
	}
	switch (mode) {
		case EvaluationMode::AllHigh:
			return highInputCount != 0 && highInputCount == nodeInputCounts_[node] ? 1 : 0;
		case EvaluationMode::NotAllHigh:
			return highInputCount == 0 || highInputCount != nodeInputCounts_[node] ? 1 : 0;
		case EvaluationMode::OddParity:
			return (highInputCount & 1) != 0 ? 1 : 0;
		case EvaluationMode::EvenParity:
			return (highInputCount & 1) == 0 ? 1 : 0;
		default:
			return nodeStates_[node];
	}
}

void SimulationCore::updateVisibleCell(int32_t cell) const {
	if (cell < 0 || cell >= static_cast<int32_t>(visibleStates_.size())) {
		return;
	}
	uint8_t state = 0;
	for (size_t offset = cellVisibleNodeOffsets_[cell]; offset < cellVisibleNodeOffsets_[static_cast<size_t>(cell) + 1U]; ++offset) {
		if (nodeStates_[cellVisibleNodes_[offset]] != 0) {
			state = 1;
			break;
		}
	}
	if (visibleStates_[cell] == state) {
		return;
	}
	visibleStates_[cell] = state;
	if (changedCellStamps_[cell] != changeStamp_) {
		changedCellStamps_[cell] = changeStamp_;
		changedCells_.push_back(cell);
	}
}

void SimulationCore::markVisibleNodeDirty(int32_t node, uint8_t initialState, bool forceMaterialization) {
	if (dirtyNodeStamps_[node] != dirtyNodeStamp_) {
		dirtyNodeStamps_[node] = dirtyNodeStamp_;
		dirtyNodeInitialStates_[node] = forceMaterialization ? ForcedVisibleNodeInitialState : initialState;
		dirtyNodes_.push_back(node);
		return;
	}
	if (forceMaterialization) {
		dirtyNodeInitialStates_[node] = ForcedVisibleNodeInitialState;
	}
}

void SimulationCore::markAllVisibleNodesDirty() {
	for (int32_t node = 0; node < static_cast<int32_t>(nodeHasVisibleCells_.size()); ++node) {
		if (nodeHasVisibleCells_[node] != 0) {
			// Restore invalidates the visible cache even when this node state did not change.
			markVisibleNodeDirty(node, nodeStates_[node], true);
		}
	}
}

void SimulationCore::materializeVisibleStates() const {
	if (dirtyNodes_.empty()) {
		return;
	}
	++materializedCellStamp_;
	if (materializedCellStamp_ == 0) {
		std::fill(materializedCellStamps_.begin(), materializedCellStamps_.end(), 0);
		materializedCellStamp_ = 1;
	}
	for (int32_t node : dirtyNodes_) {
		if (dirtyNodeInitialStates_[node] != ForcedVisibleNodeInitialState && dirtyNodeInitialStates_[node] == nodeStates_[node]) {
			continue;
		}
		for (size_t offset = visibleCellOffsets_[node]; offset < visibleCellOffsets_[static_cast<size_t>(node) + 1U]; ++offset) {
			const int32_t cell = visibleCellIndices_[offset];
			if (materializedCellStamps_[cell] == materializedCellStamp_) {
				continue;
			}
			materializedCellStamps_[cell] = materializedCellStamp_;
			updateVisibleCell(cell);
		}
	}
	dirtyNodes_.clear();
	++dirtyNodeStamp_;
	if (dirtyNodeStamp_ == 0) {
		std::fill(dirtyNodeStamps_.begin(), dirtyNodeStamps_.end(), 0);
		dirtyNodeStamp_ = 1;
	}
}

void SimulationCore::setNodeState(int32_t node, uint8_t state) {
	if (nodeStates_[node] == state) {
		return;
	}
	setChangedNodeState(node, state);
}

void SimulationCore::propagateStateChange(int32_t sourceNode, uint8_t oldState, uint8_t newState) {
	if (oldState == newState) {
		return;
	}
	connectorQueueEvents_.clear();
	connectorQueueEvents_.push_back(encodeConnectorEvent(sourceNode, newState));
	drainConnectorQueue();
}

void SimulationCore::beginPropagationBatch(bool nextGateFrontierIsEmpty) {
	for (std::vector<int32_t> &pendingInputs : pendingComponentInputsByMode_) {
		pendingInputs.clear();
	}
	assert(!hasActiveConnectorWorkWords());
	if (nextGateFrontierIsEmpty) {
		assert(nextGateActiveSummaryWordCount_ == 0);
	}
	++propagationStamp_;
	if (propagationStamp_ != 0) {
		return;
	}
	std::fill(componentInputStamps_.begin(), componentInputStamps_.end(), 0);
	std::fill(connectorDeltaStamps_.begin(), connectorDeltaStamps_.end(), 0);
	std::fill(connectorWorkWordStamps_.begin(), connectorWorkWordStamps_.end(), 0);
	propagationStamp_ = 1;
}

void SimulationCore::flushQueuedComponentInputDeltas() {
	const auto flushZeroThresholdInputs = [this](const std::vector<int32_t> &pendingInputs, bool invertOutput) {
		for (int32_t node : pendingInputs) {
			const int32_t inputDelta = pendingComponentInputDeltas_[node];
			const bool gateAlreadyQueued = isComponentGateQueued(node);
			if (inputDelta == 0 && !gateAlreadyQueued) {
				continue;
			}
			int32_t &highInputCount = nodeInputHighCounts_[node];
			highInputCount += inputDelta;
			const uint8_t nextState = static_cast<uint8_t>((highInputCount != 0) ^ invertOutput);
			if (gateAlreadyQueued || nextState != nodeStates_[node]) {
				enqueueComponentGate(node, nextState);
			}
		}
	};
	const auto flushAllHighInputs = [this](const std::vector<int32_t> &pendingInputs, bool invertOutput) {
		for (int32_t node : pendingInputs) {
			const int32_t inputDelta = pendingComponentInputDeltas_[node];
			const bool gateAlreadyQueued = isComponentGateQueued(node);
			if (inputDelta == 0 && !gateAlreadyQueued) {
				continue;
			}
			int32_t &highInputCount = nodeInputHighCounts_[node];
			highInputCount += inputDelta;
			const uint8_t nextState = static_cast<uint8_t>(
					(highInputCount != 0 && highInputCount == nodeInputCounts_[node]) ^ invertOutput);
			if (gateAlreadyQueued || nextState != nodeStates_[node]) {
				enqueueComponentGate(node, nextState);
			}
		}
	};
	const auto flushParityInputs = [this](const std::vector<int32_t> &pendingInputs, bool invertOutput) {
		for (int32_t node : pendingInputs) {
			const int32_t inputDelta = pendingComponentInputDeltas_[node];
			const bool gateAlreadyQueued = isComponentGateQueued(node);
			if (inputDelta == 0 && !gateAlreadyQueued) {
				continue;
			}
			int32_t &highInputCount = nodeInputHighCounts_[node];
			highInputCount += inputDelta;
			const uint8_t nextState = static_cast<uint8_t>(((highInputCount & 1) != 0) ^ invertOutput);
			if (gateAlreadyQueued || nextState != nodeStates_[node]) {
				enqueueComponentGate(node, nextState);
			}
		}
	};
	for (int32_t node : pendingComponentInputsByMode_[static_cast<size_t>(EvaluationMode::State)]) {
		const int32_t inputDelta = pendingComponentInputDeltas_[node];
		const bool gateAlreadyQueued = isComponentGateQueued(node);
		if (inputDelta == 0 && !gateAlreadyQueued) {
			continue;
		}
		nodeInputHighCounts_[node] += inputDelta;
		if (gateAlreadyQueued) {
			enqueueComponentGate(node, nodeStates_[node]);
		}
	}
	flushZeroThresholdInputs(pendingComponentInputsByMode_[static_cast<size_t>(EvaluationMode::High)], false);
	flushZeroThresholdInputs(pendingComponentInputsByMode_[static_cast<size_t>(EvaluationMode::Low)], true);
	flushAllHighInputs(pendingComponentInputsByMode_[static_cast<size_t>(EvaluationMode::AllHigh)], false);
	flushAllHighInputs(pendingComponentInputsByMode_[static_cast<size_t>(EvaluationMode::NotAllHigh)], true);
	flushParityInputs(pendingComponentInputsByMode_[static_cast<size_t>(EvaluationMode::OddParity)], false);
	flushParityInputs(pendingComponentInputsByMode_[static_cast<size_t>(EvaluationMode::EvenParity)], true);
	for (int32_t node : pendingComponentInputsByMode_[static_cast<size_t>(EvaluationMode::LatchToggle)]) {
		const int32_t inputDelta = pendingComponentInputDeltas_[node];
		const bool gateAlreadyQueued = isComponentGateQueued(node);
		nodeInputHighCounts_[node] += inputDelta;
		if ((pendingComponentRisingCounts_[node] & 1) == 0) {
			continue;
		}
		const uint8_t baseState = gateAlreadyQueued ? nextGateStates_[node] : nodeStates_[node];
		enqueueComponentGate(node, baseState == 0 ? 1 : 0);
	}
}

void SimulationCore::flushUnqueuedComponentInputDeltas() {
	assert(nextGateActiveSummaryWordCount_ == 0);
	const auto flushZeroThresholdInputs = [this](const std::vector<int32_t> &pendingInputs, bool invertOutput) {
		for (int32_t node : pendingInputs) {
			const int32_t inputDelta = pendingComponentInputDeltas_[node];
			if (inputDelta == 0) {
				continue;
			}
			int32_t &highInputCount = nodeInputHighCounts_[node];
			const bool previousActive = highInputCount != 0;
			highInputCount += inputDelta;
			const bool nextActive = highInputCount != 0;
			if (previousActive == nextActive) {
				continue;
			}
			assert(nodeStates_[node] == static_cast<uint8_t>(previousActive ^ invertOutput));
			enqueueNewComponentGate(node, static_cast<uint8_t>(nextActive ^ invertOutput));
		}
	};
	const auto flushAllHighInputs = [this](const std::vector<int32_t> &pendingInputs, bool invertOutput) {
		for (int32_t node : pendingInputs) {
			const int32_t inputDelta = pendingComponentInputDeltas_[node];
			if (inputDelta == 0) {
				continue;
			}
			int32_t &highInputCount = nodeInputHighCounts_[node];
			const int32_t inputCount = nodeInputCounts_[node];
			const bool previousActive = highInputCount != 0 && highInputCount == inputCount;
			highInputCount += inputDelta;
			const bool nextActive = highInputCount != 0 && highInputCount == inputCount;
			if (previousActive == nextActive) {
				continue;
			}
			assert(nodeStates_[node] == static_cast<uint8_t>(previousActive ^ invertOutput));
			enqueueNewComponentGate(node, static_cast<uint8_t>(nextActive ^ invertOutput));
		}
	};
	const auto flushParityInputs = [this](const std::vector<int32_t> &pendingInputs, bool invertOutput) {
		for (int32_t node : pendingInputs) {
			const int32_t inputDelta = pendingComponentInputDeltas_[node];
			if (inputDelta == 0) {
				continue;
			}
			int32_t &highInputCount = nodeInputHighCounts_[node];
			const bool previousActive = (highInputCount & 1) != 0;
			highInputCount += inputDelta;
			if (inputDelta % 2 == 0) {
				continue;
			}
			assert(nodeStates_[node] == static_cast<uint8_t>(previousActive ^ invertOutput));
			enqueueNewComponentGate(node, static_cast<uint8_t>(((highInputCount & 1) != 0) ^ invertOutput));
		}
	};
	for (int32_t node : pendingComponentInputsByMode_[static_cast<size_t>(EvaluationMode::State)]) {
		nodeInputHighCounts_[node] += pendingComponentInputDeltas_[node];
	}
	flushZeroThresholdInputs(pendingComponentInputsByMode_[static_cast<size_t>(EvaluationMode::High)], false);
	flushZeroThresholdInputs(pendingComponentInputsByMode_[static_cast<size_t>(EvaluationMode::Low)], true);
	flushAllHighInputs(pendingComponentInputsByMode_[static_cast<size_t>(EvaluationMode::AllHigh)], false);
	flushAllHighInputs(pendingComponentInputsByMode_[static_cast<size_t>(EvaluationMode::NotAllHigh)], true);
	flushParityInputs(pendingComponentInputsByMode_[static_cast<size_t>(EvaluationMode::OddParity)], false);
	flushParityInputs(pendingComponentInputsByMode_[static_cast<size_t>(EvaluationMode::EvenParity)], true);
	for (int32_t node : pendingComponentInputsByMode_[static_cast<size_t>(EvaluationMode::LatchToggle)]) {
		nodeInputHighCounts_[node] += pendingComponentInputDeltas_[node];
		if ((pendingComponentRisingCounts_[node] & 1) != 0) {
			enqueueNewComponentGate(node, nodeStates_[node] == 0 ? 1 : 0);
		}
	}
}

void SimulationCore::finishPropagationBatch(bool nextGateFrontierIsEmpty) {
	while (hasActiveConnectorWorkWords()) {
		const size_t workWordIndex = firstActiveConnectorWorkWord();
		uint64_t &workWord = connectorWorkWords_[workWordIndex];
		assert(workWord != 0);
		while (workWord != 0) {
			const int32_t rankOffset = countTrailingZeros(workWord);
			workWord &= workWord - 1U;
			const size_t connectorRank = workWordIndex * 64U + static_cast<size_t>(rankOffset);
			const int32_t source = connectorNodes_[connectorRank];
			const int32_t stateDelta = pendingConnectorDeltas_[source];
			if (stateDelta == 0) {
				continue;
			}
			int32_t &highInputCount = nodeInputHighCounts_[source];
			const int32_t previousHighInputCount = highInputCount;
			highInputCount += stateDelta;
			const uint8_t previousState = previousHighInputCount != 0 ? 1 : 0;
			const uint8_t nextState = highInputCount != 0 ? 1 : 0;
			if (previousState == nextState) {
				continue;
			}
			setChangedNodeState(source, nextState);
			const int32_t outputStateDelta = nextState != 0 ? 1 : -1;
			seedSourceDelta(source, outputStateDelta);
		}
		deactivateConnectorWorkWord(workWordIndex);
	}
	if (nextGateFrontierIsEmpty) {
		flushUnqueuedComponentInputDeltas();
		return;
	}
	flushQueuedComponentInputDeltas();
}

void SimulationCore::drainConnectorQueue() {
	beginPropagationBatch(false);
	// Seed every component transition before committing connectors, so converging paths share one final delta.
	const size_t initialQueueSize = connectorQueueEvents_.size();
	for (size_t cursor = 0; cursor < initialQueueSize; ++cursor) {
		const int32_t event = connectorQueueEvents_[cursor];
		const bool highState = event >= 0;
		const int32_t source = highState ? event : ~event;
		seedSourceDelta(source, highState ? 1 : -1);
	}
	connectorQueueEvents_.clear();
	finishPropagationBatch(false);
}

void SimulationCore::rebuildDerivedState(const std::vector<uint8_t> &componentStates) {
	nodeStates_.assign(nodeStates_.size(), 0);
	nodeInputHighCounts_.assign(nodeInputHighCounts_.size(), 0);
	std::fill(nextGateWords_.begin(), nextGateWords_.end(), 0);
	std::fill(nextGateSummaryWords_.begin(), nextGateSummaryWords_.end(), 0);
	std::fill(currentGateWords_.begin(), currentGateWords_.end(), 0);
	std::fill(currentGateSummaryWords_.begin(), currentGateSummaryWords_.end(), 0);
	nextGateActiveSummaryWordCount_ = 0;
	currentGateActiveSummaryWordCount_ = 0;
	std::fill(nextGateStates_.begin(), nextGateStates_.end(), 0);
	std::fill(currentGateStates_.begin(), currentGateStates_.end(), 0);
	connectorQueueEvents_.clear();
	for (int32_t index = 0; index < static_cast<int32_t>(componentNodes_.size()); ++index) {
		const int32_t node = componentNodes_[index];
		nodeStates_[node] = componentStates[index];
	}
	for (int32_t node : componentNodes_) {
		if (nodeStates_[node] != 0) {
			connectorQueueEvents_.push_back(encodeConnectorEvent(node, 1));
		}
	}
	suppressLatchInputEdges_ = true;
	drainConnectorQueue();
	suppressLatchInputEdges_ = false;
}

void SimulationCore::resetInternal() {
	tickCount_ = 0;
	std::fill(clockPhases_.begin(), clockPhases_.end(), 0);
	std::fill(nodeInputHighCounts_.begin(), nodeInputHighCounts_.end(), 0);
	std::fill(nextGateWords_.begin(), nextGateWords_.end(), 0);
	std::fill(nextGateSummaryWords_.begin(), nextGateSummaryWords_.end(), 0);
	std::fill(currentGateWords_.begin(), currentGateWords_.end(), 0);
	std::fill(currentGateSummaryWords_.begin(), currentGateSummaryWords_.end(), 0);
	nextGateActiveSummaryWordCount_ = 0;
	currentGateActiveSummaryWordCount_ = 0;
	std::fill(nextGateStates_.begin(), nextGateStates_.end(), 0);
	std::fill(currentGateStates_.begin(), currentGateStates_.end(), 0);
	std::fill(pendingComponentRisingCounts_.begin(), pendingComponentRisingCounts_.end(), 0);
	connectorQueueEvents_.clear();
	for (int32_t node = 0; node < static_cast<int32_t>(nodeStates_.size()); ++node) {
		if (nodeStates_[node] != 0) {
			setNodeState(node, 0);
		}
	}
	for (int32_t node : componentNodes_) {
		uint8_t state = 0;
		if (nodeKinds_[node] == ToolKind::Latch) {
			state = nodeLatchInitialStates_[node];
		} else if (nodeKinds_[node] != ToolKind::Clock) {
			state = evaluateComponent(node);
		}
		if (state != 0) {
			setNodeState(node, state);
		}
	}
	for (int32_t node : componentNodes_) {
		if (nodeStates_[node] != 0) {
			connectorQueueEvents_.push_back(encodeConnectorEvent(node, 1));
		}
	}
	suppressLatchInputEdges_ = true;
	drainConnectorQueue();
	suppressLatchInputEdges_ = false;
}

std::vector<int32_t> SimulationCore::getStates() const {
	if (!compiled_) {
		return {};
	}
	materializeVisibleStates();
	std::vector<int32_t> states(visibleStates_.size(), 0);
	for (int32_t cell = 0; cell < static_cast<int32_t>(visibleStates_.size()); ++cell) {
		states[cell] = visibleStates_[cell];
	}
	return states;
}

void SimulationCore::resetChangeCollector() {
	changedCells_.clear();
	++changeStamp_;
	if (changeStamp_ == 0) {
		std::fill(changedCellStamps_.begin(), changedCellStamps_.end(), 0);
		changeStamp_ = 1;
	}
}

std::vector<int32_t> SimulationCore::drainStateChanges() {
	if (!compiled_) {
		return {};
	}
	materializeVisibleStates();
	if (changedCells_.empty()) {
		return {};
	}
	std::sort(changedCells_.begin(), changedCells_.end());
	std::vector<int32_t> changes;
	changes.reserve(changedCells_.size() * 2U);
	for (int32_t cell : changedCells_) {
		if (visibleStates_[cell] != reportedVisibleStates_[cell]) {
			changes.push_back(cell);
			changes.push_back(visibleStates_[cell]);
		}
		reportedVisibleStates_[cell] = visibleStates_[cell];
	}
	resetChangeCollector();
	return changes;
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
	const int32_t node = cellToComponent_[cellIndex];
	if (node < 0 || nodeKinds_[node] != ToolKind::Latch) {
		errorReason = "not_latch";
		return false;
	}
	const uint8_t previousState = nodeStates_[node];
	const uint8_t nextState = previousState == 0 ? 1 : 0;
	setNodeState(node, nextState);
	if (isComponentGateQueued(node)) {
		nextGateStates_[node] = nextGateStates_[node] == 0 ? 1 : 0;
	}
	propagateStateChange(node, previousState, nextState);
	changes = drainStateChanges();
	return true;
}

void SimulationCore::clearNextGateFrontier() {
	const size_t sparseClearThreshold =
			(nextGateSummaryWords_.size() + GateFrontierSparseClearDivisor - 1U) / GateFrontierSparseClearDivisor;
	if (nextGateActiveSummaryWordCount_ < sparseClearThreshold) {
		for (size_t summaryWordIndex = 0; summaryWordIndex < nextGateSummaryWords_.size(); ++summaryWordIndex) {
			uint64_t summary = nextGateSummaryWords_[summaryWordIndex];
			while (summary != 0) {
				const int32_t wordOffset = countTrailingZeros(summary);
				summary &= summary - 1U;
				const size_t gateWordIndex = summaryWordIndex * 64U + static_cast<size_t>(wordOffset);
				nextGateWords_[gateWordIndex] = 0;
			}
			nextGateSummaryWords_[summaryWordIndex] = 0;
		}
	} else {
		std::fill(nextGateWords_.begin(), nextGateWords_.end(), 0);
		std::fill(nextGateSummaryWords_.begin(), nextGateSummaryWords_.end(), 0);
	}
	nextGateActiveSummaryWordCount_ = 0;
}

void SimulationCore::advanceState() {
	currentGateWords_.swap(nextGateWords_);
	currentGateSummaryWords_.swap(nextGateSummaryWords_);
	currentGateStates_.swap(nextGateStates_);
	std::swap(currentGateActiveSummaryWordCount_, nextGateActiveSummaryWordCount_);
	clearNextGateFrontier();
	connectorQueueEvents_.clear();
	beginPropagationBatch(true);
	for (size_t summaryWordIndex = 0; summaryWordIndex < currentGateSummaryWords_.size(); ++summaryWordIndex) {
		uint64_t summary = currentGateSummaryWords_[summaryWordIndex];
		while (summary != 0) {
			const int32_t wordOffset = countTrailingZeros(summary);
			summary &= summary - 1U;
			const size_t gateWordIndex = summaryWordIndex * 64U + static_cast<size_t>(wordOffset);
			uint64_t gates = currentGateWords_[gateWordIndex];
			while (gates != 0) {
				const int32_t gateOffset = countTrailingZeros(gates);
				gates &= gates - 1U;
				const size_t componentIndex = gateWordIndex * 64U + static_cast<size_t>(gateOffset);
				// Type-stable ordering keeps component IDs in the leading contiguous range.
				const int32_t node = static_cast<int32_t>(componentIndex);
				const uint8_t nextState = currentGateStates_[node];
				const uint8_t previousState = nodeStates_[node];
				if (nextState != previousState) {
					setChangedNodeState(node, nextState);
					seedSourceDelta(node, nextState != 0 ? 1 : -1);
				}
			}
		}
	}
	for (int32_t node : clockNodes_) {
		int32_t phase = clockPhases_[node] + 1;
		if (phase >= nodeClockHoldTicks_[node]) {
			phase = 0;
			const uint8_t previousState = nodeStates_[node];
			const uint8_t nextState = previousState == 0 ? 1 : 0;
			setChangedNodeState(node, nextState);
			seedSourceDelta(node, nextState != 0 ? 1 : -1);
		}
		clockPhases_[node] = phase;
	}
	// This tick begins with an empty next-gate frontier, and only the final flush can populate it.
	finishPropagationBatch(true);
	++tickCount_;
}

std::vector<int32_t> SimulationCore::advanceTick() {
	return advanceTicks(1);
}

void SimulationCore::advanceTicksSilent(int32_t tickCount) {
	if (!compiled_ || tickCount <= 0) {
		return;
	}
	for (int32_t tick = 0; tick < tickCount; ++tick) {
		advanceState();
	}
}

std::vector<int32_t> SimulationCore::advanceTicks(int32_t tickCount) {
	if (!compiled_ || tickCount <= 0) {
		return {};
	}
	advanceTicksSilent(tickCount);
	return drainStateChanges();
}

std::vector<int32_t> SimulationCore::reset() {
	if (!compiled_) {
		return {};
	}
	resetInternal();
	return drainStateChanges();
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
	snapshot.reserve(32 + snapshotComponentNodes_.size() * 6 + snapshotConnectorNodes_.size());
	appendU32(snapshot, SnapshotMagic);
	appendU32(snapshot, SnapshotVersion);
	appendU64(snapshot, topologySignature_);
	appendU32(snapshot, static_cast<uint32_t>(snapshotComponentNodes_.size()));
	appendU32(snapshot, static_cast<uint32_t>(snapshotConnectorNodes_.size()));
	appendU64(snapshot, tickCount_);
	for (int32_t node : snapshotComponentNodes_) {
		snapshot.push_back(nodeStates_[node]);
	}
	for (int32_t node : snapshotConnectorNodes_) {
		snapshot.push_back(nodeStates_[node]);
	}
	for (int32_t node : snapshotComponentNodes_) {
		appendU32(snapshot, static_cast<uint32_t>(clockPhases_[node]));
	}
	for (int32_t node : snapshotComponentNodes_) {
		const uint8_t queuedState = isComponentGateQueued(node) ? static_cast<uint8_t>(nextGateStates_[node] + 1U) : 0;
		snapshot.push_back(queuedState);
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
	if (signature != topologySignature_ || componentCount != snapshotComponentNodes_.size() || networkCount != snapshotConnectorNodes_.size()) {
		errorReason = "snapshot_topology_mismatch";
		return false;
	}
	const size_t expectedTail = static_cast<size_t>(componentCount) * 2U + static_cast<size_t>(networkCount) + static_cast<size_t>(componentCount) * 4U;
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
	std::vector<int32_t> clockPhases(clockPhases_.size(), 0);
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
		const int32_t node = snapshotComponentNodes_[component];
		if (nodeKinds_[node] == ToolKind::Clock && phase >= static_cast<uint32_t>(nodeClockHoldTicks_[node])) {
			errorReason = "invalid_snapshot_state";
			return false;
		}
		clockPhases[node] = static_cast<int32_t>(phase);
	}
	std::vector<uint8_t> queuedGateStates(componentCount, 0);
	for (uint32_t component = 0; component < componentCount; ++component) {
		const uint8_t queuedState = snapshot[offset++];
		if (queuedState > 2) {
			errorReason = "invalid_snapshot_state";
			return false;
		}
		queuedGateStates[component] = queuedState;
	}
	visibleStates_.assign(visibleStates_.size(), 0);
	changedCells_.clear();
	std::fill(changedCellStamps_.begin(), changedCellStamps_.end(), 0);
	changeStamp_ = 1;
	dirtyNodes_.clear();
	std::fill(dirtyNodeStamps_.begin(), dirtyNodeStamps_.end(), 0);
	std::fill(dirtyNodeInitialStates_.begin(), dirtyNodeInitialStates_.end(), 0);
	dirtyNodeStamp_ = 1;
	std::vector<uint8_t> componentStatesInRuntimeOrder(componentNodes_.size(), 0);
	for (int32_t component = 0; component < static_cast<int32_t>(snapshotComponentNodes_.size()); ++component) {
		const int32_t node = snapshotComponentNodes_[component];
		const auto runtimePosition = std::lower_bound(componentNodes_.begin(), componentNodes_.end(), node);
		componentStatesInRuntimeOrder[static_cast<size_t>(runtimePosition - componentNodes_.begin())] = componentStates[component];
	}
	rebuildDerivedState(componentStatesInRuntimeOrder);
	std::fill(nextGateWords_.begin(), nextGateWords_.end(), 0);
	std::fill(nextGateSummaryWords_.begin(), nextGateSummaryWords_.end(), 0);
	nextGateActiveSummaryWordCount_ = 0;
	std::fill(nextGateStates_.begin(), nextGateStates_.end(), 0);
	for (int32_t component = 0; component < static_cast<int32_t>(snapshotComponentNodes_.size()); ++component) {
		const uint8_t queuedState = queuedGateStates[component];
		if (queuedState != 0) {
			enqueueComponentGate(snapshotComponentNodes_[component], queuedState - 1U);
		}
	}
	markAllVisibleNodesDirty();
	materializeVisibleStates();
	clockPhases_ = std::move(clockPhases);
	tickCount_ = tickCount;
	reportedVisibleStates_ = visibleStates_;
	resetChangeCollector();
	return true;
}

bool SimulationCore::isCompiled() const {
	return compiled_;
}

bool SimulationCore::isGraphLocalityOrderingApplied() const {
	return graphLocalityOrderingApplied_;
}

int64_t SimulationCore::getGraphLocalityScore() const {
	return graphLocalityScore_;
}

} // namespace ocb
