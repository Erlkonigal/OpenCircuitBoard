#pragma once

#include <cstdint>
#include <vector>

namespace ocb {

struct GraphLocalityOrder {
	// Maps a reordered node index to the source graph node index.
	std::vector<int32_t> newToOld;
	// Maps a source graph node index to the reordered node index.
	std::vector<int32_t> oldToNew;
};

class GraphLocalityOrderer {
public:
	static constexpr int32_t WindowSize = 64;

	static GraphLocalityOrder order(
		int32_t nodeCount,
		const std::vector<int32_t> &outgoingOffsets,
		const std::vector<int32_t> &outgoingTargets,
		const std::vector<int32_t> &incomingOffsets,
		const std::vector<int32_t> &incomingSources);

	static GraphLocalityOrder order(
		const std::vector<int32_t> &outgoingOffsets,
		const std::vector<int32_t> &outgoingTargets,
		const std::vector<int32_t> &incomingOffsets,
		const std::vector<int32_t> &incomingSources);

	// Each edge within WindowSize positions contributes WindowSize + 1 - distance.
	// Higher scores place connected nodes closer together in the reordered graph.
	static int64_t calculateLocalityScore(
		int32_t nodeCount,
		const std::vector<int32_t> &outgoingOffsets,
		const std::vector<int32_t> &outgoingTargets,
		const std::vector<int32_t> &oldToNew);

	static int64_t calculateLocalityScore(
		const std::vector<int32_t> &outgoingOffsets,
		const std::vector<int32_t> &outgoingTargets,
		const std::vector<int32_t> &oldToNew);
};

} // namespace ocb
