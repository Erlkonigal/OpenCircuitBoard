#include "SimulationCore.hpp"

#include <cstdlib>
#include <iostream>
#include <string>
#include <vector>

namespace {

using ocb::CompileError;
using ocb::CompileInput;
using ocb::SimulationCore;
using ocb::ToolKind;

void expect(bool condition, const std::string &message) {
	if (!condition) {
		std::cerr << "FAILED: " << message << '\n';
		std::exit(1);
	}
}

CompileInput makeInput(int32_t width, int32_t height) {
	const int32_t count = width * height;
	CompileInput input;
	input.width = width;
	input.height = height;
	input.kinds.assign(count, static_cast<int32_t>(ToolKind::Empty));
	input.initialStates.assign(count, 0);
	input.clockHoldTicks.assign(count, 1);
	input.meshIds.assign(count, 0);
	return input;
}

int32_t cellIndex(const CompileInput &input, int32_t x, int32_t y) {
	return y * input.width + x;
}

void setKind(CompileInput &input, int32_t x, int32_t y, ToolKind kind) {
	input.kinds[cellIndex(input, x, y)] = static_cast<int32_t>(kind);
}

void setInitialState(CompileInput &input, int32_t x, int32_t y, int32_t state) {
	input.initialStates[cellIndex(input, x, y)] = state;
}

void expectState(const SimulationCore &core, const CompileInput &input, int32_t x, int32_t y, int32_t expected, const std::string &message) {
	const std::vector<int32_t> states = core.getStates();
	expect(states[cellIndex(input, x, y)] == expected, message);
}

void testReadWritePipeline() {
	CompileInput input = makeInput(5, 1);
	input.kinds = {
		static_cast<int32_t>(ToolKind::Latch),
		static_cast<int32_t>(ToolKind::Read),
		static_cast<int32_t>(ToolKind::Trace),
		static_cast<int32_t>(ToolKind::Write),
		static_cast<int32_t>(ToolKind::Buffer),
	};
	input.initialStates[0] = 1;
	SimulationCore core;
	CompileError error;
	expect(core.compile(input, error), "Read/Write pipeline compiles");
	expect(core.getStates()[2] == 1, "Read drives Trace during reset without an extra tick");
	expect(core.getStates()[4] == 0, "buffer starts low");
	core.advanceTick();
	expect(core.getStates()[2] == 1, "Read keeps its Trace output resolved");
	expect(core.getStates()[4] == 1, "Buffer updates after one logical tick from the settled Write input");
}

void testBatchAdvanceMatchesSingleTicks() {
	CompileInput input = makeInput(5, 1);
	setKind(input, 0, 0, ToolKind::Clock);
	setKind(input, 1, 0, ToolKind::Read);
	setKind(input, 2, 0, ToolKind::Trace);
	setKind(input, 3, 0, ToolKind::Write);
	setKind(input, 4, 0, ToolKind::Buffer);
	SimulationCore singleTickCore;
	SimulationCore batchCore;
	CompileError error;
	expect(singleTickCore.compile(input, error), "single-tick comparison circuit compiles");
	expect(batchCore.compile(input, error), "batch comparison circuit compiles");
	const std::vector<int32_t> initialStates = batchCore.getStates();

	for (int32_t tick = 0; tick < 3; ++tick) {
		singleTickCore.advanceTick();
	}
	const std::vector<int32_t> batchChanges = batchCore.advanceTicks(3);
	const std::vector<int32_t> batchStates = batchCore.getStates();
	expect(batchStates == singleTickCore.getStates(), "batch advance reaches the same state as repeated single ticks");

	std::vector<int32_t> expectedChanges;
	for (int32_t cell = 0; cell < static_cast<int32_t>(batchStates.size()); ++cell) {
		if (initialStates[cell] != batchStates[cell]) {
			expectedChanges.push_back(cell);
			expectedChanges.push_back(batchStates[cell]);
		}
	}
	expect(batchChanges == expectedChanges, "batch advance reports only the final delta");

	const std::vector<int32_t> statesBeforeNoOp = batchCore.getStates();
	expect(batchCore.advanceTicks(0).empty(), "zero-length batch returns no delta");
	expect(batchCore.advanceTicks(-1).empty(), "negative-length batch returns no delta");
	expect(batchCore.getStates() == statesBeforeNoOp, "non-positive batch does not advance state");
}

void testSilentAdvanceDrainsOnlyFinalChanges() {
	CompileInput input = makeInput(5, 1);
	setKind(input, 0, 0, ToolKind::Clock);
	setKind(input, 1, 0, ToolKind::Read);
	setKind(input, 2, 0, ToolKind::Trace);
	setKind(input, 3, 0, ToolKind::Write);
	setKind(input, 4, 0, ToolKind::Buffer);
	SimulationCore exactCore;
	SimulationCore silentCore;
	CompileError error;
	expect(exactCore.compile(input, error), "exact silent-delta comparison circuit compiles");
	expect(silentCore.compile(input, error), "silent-delta comparison circuit compiles");
	const std::vector<int32_t> expectedChanges = exactCore.advanceTicks(8);
	expect(silentCore.advanceTicksSilent(8).empty(), "silent advance never returns a delta");
	expect(silentCore.drainStateChanges() == expectedChanges, "drain returns the same final delta as exact batch advance");
	expect(silentCore.getStates() == exactCore.getStates(), "silent advance reaches the exact batch state");
	expect(silentCore.drainStateChanges().empty(), "second drain is empty after final delta is consumed");

	CompileInput clockInput = makeInput(1, 1);
	setKind(clockInput, 0, 0, ToolKind::Clock);
	SimulationCore clockCore;
	expect(clockCore.compile(clockInput, error), "standalone Clock compiles for final-delta filtering");
	clockCore.advanceTicksSilent(2);
	expect(clockCore.drainStateChanges().empty(), "silent collection omits a cell that returns to its reported state");
}

void testGraphOrderingPreservesExternalStatesAndDeltas() {
	CompileInput input = makeInput(8, 1);
	setKind(input, 0, 0, ToolKind::Clock);
	setKind(input, 1, 0, ToolKind::Read);
	setKind(input, 2, 0, ToolKind::Trace);
	setKind(input, 3, 0, ToolKind::Write);
	setKind(input, 4, 0, ToolKind::Read);
	setKind(input, 5, 0, ToolKind::Trace);
	setKind(input, 6, 0, ToolKind::Write);
	setKind(input, 7, 0, ToolKind::Buffer);
	SimulationCore baselineCore(false);
	SimulationCore orderedCore;
	CompileError error;
	expect(baselineCore.compile(input, error), "unreordered reference circuit compiles");
	expect(orderedCore.compile(input, error), "reordered reference circuit compiles");
	expect(orderedCore.getStates() == baselineCore.getStates(), "reordered compile preserves initial visible states");
	for (int32_t tick = 0; tick < 12; ++tick) {
		const std::vector<int32_t> baselineChanges = baselineCore.advanceTick();
		const std::vector<int32_t> orderedChanges = orderedCore.advanceTick();
		expect(orderedChanges == baselineChanges, "reordered execution preserves sorted external delta order");
		expect(orderedCore.getStates() == baselineCore.getStates(), "reordered execution preserves each tick's visible state");
	}
}

void testReadWriteZeroDelayPeerPorts() {
	CompileInput input = makeInput(8, 1);
	setKind(input, 0, 0, ToolKind::Clock);
	setKind(input, 1, 0, ToolKind::Read);
	setKind(input, 2, 0, ToolKind::Trace);
	setKind(input, 3, 0, ToolKind::Write);
	setKind(input, 4, 0, ToolKind::Read);
	setKind(input, 5, 0, ToolKind::Trace);
	setKind(input, 6, 0, ToolKind::Write);
	setKind(input, 7, 0, ToolKind::Buffer);
	SimulationCore core;
	CompileError error;
	expect(core.compile(input, error), "Read accepts Write as a source and Write accepts Read as a target");
	expectState(core, input, 2, 0, 0, "Clock connector path starts low");
	expectState(core, input, 5, 0, 0, "peer Read output starts low");

	core.advanceTick();
	expectState(core, input, 0, 0, 1, "Clock changes on the tick");
	expectState(core, input, 1, 0, 1, "first Read sees the new Clock state in the same tick");
	expectState(core, input, 2, 0, 1, "first Trace resolves in the same tick");
	expectState(core, input, 3, 0, 1, "first Write sees its Trace input in the same tick");
	expectState(core, input, 4, 0, 1, "peer Read sees its Write source in the same tick");
	expectState(core, input, 5, 0, 1, "peer Trace resolves in the same tick");
	expectState(core, input, 6, 0, 1, "second Write sees its Trace input in the same tick");
	expectState(core, input, 7, 0, 0, "Buffer retains one logical tick of latency");

	core.advanceTick();
	expectState(core, input, 2, 0, 0, "connector Trace follows the next Clock state without delay");
	expectState(core, input, 5, 0, 0, "peer connector Trace follows without delay");
	expectState(core, input, 7, 0, 1, "Buffer receives the prior tick's settled Write input");
}

void testWriteAcceptsReadInput() {
	CompileInput input = makeInput(4, 2);
	setKind(input, 0, 1, ToolKind::Clock);
	setKind(input, 1, 1, ToolKind::Read);
	setKind(input, 1, 0, ToolKind::Trace);
	setKind(input, 2, 1, ToolKind::Write);
	setKind(input, 3, 1, ToolKind::Buffer);
	SimulationCore core;
	CompileError error;
	expect(core.compile(input, error), "Write accepts a neighboring Read as its single input");
	expectState(core, input, 1, 0, 0, "Read output Trace starts low");

	core.advanceTick();
	expectState(core, input, 1, 1, 1, "Read sees the new Clock state in the same tick");
	expectState(core, input, 1, 0, 1, "Read still drives its Trace output in the same tick");
	expectState(core, input, 2, 1, 1, "Write sees its direct Read input in the same tick");
	expectState(core, input, 3, 1, 0, "Buffer retains logical latency after direct Read input");

	core.advanceTick();
	expectState(core, input, 3, 1, 1, "Buffer receives the prior tick's direct Read input");
}

void testAlternatingReadWriteChain() {
	CompileInput input = makeInput(6, 1);
	setKind(input, 0, 0, ToolKind::Latch);
	setInitialState(input, 0, 0, 1);
	setKind(input, 1, 0, ToolKind::Read);
	setKind(input, 2, 0, ToolKind::Write);
	setKind(input, 3, 0, ToolKind::Read);
	setKind(input, 4, 0, ToolKind::Write);
	setKind(input, 5, 0, ToolKind::Led);
	SimulationCore core;
	CompileError error;
	expect(core.compile(input, error), "alternating Latch-Read-Write-Read-Write-LED chain compiles");
	expectState(core, input, 1, 0, 1, "first Read resolves from Latch during reset");
	expectState(core, input, 2, 0, 1, "first Write resolves from first Read during reset");
	expectState(core, input, 3, 0, 1, "second Read resolves from first Write during reset");
	expectState(core, input, 4, 0, 1, "second Write resolves from second Read during reset");
	expectState(core, input, 5, 0, 0, "LED preserves its logical tick delay");

	core.advanceTick();
	expectState(core, input, 1, 0, 1, "first Read remains resolved after one tick");
	expectState(core, input, 2, 0, 1, "first Write remains resolved after one tick");
	expectState(core, input, 3, 0, 1, "second Read remains resolved after one tick");
	expectState(core, input, 4, 0, 1, "second Write remains resolved after one tick");
	expectState(core, input, 5, 0, 1, "LED updates after one logical tick");
}

void testCrossIsolation() {
	CompileInput input = makeInput(5, 1);
	setKind(input, 0, 0, ToolKind::Latch);
	setInitialState(input, 0, 0, 1);
	setKind(input, 1, 0, ToolKind::Read);
	setKind(input, 2, 0, ToolKind::Trace);
	setKind(input, 3, 0, ToolKind::Cross);
	setKind(input, 4, 0, ToolKind::TraceRed);
	SimulationCore core;
	CompileError error;
	expect(core.compile(input, error), "Cross ignores incompatible conductor colors");
	core.advanceTick();
	expectState(core, input, 2, 0, 1, "Cross input Trace is powered");
	expectState(core, input, 3, 0, 0, "Cross does not conduct between mismatched colors");
	expectState(core, input, 4, 0, 0, "mismatched Cross output stays isolated");
}

void testCrossChannelIsolation() {
	CompileInput input = makeInput(5, 3);
	setKind(input, 0, 1, ToolKind::Latch);
	setInitialState(input, 0, 1, 1);
	setKind(input, 1, 1, ToolKind::Read);
	setKind(input, 2, 1, ToolKind::Trace);
	setKind(input, 3, 1, ToolKind::Cross);
	setKind(input, 4, 1, ToolKind::Trace);
	setKind(input, 3, 0, ToolKind::TraceRed);
	setKind(input, 3, 2, ToolKind::TraceRed);
	SimulationCore core;
	CompileError error;
	expect(core.compile(input, error), "Cross with two channels compiles");
	core.advanceTick();
	expectState(core, input, 2, 1, 1, "Cross horizontal input is powered");
	expectState(core, input, 4, 1, 1, "Cross horizontal output is powered");
	expectState(core, input, 3, 0, 0, "Cross keeps the vertical channel isolated");
	expectState(core, input, 3, 2, 0, "Cross keeps both vertical endpoints isolated");
}

void testMeshIgnoresIncompatibleNeighbors() {
	CompileInput input = makeInput(5, 2);
	setKind(input, 0, 1, ToolKind::Latch);
	setInitialState(input, 0, 1, 1);
	setKind(input, 1, 1, ToolKind::Read);
	setKind(input, 2, 1, ToolKind::TraceRed);
	setKind(input, 3, 1, ToolKind::Mesh);
	input.meshIds[cellIndex(input, 3, 1)] = 1;
	setKind(input, 4, 1, ToolKind::TraceBlue);
	setKind(input, 3, 0, ToolKind::Buffer);
	SimulationCore core;
	CompileError error;
	expect(core.compile(input, error), "Mesh ignores incompatible Trace colors and non-Trace neighbors");
	core.advanceTick();
	expectState(core, input, 2, 1, 1, "selected Mesh Trace color is powered");
	expectState(core, input, 3, 1, 1, "Mesh follows the first compatible Trace color in direction order");
	expectState(core, input, 4, 1, 0, "incompatible Mesh Trace color remains isolated");
}

void testCompileErrorCoordinates() {
	CompileInput input = makeInput(1, 1);
	input.kinds[0] = static_cast<int32_t>(ToolKind::Read);
	SimulationCore core;
	CompileError error;
	expect(!core.compile(input, error), "unconnected Read is rejected");
	expect(error.errorX == 0 && error.errorY == 0, "compile diagnostic keeps the failing cell coordinates");
}

void testRemoteMeshConnectivity() {
	CompileInput input = makeInput(9, 1);
	setKind(input, 0, 0, ToolKind::Latch);
	setInitialState(input, 0, 0, 1);
	setKind(input, 1, 0, ToolKind::Read);
	setKind(input, 2, 0, ToolKind::Trace);
	setKind(input, 3, 0, ToolKind::Mesh);
	input.meshIds[3] = 7;
	setKind(input, 5, 0, ToolKind::Mesh);
	input.meshIds[5] = 7;
	setKind(input, 6, 0, ToolKind::Trace);
	setKind(input, 7, 0, ToolKind::Write);
	setKind(input, 8, 0, ToolKind::Led);
	SimulationCore core;
	CompileError error;
	expect(core.compile(input, error), "same-ID Mesh endpoints compile");
	expectState(core, input, 3, 0, 1, "source Mesh endpoint resolves during reset");
	expectState(core, input, 5, 0, 1, "remote same-ID Mesh endpoint resolves during reset");
	expectState(core, input, 6, 0, 1, "remote Mesh drives its attached Trace during reset");
	core.advanceTick();
	expectState(core, input, 8, 0, 1, "LED receives the settled remote Write input after one logical tick");
}

void testRemoteMeshIsolation() {
	CompileInput input = makeInput(9, 1);
	setKind(input, 0, 0, ToolKind::Latch);
	setInitialState(input, 0, 0, 1);
	setKind(input, 1, 0, ToolKind::Read);
	setKind(input, 2, 0, ToolKind::Trace);
	setKind(input, 3, 0, ToolKind::Mesh);
	input.meshIds[3] = 7;
	setKind(input, 5, 0, ToolKind::Mesh);
	input.meshIds[5] = 8;
	setKind(input, 6, 0, ToolKind::Trace);
	setKind(input, 7, 0, ToolKind::Write);
	setKind(input, 8, 0, ToolKind::Led);
	SimulationCore core;
	CompileError error;
	expect(core.compile(input, error), "different-ID Mesh endpoints compile");
	core.advanceTick();
	expectState(core, input, 3, 0, 1, "source Mesh endpoint remains powered");
	expectState(core, input, 5, 0, 0, "different-ID Mesh endpoint remains isolated");
	expectState(core, input, 6, 0, 0, "different-ID Mesh does not drive a remote Trace");
	core.advanceTick();
	expectState(core, input, 8, 0, 0, "isolated Mesh network does not reach Write");
}

void testBusIsLocalOnly() {
	CompileInput input = makeInput(9, 1);
	setKind(input, 0, 0, ToolKind::Latch);
	setInitialState(input, 0, 0, 1);
	setKind(input, 1, 0, ToolKind::Read);
	setKind(input, 2, 0, ToolKind::Trace);
	setKind(input, 3, 0, ToolKind::BusYellow);
	setKind(input, 5, 0, ToolKind::BusYellow);
	setKind(input, 6, 0, ToolKind::Trace);
	setKind(input, 7, 0, ToolKind::Write);
	setKind(input, 8, 0, ToolKind::Led);
	SimulationCore core;
	CompileError error;
	expect(core.compile(input, error), "separate same-color Bus groups compile");
	core.advanceTick();
	expectState(core, input, 3, 0, 1, "local Bus group conducts the attached Trace");
	expectState(core, input, 5, 0, 0, "separate Bus group is not a remote connection");
	expectState(core, input, 6, 0, 0, "separate Bus does not drive its Trace");
	core.advanceTick();
	expectState(core, input, 8, 0, 0, "separate Bus cannot drive Write remotely");
}

void testReadWriteIgnoreUnrelatedNeighbors() {
	CompileInput readInput = makeInput(3, 2);
	setKind(readInput, 0, 1, ToolKind::Latch);
	setInitialState(readInput, 0, 1, 1);
	setKind(readInput, 1, 1, ToolKind::Read);
	setKind(readInput, 2, 1, ToolKind::Trace);
	setKind(readInput, 1, 0, ToolKind::BusYellow);
	SimulationCore readCore;
	CompileError error;
	expect(readCore.compile(readInput, error), "Read ignores unrelated adjacent components");
	expectState(readCore, readInput, 2, 1, 1, "Read still drives a valid Trace output during reset");

	CompileInput writeInput = makeInput(4, 2);
	setKind(writeInput, 0, 1, ToolKind::Latch);
	setInitialState(writeInput, 0, 1, 1);
	setKind(writeInput, 1, 1, ToolKind::Read);
	setKind(writeInput, 2, 1, ToolKind::Write);
	setKind(writeInput, 3, 1, ToolKind::Led);
	setKind(writeInput, 1, 0, ToolKind::BusYellow);
	setKind(writeInput, 2, 0, ToolKind::Clock);
	SimulationCore writeCore;
	expect(writeCore.compile(writeInput, error), "direct Read/Write chain ignores unrelated adjacent components");
	expectState(writeCore, writeInput, 1, 1, 1, "Read resolves directly from its source without a Trace");
	expectState(writeCore, writeInput, 2, 1, 1, "Write resolves directly from its Read input without a Trace");
	writeCore.advanceTick();
	expectState(writeCore, writeInput, 3, 1, 1, "direct Write still drives a valid target after one logical tick");
}

void testReadWriteRequireValidPorts() {
	CompileInput directInput = makeInput(4, 1);
	setKind(directInput, 0, 0, ToolKind::Latch);
	setInitialState(directInput, 0, 0, 1);
	setKind(directInput, 1, 0, ToolKind::Read);
	setKind(directInput, 2, 0, ToolKind::Write);
	setKind(directInput, 3, 0, ToolKind::Led);
	SimulationCore directCore;
	CompileError error;
	expect(directCore.compile(directInput, error), "Latch-Read-Write-LED compiles without a literal Trace");
	expectState(directCore, directInput, 1, 0, 1, "direct Read starts high from its Latch source");
	expectState(directCore, directInput, 2, 0, 1, "direct Write starts high from its Read source");
	expectState(directCore, directInput, 3, 0, 0, "LED keeps its logical tick delay");
	directCore.advanceTick();
	expectState(directCore, directInput, 3, 0, 1, "direct Write drives LED after one logical tick");

	CompileInput readInput = makeInput(2, 1);
	setKind(readInput, 0, 0, ToolKind::Latch);
	setKind(readInput, 1, 0, ToolKind::Read);
	SimulationCore readCore;
	expect(!readCore.compile(readInput, error), "Read still requires an outgoing connection");

	CompileInput writeInput = makeInput(3, 1);
	setKind(writeInput, 1, 0, ToolKind::Write);
	setKind(writeInput, 2, 0, ToolKind::Led);
	SimulationCore writeCore;
	expect(!writeCore.compile(writeInput, error), "Write still requires one incoming connection");

	CompileInput writeWithoutTarget = makeInput(3, 1);
	setKind(writeWithoutTarget, 0, 0, ToolKind::Trace);
	setKind(writeWithoutTarget, 1, 0, ToolKind::Write);
	setKind(writeWithoutTarget, 2, 0, ToolKind::BusYellow);
	SimulationCore writeWithoutTargetCore;
	expect(!writeWithoutTargetCore.compile(writeWithoutTarget, error), "Write still requires a valid target");
	expect(error.errorReason == "write_requires_target", "Write keeps its missing target diagnostic");

	CompileInput writeWithTwoTraceSides = makeInput(3, 3);
	setKind(writeWithTwoTraceSides, 0, 1, ToolKind::Trace);
	setKind(writeWithTwoTraceSides, 1, 1, ToolKind::Write);
	setKind(writeWithTwoTraceSides, 2, 1, ToolKind::Trace);
	setKind(writeWithTwoTraceSides, 1, 0, ToolKind::Led);
	setKind(writeWithTwoTraceSides, 0, 2, ToolKind::Trace);
	setKind(writeWithTwoTraceSides, 1, 2, ToolKind::Trace);
	setKind(writeWithTwoTraceSides, 2, 2, ToolKind::Trace);
	SimulationCore writeWithTwoTraceSidesCore;
	expect(!writeWithTwoTraceSidesCore.compile(writeWithTwoTraceSides, error), "Write rejects two incoming Trace sides on one network");

	CompileInput ambiguousRead = makeInput(3, 2);
	setKind(ambiguousRead, 0, 0, ToolKind::Trace);
	setKind(ambiguousRead, 1, 0, ToolKind::Write);
	setKind(ambiguousRead, 0, 1, ToolKind::Latch);
	setKind(ambiguousRead, 1, 1, ToolKind::Read);
	setKind(ambiguousRead, 2, 1, ToolKind::Trace);
	SimulationCore ambiguousReadCore;
	expect(!ambiguousReadCore.compile(ambiguousRead, error), "Read rejects simultaneous device and Write sources");
	expect(error.errorReason == "read_requires_one_source", "Read reports its ambiguous source diagnostic");
}

void expectMultiWriteAllowed(ToolKind kind, const std::string &name) {
	CompileInput input = makeInput(5, 1);
	setKind(input, 0, 0, ToolKind::Trace);
	setKind(input, 1, 0, ToolKind::Write);
	setKind(input, 2, 0, kind);
	setKind(input, 3, 0, ToolKind::Write);
	setKind(input, 4, 0, ToolKind::Trace);
	SimulationCore core;
	CompileError error;
	expect(core.compile(input, error), name + " accepts multiple Write blocks");
}

void testWriteMultiplicity() {
	expectMultiWriteAllowed(ToolKind::And, "AND");
	expectMultiWriteAllowed(ToolKind::Nand, "NAND");
	expectMultiWriteAllowed(ToolKind::Or, "OR");
	expectMultiWriteAllowed(ToolKind::Nor, "NOR");
	expectMultiWriteAllowed(ToolKind::Xor, "XOR");
	expectMultiWriteAllowed(ToolKind::Xnor, "XNOR");

	CompileInput input = makeInput(5, 1);
	setKind(input, 0, 0, ToolKind::Trace);
	setKind(input, 1, 0, ToolKind::Write);
	setKind(input, 2, 0, ToolKind::Buffer);
	setKind(input, 3, 0, ToolKind::Write);
	setKind(input, 4, 0, ToolKind::Trace);
	SimulationCore core;
	CompileError error;
	expect(!core.compile(input, error), "Buffer rejects multiple Write blocks");
	expect(error.errorReason == "multiple_write_inputs", "single-write target returns its diagnostic");
}

void testLatchInitialStateVariantsRemainSeparate() {
	CompileInput input = makeInput(2, 1);
	setKind(input, 0, 0, ToolKind::Latch);
	setKind(input, 1, 0, ToolKind::Latch);
	setInitialState(input, 0, 0, 1);
	setInitialState(input, 1, 0, 0);
	SimulationCore core;
	CompileError error;
	std::vector<int32_t> changes;
	std::string toggleError;
	expect(core.compile(input, error), "adjacent Latch state variants compile as separate components");
	expectState(core, input, 0, 0, 1, "On Latch keeps its design state");
	expectState(core, input, 1, 0, 0, "Off Latch keeps its design state");
	expect(core.toggleLatch(0, changes, toggleError), "On Latch toggles independently");
	expect(changes == std::vector<int32_t>({0, 0}), "On Latch toggle does not change adjacent Off Latch");
	expectState(core, input, 1, 0, 0, "adjacent Off Latch remains unchanged");
	expect(core.toggleLatch(1, changes, toggleError), "Off Latch toggles independently");
	expect(changes == std::vector<int32_t>({1, 1}), "Off Latch toggle does not change adjacent Latch");
}

void testLatchToggle() {
	CompileInput input = makeInput(5, 1);
	setKind(input, 0, 0, ToolKind::Latch);
	setKind(input, 1, 0, ToolKind::Latch);
	setKind(input, 2, 0, ToolKind::Read);
	setKind(input, 3, 0, ToolKind::Trace);
	setInitialState(input, 0, 0, 0);
	setInitialState(input, 1, 0, 0);
	SimulationCore core;
	CompileError error;
	std::vector<int32_t> changes;
	std::string toggleError;
	expect(!core.toggleLatch(0, changes, toggleError), "uncompiled Latch cannot be toggled");
	expect(toggleError == "simulation_not_compiled", "uncompiled Latch returns its diagnostic");
	expect(core.compile(input, error), "merged Latches compile for click toggling");

	expect(!core.toggleLatch(-1, changes, toggleError), "negative cell index is rejected");
	expect(toggleError == "cell_out_of_bounds", "invalid cell index returns its diagnostic");
	expect(!core.toggleLatch(2, changes, toggleError), "Read block cannot be toggled as a Latch");
	expect(toggleError == "not_latch", "non-Latch cell returns its diagnostic");

	expect(core.toggleLatch(1, changes, toggleError), "any cell in a merged Latch toggles its component");
	expect(changes == std::vector<int32_t>({0, 1, 1, 1, 2, 1, 3, 1}), "Latch toggle immediately resolves connected Read and Trace states");
	expectState(core, input, 0, 0, 1, "first merged Latch is on after toggle");
	expectState(core, input, 1, 0, 1, "clicked merged Latch is on after toggle");
	expectState(core, input, 3, 0, 1, "Latch toggle immediately updates connected Trace output");

	const std::vector<uint8_t> snapshot = core.captureState();
	core.advanceTick();
	expectState(core, input, 3, 0, 1, "toggled Latch keeps its resolved Trace output across ticks");
	std::string restoreError;
	expect(core.restoreState(snapshot, restoreError), "snapshot restores toggled Latch state");
	expectState(core, input, 0, 0, 1, "restored snapshot keeps toggled Latch state");
	expectState(core, input, 3, 0, 1, "restored snapshot keeps resolved Trace state");

	expect(core.toggleLatch(0, changes, toggleError), "toggled Latch can be toggled off again");
	expect(changes == std::vector<int32_t>({0, 0, 1, 0, 2, 0, 3, 0}), "second toggle immediately clears connected Trace state");
	core.reset();
	expectState(core, input, 0, 0, 0, "reset restores the Latch design state");
}

void testZeroWriteGateIdentities() {
	CompileInput input = makeInput(9, 1);
	setKind(input, 0, 0, ToolKind::Buffer);
	setKind(input, 1, 0, ToolKind::And);
	setKind(input, 2, 0, ToolKind::Or);
	setKind(input, 3, 0, ToolKind::Xor);
	setKind(input, 4, 0, ToolKind::Not);
	setKind(input, 5, 0, ToolKind::Nand);
	setKind(input, 6, 0, ToolKind::Nor);
	setKind(input, 7, 0, ToolKind::Xnor);
	setKind(input, 8, 0, ToolKind::Led);
	SimulationCore core;
	CompileError error;
	expect(core.compile(input, error), "zero-write gates compile");
	const std::vector<int32_t> expected = {0, 1, 0, 0, 1, 0, 1, 1, 0};
	expect(core.getStates() == expected, "zero-write gates use their Boolean identities");
}

void testSnapshotRestore() {
	CompileInput input = makeInput(4, 2);
	setKind(input, 0, 1, ToolKind::Clock);
	setKind(input, 1, 1, ToolKind::Read);
	setKind(input, 1, 0, ToolKind::Trace);
	setKind(input, 2, 1, ToolKind::Write);
	setKind(input, 3, 1, ToolKind::Buffer);
	SimulationCore core;
	CompileError error;
	expect(core.compile(input, error), "direct Read-to-Write chain compiles");
	core.advanceTick();
	const std::vector<int32_t> expectedStates = core.getStates();
	expectState(core, input, 1, 0, 1, "snapshot captures the Read output Trace");
	expectState(core, input, 2, 1, 1, "snapshot captures the direct Read-to-Write signal");
	expectState(core, input, 3, 1, 0, "logical target has not advanced at the snapshot tick");
	const std::vector<uint8_t> snapshot = core.captureState();
	expect(snapshot.size() == 44, "snapshot keeps the v1 header and original component/network payload layout");
	core.advanceTick();
	expect(core.getStates() != expectedStates, "second tick changes the direct connector chain");
	std::string restoreError;
	expect(core.restoreState(snapshot, restoreError), "snapshot restores onto the same topology");
	expect(core.getStates() == expectedStates, "snapshot restores every visible state");
	core.reset();
	expectState(core, input, 1, 0, 0, "reset clears the Read output Trace");
	expectState(core, input, 2, 1, 0, "reset clears the direct Read-to-Write signal");
	expectState(core, input, 3, 1, 0, "reset clears the logical target");
}

} // namespace

int main() {
	testReadWritePipeline();
	testBatchAdvanceMatchesSingleTicks();
	testSilentAdvanceDrainsOnlyFinalChanges();
	testGraphOrderingPreservesExternalStatesAndDeltas();
	testReadWriteZeroDelayPeerPorts();
	testWriteAcceptsReadInput();
	testAlternatingReadWriteChain();
	testCrossIsolation();
	testCrossChannelIsolation();
	testMeshIgnoresIncompatibleNeighbors();
	testCompileErrorCoordinates();
	testRemoteMeshConnectivity();
	testRemoteMeshIsolation();
	testBusIsLocalOnly();
	testReadWriteIgnoreUnrelatedNeighbors();
	testReadWriteRequireValidPorts();
	testWriteMultiplicity();
	testLatchInitialStateVariantsRemainSeparate();
	testLatchToggle();
	testZeroWriteGateIdentities();
	testSnapshotRestore();
	return 0;
}
