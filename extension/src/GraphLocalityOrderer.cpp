#include "GraphLocalityOrderer.hpp"

#include <algorithm>
#include <cstdlib>
#include <limits>

namespace ocb {
namespace {

bool hasValidCsr(int32_t nodeCount, const std::vector<int32_t> &offsets, const std::vector<int32_t> &neighbors) {
	if (nodeCount < 0 || offsets.size() != static_cast<size_t>(nodeCount) + 1 || offsets.empty() || offsets.front() != 0 || offsets.back() != static_cast<int32_t>(neighbors.size())) {
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

void beginWindowMarks(std::vector<int32_t> &stamps, int32_t &stamp) {
	if (stamp == std::numeric_limits<int32_t>::max()) {
		std::fill(stamps.begin(), stamps.end(), 0);
		stamp = 1;
	} else {
		++stamp;
	}
}

void markWindowNeighbor(std::vector<int32_t> &stamps, std::vector<uint8_t> &masks, int32_t stamp, int32_t neighbor, uint8_t windowBit) {
	if (stamps[neighbor] != stamp) {
		stamps[neighbor] = stamp;
		masks[neighbor] = 0;
	}
	masks[neighbor] |= windowBit;
}

int32_t countSetBits(uint8_t bits) {
	int32_t count = 0;
	while (bits != 0) {
		bits &= static_cast<uint8_t>(bits - 1);
		++count;
	}
	return count;
}

int64_t countMarkedNeighbors(
	const std::vector<int32_t> &offsets,
	const std::vector<int32_t> &neighbors,
	int32_t node,
	const std::vector<int32_t> &stamps,
	const std::vector<uint8_t> &masks,
	int32_t stamp) {
	int64_t count = 0;
	for (int32_t edge = offsets[node]; edge < offsets[node + 1]; ++edge) {
		const int32_t neighbor = neighbors[edge];
		if (stamps[neighbor] == stamp) {
			count += countSetBits(masks[neighbor]);
		}
	}
	return count;
}

int64_t calculateCandidateScore(
	int32_t candidate,
	const std::vector<int32_t> &outgoingOffsets,
	const std::vector<int32_t> &outgoingTargets,
	const std::vector<int32_t> &incomingOffsets,
	const std::vector<int32_t> &incomingSources,
	const std::vector<int32_t> &outgoingStamps,
	const std::vector<uint8_t> &outgoingMasks,
	int32_t outgoingStamp,
	const std::vector<int32_t> &incomingStamps,
	const std::vector<uint8_t> &incomingMasks,
	int32_t incomingStamp) {
	int64_t score = 0;
	score += countMarkedNeighbors(outgoingOffsets, outgoingTargets, candidate, outgoingStamps, outgoingMasks, outgoingStamp);
	score += countMarkedNeighbors(incomingOffsets, incomingSources, candidate, incomingStamps, incomingMasks, incomingStamp);
	if (outgoingStamps[candidate] == outgoingStamp) {
		score += countSetBits(outgoingMasks[candidate]);
	}
	if (incomingStamps[candidate] == incomingStamp) {
		score += countSetBits(incomingMasks[candidate]);
	}
	return score;
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
	if (!hasValidCsr(nodeCount, outgoingOffsets, outgoingTargets) || !hasValidCsr(nodeCount, incomingOffsets, incomingSources)) {
		return makeIdentityOrder(nodeCount);
	}

	GraphLocalityOrder result;
	result.newToOld.reserve(nodeCount);
	result.oldToNew.assign(nodeCount, -1);

	std::vector<int32_t> degrees(nodeCount, 0);
	std::vector<int32_t> seedNodes;
	seedNodes.reserve(nodeCount);
	std::vector<int32_t> isolatedNodes;
	isolatedNodes.reserve(nodeCount);
	for (int32_t node = 0; node < nodeCount; ++node) {
		degrees[node] = outgoingOffsets[node + 1] - outgoingOffsets[node] + incomingOffsets[node + 1] - incomingOffsets[node];
		if (degrees[node] == 0) {
			isolatedNodes.push_back(node);
		} else {
			seedNodes.push_back(node);
		}
	}
	std::sort(seedNodes.begin(), seedNodes.end(), [&](int32_t left, int32_t right) {
		return degrees[left] != degrees[right] ? degrees[left] > degrees[right] : left < right;
	});

	std::vector<uint8_t> selected(nodeCount, 0);
	std::vector<int32_t> candidateMarks(nodeCount, 0);
	std::vector<int32_t> outgoingStamps(nodeCount, 0);
	std::vector<uint8_t> outgoingMasks(nodeCount, 0);
	std::vector<int32_t> incomingStamps(nodeCount, 0);
	std::vector<uint8_t> incomingMasks(nodeCount, 0);
	std::vector<int32_t> candidates;
	int32_t candidateStamp = 0;
	int32_t outgoingStamp = 0;
	int32_t incomingStamp = 0;
	size_t nextSeedIndex = 0;
	const auto selectNextSeed = [&]() {
		while (nextSeedIndex < seedNodes.size() && selected[seedNodes[nextSeedIndex]] != 0) {
			++nextSeedIndex;
		}
		return nextSeedIndex < seedNodes.size() ? seedNodes[nextSeedIndex] : -1;
	};

	const int32_t firstSeed = selectNextSeed();
	if (firstSeed >= 0) {
		result.newToOld.push_back(firstSeed);
		selected[firstSeed] = 1;
	}

	while (result.newToOld.size() < seedNodes.size()) {

		if (candidateStamp == std::numeric_limits<int32_t>::max()) {
			std::fill(candidateMarks.begin(), candidateMarks.end(), 0);
			candidateStamp = 1;
		} else {
			++candidateStamp;
		}

		beginWindowMarks(outgoingStamps, outgoingStamp);
		beginWindowMarks(incomingStamps, incomingStamp);
		candidates.clear();
		const int32_t windowBegin = std::max<int32_t>(0, static_cast<int32_t>(result.newToOld.size()) - WindowSize);
		for (int32_t position = windowBegin; position < static_cast<int32_t>(result.newToOld.size()); ++position) {
			const int32_t windowNode = result.newToOld[position];
			const uint8_t windowBit = static_cast<uint8_t>(1U << (position - windowBegin));
			const auto appendCandidates = [&](const std::vector<int32_t> &offsets, const std::vector<int32_t> &neighbors, std::vector<int32_t> &stamps, std::vector<uint8_t> &masks, int32_t stamp) {
				for (int32_t edge = offsets[windowNode]; edge < offsets[windowNode + 1]; ++edge) {
					const int32_t candidate = neighbors[edge];
					markWindowNeighbor(stamps, masks, stamp, candidate, windowBit);
					if (selected[candidate] == 0 && candidateMarks[candidate] != candidateStamp) {
						candidateMarks[candidate] = candidateStamp;
						candidates.push_back(candidate);
					}
				}
			};
			appendCandidates(outgoingOffsets, outgoingTargets, outgoingStamps, outgoingMasks, outgoingStamp);
			appendCandidates(incomingOffsets, incomingSources, incomingStamps, incomingMasks, incomingStamp);
		}

		int32_t nextNode = -1;
		int64_t bestScore = std::numeric_limits<int64_t>::min();
		for (int32_t candidate : candidates) {
			const int64_t score = calculateCandidateScore(
				candidate,
				outgoingOffsets,
				outgoingTargets,
				incomingOffsets,
				incomingSources,
				outgoingStamps,
				outgoingMasks,
				outgoingStamp,
				incomingStamps,
				incomingMasks,
				incomingStamp);
			if (score > bestScore || (score == bestScore && (nextNode < 0 || candidate < nextNode))) {
				nextNode = candidate;
				bestScore = score;
			}
		}

		if (nextNode < 0) {
			nextNode = selectNextSeed();
			if (nextNode < 0) {
				break;
			}
		}
		result.newToOld.push_back(nextNode);
		selected[nextNode] = 1;
	}

	for (int32_t node : isolatedNodes) {
		result.newToOld.push_back(node);
	}

	for (int32_t newNode = 0; newNode < static_cast<int32_t>(result.newToOld.size()); ++newNode) {
		result.oldToNew[result.newToOld[newNode]] = newNode;
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
