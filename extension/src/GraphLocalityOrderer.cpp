#include "GraphLocalityOrderer.hpp"

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <queue>
#include <utility>

namespace ocb {
namespace {

bool hasValidCsr(int32_t nodeCount, const std::vector<int32_t> &offsets, const std::vector<int32_t> &neighbors) {
	if (nodeCount < 0 || offsets.size() != static_cast<size_t>(nodeCount) + 1U || offsets.empty() || offsets.front() != 0 ||
			offsets.back() != static_cast<int32_t>(neighbors.size())) {
		return false;
	}
	for (int32_t node = 0; node < nodeCount; ++node) {
		if (offsets[node] > offsets[node + 1] || offsets[node] < 0) {
			return false;
		}
	}
	for (int32_t neighbor : neighbors) {
		if (neighbor < 0 || neighbor >= nodeCount) {
			return false;
		}
	}
	return true;
}

GraphLocalityOrder makeIdentityOrder(int32_t nodeCount) {
	GraphLocalityOrder result;
	if (nodeCount <= 0) {
		return result;
	}
	result.newToOld.resize(nodeCount);
	result.oldToNew.resize(nodeCount);
	for (int32_t node = 0; node < nodeCount; ++node) {
		result.newToOld[node] = node;
		result.oldToNew[node] = node;
	}
	return result;
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

void buildIncomingCsr(
		int32_t nodeCount,
		const std::vector<int32_t> &outgoingOffsets,
		const std::vector<int32_t> &outgoingTargets,
		std::vector<int32_t> &incomingOffsets,
		std::vector<int32_t> &incomingSources) {
	incomingOffsets.assign(static_cast<size_t>(nodeCount) + 1U, 0);
	for (int32_t target : outgoingTargets) {
		++incomingOffsets[static_cast<size_t>(target) + 1U];
	}
	for (int32_t node = 1; node <= nodeCount; ++node) {
		incomingOffsets[node] += incomingOffsets[node - 1];
	}
	incomingSources.assign(outgoingTargets.size(), 0);
	std::vector<int32_t> insertionOffsets = incomingOffsets;
	for (int32_t source = 0; source < nodeCount; ++source) {
		for (int32_t edge = outgoingOffsets[source]; edge < outgoingOffsets[source + 1]; ++edge) {
			const int32_t target = outgoingTargets[edge];
			incomingSources[insertionOffsets[target]++] = source;
		}
	}
}

GraphLocalityOrder makeDirectedReverseCuthillMcKeeOrder(
		int32_t nodeCount,
		const std::vector<int32_t> &outgoingOffsets,
		const std::vector<int32_t> &outgoingTargets,
		const std::vector<int32_t> &incomingOffsets) {
	std::vector<int32_t> degrees(nodeCount, 0);
	std::vector<int32_t> seedNodes(nodeCount, 0);
	for (int32_t node = 0; node < nodeCount; ++node) {
		degrees[node] = outgoingOffsets[node + 1] - outgoingOffsets[node] + incomingOffsets[node + 1] - incomingOffsets[node];
		seedNodes[node] = node;
	}
	std::sort(seedNodes.begin(), seedNodes.end(), [&](int32_t left, int32_t right) {
		return degrees[left] != degrees[right] ? degrees[left] < degrees[right] : left < right;
	});

	std::vector<uint8_t> visited(nodeCount, 0);
	std::vector<int32_t> traversal;
	traversal.reserve(nodeCount);
	std::vector<int32_t> queue;
	queue.reserve(nodeCount);
	std::vector<int32_t> neighbors;
	for (int32_t seed : seedNodes) {
		if (visited[seed] != 0) {
			continue;
		}
		queue.clear();
		queue.push_back(seed);
		visited[seed] = 1;
		for (size_t cursor = 0; cursor < queue.size(); ++cursor) {
			const int32_t node = queue[cursor];
			traversal.push_back(node);
			neighbors.clear();
			for (int32_t edge = outgoingOffsets[node]; edge < outgoingOffsets[node + 1]; ++edge) {
				const int32_t neighbor = outgoingTargets[edge];
				if (visited[neighbor] == 0) {
					neighbors.push_back(neighbor);
				}
			}
			std::sort(neighbors.begin(), neighbors.end(), [&](int32_t left, int32_t right) {
				return degrees[left] != degrees[right] ? degrees[left] < degrees[right] : left < right;
			});
			for (int32_t neighbor : neighbors) {
				if (visited[neighbor] != 0) {
					continue;
				}
				visited[neighbor] = 1;
				queue.push_back(neighbor);
			}
		}
	}

	GraphLocalityOrder result;
	result.newToOld.resize(nodeCount);
	result.oldToNew.resize(nodeCount);
	for (int32_t position = 0; position < nodeCount; ++position) {
		const int32_t oldNode = traversal[nodeCount - 1 - position];
		result.newToOld[position] = oldNode;
		result.oldToNew[oldNode] = position;
	}
	return result;
}

void remapCsr(
		int32_t nodeCount,
		const std::vector<int32_t> &offsets,
		const std::vector<int32_t> &targets,
		const std::vector<int32_t> &oldToNew,
		std::vector<int32_t> &remappedOffsets,
		std::vector<int32_t> &remappedTargets) {
	std::vector<std::vector<int32_t>> adjacency(nodeCount);
	for (int32_t source = 0; source < nodeCount; ++source) {
		const int32_t remappedSource = oldToNew[source];
		for (int32_t edge = offsets[source]; edge < offsets[source + 1]; ++edge) {
			adjacency[remappedSource].push_back(oldToNew[targets[edge]]);
		}
	}
	for (std::vector<int32_t> &neighbors : adjacency) {
		std::sort(neighbors.begin(), neighbors.end());
		neighbors.erase(std::unique(neighbors.begin(), neighbors.end()), neighbors.end());
	}
	flattenCsr(adjacency, remappedOffsets, remappedTargets);
}

class IndexedScoreHeap {
public:
	IndexedScoreHeap(const std::vector<int64_t> &scores, std::vector<int32_t> nodes, int32_t nodeCount)
			: scores_(scores), nodes_(std::move(nodes)), positions_(nodeCount, -1) {
		for (int32_t index = 0; index < static_cast<int32_t>(nodes_.size()); ++index) {
			positions_[nodes_[index]] = index;
		}
		for (int32_t index = static_cast<int32_t>(nodes_.size()) / 2 - 1; index >= 0; --index) {
			siftDown(index);
		}
	}

	void adjust(int32_t node) {
		const int32_t index = positions_[node];
		if (index < 0) {
			return;
		}
		const int32_t parent = (index - 1) / 2;
		if (index > 0 && isHigher(nodes_[index], nodes_[parent])) {
			siftUp(index);
			return;
		}
		siftDown(index);
	}

	void remove(int32_t node) {
		const int32_t index = positions_[node];
		if (index < 0) {
			return;
		}
		removeAt(index);
	}

	int32_t popMax() {
		if (nodes_.empty()) {
			return -1;
		}
		const int32_t node = nodes_.front();
		removeAt(0);
		return node;
	}

private:
	bool isHigher(int32_t left, int32_t right) const {
		return scores_[left] != scores_[right] ? scores_[left] > scores_[right] : left < right;
	}

	void swapNodes(int32_t left, int32_t right) {
		std::swap(nodes_[left], nodes_[right]);
		positions_[nodes_[left]] = left;
		positions_[nodes_[right]] = right;
	}

	void siftUp(int32_t index) {
		while (index > 0) {
			const int32_t parent = (index - 1) / 2;
			if (!isHigher(nodes_[index], nodes_[parent])) {
				break;
			}
			swapNodes(index, parent);
			index = parent;
		}
	}

	void siftDown(int32_t index) {
		const int32_t size = static_cast<int32_t>(nodes_.size());
		while (true) {
			const int32_t left = index * 2 + 1;
			if (left >= size) {
				return;
			}
			const int32_t right = left + 1;
			int32_t best = left;
			if (right < size && isHigher(nodes_[right], nodes_[left])) {
				best = right;
			}
			if (!isHigher(nodes_[best], nodes_[index])) {
				return;
			}
			swapNodes(index, best);
			index = best;
		}
	}

	void removeAt(int32_t index) {
		const int32_t removedNode = nodes_[index];
		const int32_t lastNode = nodes_.back();
		nodes_.pop_back();
		positions_[removedNode] = -1;
		if (index >= static_cast<int32_t>(nodes_.size())) {
			return;
		}
		nodes_[index] = lastNode;
		positions_[lastNode] = index;
		adjust(lastNode);
	}

	const std::vector<int64_t> &scores_;
	std::vector<int32_t> nodes_;
	std::vector<int32_t> positions_;
};

GraphLocalityOrder makeGorderOrder(
		int32_t nodeCount,
		const std::vector<int32_t> &outgoingOffsets,
		const std::vector<int32_t> &outgoingTargets,
		const std::vector<int32_t> &incomingOffsets,
		const std::vector<int32_t> &incomingSources) {
	std::vector<int32_t> inDegrees(nodeCount, 0);
	std::vector<int32_t> outDegrees(nodeCount, 0);
	std::vector<int32_t> isolatedNodes;
	isolatedNodes.reserve(nodeCount);
	int32_t firstNode = -1;
	for (int32_t node = 0; node < nodeCount; ++node) {
		outDegrees[node] = outgoingOffsets[node + 1] - outgoingOffsets[node];
		inDegrees[node] = incomingOffsets[node + 1] - incomingOffsets[node];
		if (outDegrees[node] + inDegrees[node] == 0) {
			isolatedNodes.push_back(node);
			continue;
		}
		if (firstNode < 0 || inDegrees[node] > inDegrees[firstNode] ||
				(inDegrees[node] == inDegrees[firstNode] && node < firstNode)) {
			firstNode = node;
		}
	}
	if (firstNode < 0) {
		return makeIdentityOrder(nodeCount);
	}

	const int32_t largeOutDegree = std::max<int32_t>(1, static_cast<int32_t>(std::sqrt(static_cast<double>(nodeCount))));
	std::vector<uint8_t> selected(nodeCount, 0);
	std::vector<int64_t> scores(nodeCount, 0);
	std::vector<int32_t> candidateNodes;
	candidateNodes.reserve(nodeCount - static_cast<int32_t>(isolatedNodes.size()));
	for (int32_t node = 0; node < nodeCount; ++node) {
		if (outDegrees[node] + inDegrees[node] != 0) {
			candidateNodes.push_back(node);
		}
	}
	IndexedScoreHeap candidates(scores, std::move(candidateNodes), nodeCount);

	const auto updateScore = [&](int32_t node, int32_t delta) {
		if (selected[node] != 0) {
			return;
		}
		scores[node] += delta;
		candidates.adjust(node);
	};
	const auto updateWindowScore = [&](int32_t node, int32_t delta) {
		if (outDegrees[node] <= largeOutDegree) {
			for (int32_t edge = outgoingOffsets[node]; edge < outgoingOffsets[node + 1]; ++edge) {
				updateScore(outgoingTargets[edge], delta);
			}
		}
		for (int32_t edge = incomingOffsets[node]; edge < incomingOffsets[node + 1]; ++edge) {
			const int32_t source = incomingSources[edge];
			if (outDegrees[source] > largeOutDegree) {
				continue;
			}
			updateScore(source, delta);
			if (outDegrees[source] <= 1) {
				continue;
			}
			for (int32_t sharedEdge = outgoingOffsets[source]; sharedEdge < outgoingOffsets[source + 1]; ++sharedEdge) {
				updateScore(outgoingTargets[sharedEdge], delta);
			}
		}
	};

	GraphLocalityOrder result;
	result.newToOld.reserve(nodeCount);
	result.oldToNew.assign(nodeCount, -1);
	const auto selectNode = [&](int32_t node) {
		selected[node] = 1;
		result.oldToNew[node] = static_cast<int32_t>(result.newToOld.size());
		result.newToOld.push_back(node);
	};
	selectNode(firstNode);
	candidates.remove(firstNode);
	updateWindowScore(firstNode, 1);
	std::queue<int32_t> window;
	window.push(firstNode);

	const int32_t connectedNodeCount = nodeCount - static_cast<int32_t>(isolatedNodes.size());
	while (static_cast<int32_t>(result.newToOld.size()) < connectedNodeCount) {
		int32_t nextNode = candidates.popMax();
		if (nextNode < 0) {
			for (int32_t node = 0; node < nodeCount; ++node) {
				if (selected[node] == 0 && (nextNode < 0 || inDegrees[node] > inDegrees[nextNode] ||
						(inDegrees[node] == inDegrees[nextNode] && node < nextNode))) {
					nextNode = node;
				}
			}
		}
		selectNode(nextNode);
		updateWindowScore(nextNode, 1);
		window.push(nextNode);
		if (window.size() > static_cast<size_t>(GraphLocalityOrderer::WindowSize)) {
			updateWindowScore(window.front(), -1);
			window.pop();
		}
	}
	for (int32_t node : isolatedNodes) {
		result.oldToNew[node] = static_cast<int32_t>(result.newToOld.size());
		result.newToOld.push_back(node);
	}
	return result;
}

bool isPermutation(int32_t nodeCount, const std::vector<int32_t> &oldToNew) {
	if (oldToNew.size() != static_cast<size_t>(nodeCount)) {
		return false;
	}
	std::vector<uint8_t> seen(nodeCount, 0);
	for (int32_t newNode : oldToNew) {
		if (newNode < 0 || newNode >= nodeCount || seen[newNode] != 0) {
			return false;
		}
		seen[newNode] = 1;
	}
	return true;
}

} // namespace

GraphLocalityOrder GraphLocalityOrderer::order(
		int32_t nodeCount,
		const std::vector<int32_t> &outgoingOffsets,
		const std::vector<int32_t> &outgoingTargets,
		const std::vector<int32_t> &incomingOffsets,
		const std::vector<int32_t> &incomingSources) {
	if (!hasValidCsr(nodeCount, outgoingOffsets, outgoingTargets) || !hasValidCsr(nodeCount, incomingOffsets, incomingSources) ||
			nodeCount <= 1) {
		return makeIdentityOrder(nodeCount);
	}

	const GraphLocalityOrder rcmOrder = makeDirectedReverseCuthillMcKeeOrder(
			nodeCount, outgoingOffsets, outgoingTargets, incomingOffsets);
	std::vector<int32_t> transformedOutgoingOffsets;
	std::vector<int32_t> transformedOutgoingTargets;
	remapCsr(
			nodeCount,
			outgoingOffsets,
			outgoingTargets,
			rcmOrder.oldToNew,
			transformedOutgoingOffsets,
			transformedOutgoingTargets);
	std::vector<int32_t> transformedIncomingOffsets;
	std::vector<int32_t> transformedIncomingSources;
	buildIncomingCsr(
			nodeCount,
			transformedOutgoingOffsets,
			transformedOutgoingTargets,
			transformedIncomingOffsets,
			transformedIncomingSources);
	const GraphLocalityOrder gorderOrder = makeGorderOrder(
			nodeCount,
			transformedOutgoingOffsets,
			transformedOutgoingTargets,
			transformedIncomingOffsets,
			transformedIncomingSources);

	GraphLocalityOrder result;
	result.newToOld.resize(nodeCount);
	result.oldToNew.resize(nodeCount);
	for (int32_t oldNode = 0; oldNode < nodeCount; ++oldNode) {
		const int32_t rcmNode = rcmOrder.oldToNew[oldNode];
		const int32_t newNode = gorderOrder.oldToNew[rcmNode];
		result.oldToNew[oldNode] = newNode;
		result.newToOld[newNode] = oldNode;
	}
	return result;
}

GraphLocalityOrder GraphLocalityOrderer::order(
		const std::vector<int32_t> &outgoingOffsets,
		const std::vector<int32_t> &outgoingTargets,
		const std::vector<int32_t> &incomingOffsets,
		const std::vector<int32_t> &incomingSources) {
	if (outgoingOffsets.empty()) {
		return {};
	}
	return order(static_cast<int32_t>(outgoingOffsets.size()) - 1, outgoingOffsets, outgoingTargets, incomingOffsets, incomingSources);
}

int64_t GraphLocalityOrderer::calculateLocalityScore(
		int32_t nodeCount,
		const std::vector<int32_t> &outgoingOffsets,
		const std::vector<int32_t> &outgoingTargets,
		const std::vector<int32_t> &oldToNew) {
	if (!hasValidCsr(nodeCount, outgoingOffsets, outgoingTargets) || !isPermutation(nodeCount, oldToNew)) {
		return 0;
	}
	int64_t score = 0;
	for (int32_t source = 0; source < nodeCount; ++source) {
		for (int32_t edge = outgoingOffsets[source]; edge < outgoingOffsets[source + 1]; ++edge) {
			const int32_t distance = std::abs(oldToNew[source] - oldToNew[outgoingTargets[edge]]);
			if (distance <= WindowSize) {
				score += WindowSize + 1 - distance;
			}
		}
	}
	return score;
}

int64_t GraphLocalityOrderer::calculateLocalityScore(
		const std::vector<int32_t> &outgoingOffsets,
		const std::vector<int32_t> &outgoingTargets,
		const std::vector<int32_t> &oldToNew) {
	if (outgoingOffsets.empty()) {
		return 0;
	}
	return calculateLocalityScore(static_cast<int32_t>(outgoingOffsets.size()) - 1, outgoingOffsets, outgoingTargets, oldToNew);
}

} // namespace ocb
