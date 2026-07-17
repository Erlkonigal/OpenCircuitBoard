#include "GraphLocalityOrderer.hpp"

#include <algorithm>
#include <cstdlib>
#include <iostream>
#include <numeric>
#include <string>
#include <utility>
#include <vector>

namespace {

using ocb::GraphLocalityOrder;
using ocb::GraphLocalityOrderer;

struct Graph {
	std::vector<int32_t> outgoingOffsets;
	std::vector<int32_t> outgoingTargets;
	std::vector<int32_t> incomingOffsets;
	std::vector<int32_t> incomingSources;
};

void expect(bool condition, const std::string &message) {
	if (!condition) {
		std::cerr << "FAILED: " << message << '\n';
		std::exit(1);
	}
}

Graph makeGraph(int32_t nodeCount, const std::vector<std::pair<int32_t, int32_t>> &edges) {
	std::vector<std::vector<int32_t>> outgoing(nodeCount);
	std::vector<std::vector<int32_t>> incoming(nodeCount);
	for (const std::pair<int32_t, int32_t> &edge : edges) {
		expect(edge.first >= 0 && edge.first < nodeCount && edge.second >= 0 && edge.second < nodeCount, "test edge is within the graph");
		outgoing[edge.first].push_back(edge.second);
		incoming[edge.second].push_back(edge.first);
	}

	Graph graph;
	graph.outgoingOffsets.reserve(nodeCount + 1);
	graph.incomingOffsets.reserve(nodeCount + 1);
	graph.outgoingOffsets.push_back(0);
	graph.incomingOffsets.push_back(0);
	for (int32_t node = 0; node < nodeCount; ++node) {
		std::sort(outgoing[node].begin(), outgoing[node].end());
		std::sort(incoming[node].begin(), incoming[node].end());
		graph.outgoingTargets.insert(graph.outgoingTargets.end(), outgoing[node].begin(), outgoing[node].end());
		graph.incomingSources.insert(graph.incomingSources.end(), incoming[node].begin(), incoming[node].end());
		graph.outgoingOffsets.push_back(static_cast<int32_t>(graph.outgoingTargets.size()));
		graph.incomingOffsets.push_back(static_cast<int32_t>(graph.incomingSources.size()));
	}
	return graph;
}

Graph makeSeparatedPairsGraph() {
	return makeGraph(8, {
		{0, 4},
		{1, 5},
		{2, 6},
		{4, 0},
		{5, 1},
		{6, 2},
	});
}

std::vector<std::pair<int32_t, int32_t>> collectEdges(const Graph &graph) {
	std::vector<std::pair<int32_t, int32_t>> edges;
	for (int32_t source = 0; source + 1 < static_cast<int32_t>(graph.outgoingOffsets.size()); ++source) {
		for (int32_t edge = graph.outgoingOffsets[source]; edge < graph.outgoingOffsets[source + 1]; ++edge) {
			edges.emplace_back(source, graph.outgoingTargets[edge]);
		}
	}
	std::sort(edges.begin(), edges.end());
	return edges;
}

bool isCompletePermutation(const GraphLocalityOrder &order, int32_t nodeCount) {
	if (order.newToOld.size() != static_cast<size_t>(nodeCount) || order.oldToNew.size() != static_cast<size_t>(nodeCount)) {
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

void testDeterministicOutput() {
	const Graph graph = makeSeparatedPairsGraph();
	const GraphLocalityOrder first = GraphLocalityOrderer::order(
		graph.outgoingOffsets, graph.outgoingTargets, graph.incomingOffsets, graph.incomingSources);
	const GraphLocalityOrder second = GraphLocalityOrderer::order(
		graph.outgoingOffsets, graph.outgoingTargets, graph.incomingOffsets, graph.incomingSources);
	const std::vector<int32_t> expected = {0, 4, 1, 5, 2, 6, 3, 7};
	expect(first.newToOld == second.newToOld, "GraphLocalityOrderer produces deterministic ordering");
	expect(first.oldToNew == second.oldToNew, "GraphLocalityOrderer produces deterministic inverse ordering");
	expect(first.newToOld == expected, "highest-degree and original-ID ties are deterministic while isolated nodes are last");
}

void testCompletePermutation() {
	const Graph graph = makeGraph(8, {
		{0, 4},
		{0, 5},
		{1, 5},
		{2, 6},
		{4, 1},
		{5, 2},
		{6, 0},
	});
	const GraphLocalityOrder order = GraphLocalityOrderer::order(
		8, graph.outgoingOffsets, graph.outgoingTargets, graph.incomingOffsets, graph.incomingSources);
	expect(isCompletePermutation(order, 8), "GraphLocalityOrder contains complete inverse permutations");
}

void testEdgeRemappingEquivalence() {
	const Graph graph = makeGraph(6, {
		{0, 4},
		{1, 5},
		{2, 4},
		{4, 1},
		{4, 3},
		{5, 2},
	});
	const GraphLocalityOrder order = GraphLocalityOrderer::order(
		graph.outgoingOffsets, graph.outgoingTargets, graph.incomingOffsets, graph.incomingSources);
	std::vector<std::pair<int32_t, int32_t>> remappedEdges;
	for (int32_t source = 0; source + 1 < static_cast<int32_t>(graph.outgoingOffsets.size()); ++source) {
		for (int32_t edge = graph.outgoingOffsets[source]; edge < graph.outgoingOffsets[source + 1]; ++edge) {
			remappedEdges.emplace_back(order.oldToNew[source], order.oldToNew[graph.outgoingTargets[edge]]);
		}
	}

	std::vector<std::pair<int32_t, int32_t>> restoredEdges;
	for (const std::pair<int32_t, int32_t> &edge : remappedEdges) {
		restoredEdges.emplace_back(order.newToOld[edge.first], order.newToOld[edge.second]);
	}
	std::sort(restoredEdges.begin(), restoredEdges.end());
	expect(restoredEdges == collectEdges(graph), "permutation remaps every directed edge without changing topology");
}

void testLocalityScoreImproves() {
	const Graph graph = makeSeparatedPairsGraph();
	const int32_t nodeCount = static_cast<int32_t>(graph.outgoingOffsets.size()) - 1;
	std::vector<int32_t> identity(nodeCount);
	std::iota(identity.begin(), identity.end(), 0);
	const GraphLocalityOrder order = GraphLocalityOrderer::order(
		graph.outgoingOffsets, graph.outgoingTargets, graph.incomingOffsets, graph.incomingSources);
	const int64_t identityScore = GraphLocalityOrderer::calculateLocalityScore(
		graph.outgoingOffsets, graph.outgoingTargets, identity);
	const int64_t reorderedScore = GraphLocalityOrderer::calculateLocalityScore(
		graph.outgoingOffsets, graph.outgoingTargets, order.oldToNew);
	expect(reorderedScore > identityScore, "reordered graph has higher five-node-window locality score than identity ordering");
}

} // namespace

int main() {
	testDeterministicOutput();
	testCompletePermutation();
	testEdgeRemappingEquivalence();
	testLocalityScoreImproves();
	return 0;
}
