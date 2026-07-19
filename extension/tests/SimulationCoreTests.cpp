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

int32_t countChangesForCell(const std::vector<int32_t> &changes, int32_t cell) {
	int32_t count = 0;
	for (size_t offset = 0; offset + 1U < changes.size(); offset += 2U) {
		if (changes[offset] == cell) {
			++count;
		}
	}
	return count;
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

void testConnectorQueueEventEncoding() {
	CompileInput input = makeInput(5, 1);
	setKind(input, 0, 0, ToolKind::Clock);
	setKind(input, 1, 0, ToolKind::Read);
	setKind(input, 2, 0, ToolKind::Trace);
	setKind(input, 3, 0, ToolKind::Write);
	setKind(input, 4, 0, ToolKind::Buffer);
	input.clockHoldTicks[0] = 2;
	SimulationCore core;
	CompileError error;
	expect(core.compile(input, error), "Clock pipeline compiles for connector event encoding");
	expect(core.advanceTick().empty(), "idle tick does not replay a drained event");
	expect(
			core.advanceTick() == std::vector<int32_t>({0, 1, 1, 1, 2, 1, 3, 1}),
			"node zero high event propagates through the connector queue");
	expect(core.advanceTick() == std::vector<int32_t>({4, 1}), "scheduled Buffer event is retained for the next tick");
	expect(
			core.advanceTick() == std::vector<int32_t>({0, 0, 1, 0, 2, 0, 3, 0}),
			"node zero low event propagates through the connector queue");
	expect(core.advanceTick() == std::vector<int32_t>({4, 0}), "drained low event is not replayed");
}

void testGateAndClockCommitBeforeDrain() {
	CompileInput input = makeInput(5, 1);
	setKind(input, 0, 0, ToolKind::Clock);
	setKind(input, 1, 0, ToolKind::Read);
	setKind(input, 2, 0, ToolKind::Trace);
	setKind(input, 3, 0, ToolKind::Write);
	setKind(input, 4, 0, ToolKind::Buffer);
	SimulationCore core;
	CompileError error;
	expect(core.compile(input, error), "Clock and Buffer pipeline compiles for staged commit");
	expect(
			core.advanceTick() == std::vector<int32_t>({0, 1, 1, 1, 2, 1, 3, 1}),
			"Clock propagates before its scheduled Buffer update");
	expect(
			core.advanceTick() == std::vector<int32_t>({0, 0, 1, 0, 2, 0, 3, 0, 4, 1}),
			"scheduled Buffer and Clock transitions commit before connector propagation");
	expect(
			core.advanceTick() == std::vector<int32_t>({0, 1, 1, 1, 2, 1, 3, 1, 4, 0}),
			"subsequent simultaneous transitions preserve the tick barrier");
}

void testInputDrivenLatchPreservesNormalFlushDelay() {
	CompileInput input = makeInput(5, 1);
	setKind(input, 0, 0, ToolKind::Clock);
	setKind(input, 1, 0, ToolKind::Read);
	setKind(input, 2, 0, ToolKind::Trace);
	setKind(input, 3, 0, ToolKind::Write);
	setKind(input, 4, 0, ToolKind::Latch);
	SimulationCore core;
	CompileError error;
	expect(core.compile(input, error), "input-driven Latch pipeline compiles");
	expectState(core, input, 4, 0, 0, "input-driven Latch starts low");
	core.advanceTick();
	expectState(core, input, 4, 0, 0, "input-driven Latch remains deferred after the Clock rises");
	core.advanceTick();
	expectState(core, input, 4, 0, 1, "input-driven Latch commits the prior rising Write edge");
	core.advanceTick();
	expectState(core, input, 4, 0, 1, "input-driven Latch ignores the falling Write edge");
	core.advanceTick();
	expectState(core, input, 4, 0, 0, "input-driven Latch commits the next rising Write edge");
}

void testInputDrivenLatchIgnoresStaticWriteState() {
	CompileInput input = makeInput(3, 1);
	setKind(input, 0, 0, ToolKind::Latch);
	setInitialState(input, 0, 0, true);
	setKind(input, 1, 0, ToolKind::Write);
	setKind(input, 2, 0, ToolKind::Trace);
	SimulationCore core;
	CompileError error;
	expect(core.compile(input, error), "static-low Write to Latch compiles");
	expectState(core, input, 0, 0, 1, "Latch preserves its configured state before the first tick");
	core.advanceTick();
	expectState(core, input, 0, 0, 1, "Latch ignores a static low Write state");

	CompileInput highInput = makeInput(5, 1);
	setKind(highInput, 0, 0, ToolKind::Latch);
	setInitialState(highInput, 0, 0, true);
	setKind(highInput, 1, 0, ToolKind::Read);
	setKind(highInput, 2, 0, ToolKind::Trace);
	setKind(highInput, 3, 0, ToolKind::Write);
	setKind(highInput, 4, 0, ToolKind::Latch);
	SimulationCore highCore;
	expect(highCore.compile(highInput, error), "static-high Write to Latch compiles");
	expectState(highCore, highInput, 4, 0, 0, "Latch preserves its configured state with a static high Write");
	highCore.advanceTick();
	expectState(highCore, highInput, 4, 0, 0, "Latch ignores a static high Write state");
}

void testMixedDeferredAndNormalGateFrontiers() {
	CompileInput input = makeInput(5, 3);
	setKind(input, 0, 0, ToolKind::Clock);
	setKind(input, 1, 0, ToolKind::Read);
	setKind(input, 2, 0, ToolKind::Trace);
	setKind(input, 3, 0, ToolKind::Write);
	setKind(input, 4, 0, ToolKind::Buffer);
	setKind(input, 0, 2, ToolKind::Clock);
	setKind(input, 1, 2, ToolKind::Read);
	setKind(input, 2, 2, ToolKind::Trace);
	setKind(input, 3, 2, ToolKind::Write);
	setKind(input, 4, 2, ToolKind::Latch);
	SimulationCore core;
	CompileError error;
	expect(core.compile(input, error), "mixed normal and deferred frontier circuit compiles");
	core.advanceTick();
	expectState(core, input, 4, 0, 0, "Buffer stays deferred after the source clock rises");
	expectState(core, input, 4, 2, 0, "Latch stays deferred after the source clock rises");
	core.advanceTick();
	expectState(core, input, 4, 0, 1, "Buffer commits alongside an input-driven Latch");
	expectState(core, input, 4, 2, 1, "Latch commits alongside a normal Buffer");
	core.advanceTick();
	expectState(core, input, 4, 0, 0, "Buffer commits the following low input");
	expectState(core, input, 4, 2, 1, "Latch ignores the following low input");
}

void testSnapshotRestoresPendingLatchTransition() {
	CompileInput input = makeInput(5, 1);
	setKind(input, 0, 0, ToolKind::Clock);
	setKind(input, 1, 0, ToolKind::Read);
	setKind(input, 2, 0, ToolKind::Trace);
	setKind(input, 3, 0, ToolKind::Write);
	setKind(input, 4, 0, ToolKind::Latch);
	SimulationCore core;
	CompileError error;
	expect(core.compile(input, error), "snapshot Latch pipeline compiles");
	core.advanceTick();
	expectState(core, input, 4, 0, 0, "Latch remains low while its rising edge is queued");
	const std::vector<uint8_t> snapshot = core.captureState();
	core.advanceTick();
	expectState(core, input, 4, 0, 1, "Latch commits the queued rising-edge transition");
	std::string restoreError;
	expect(core.restoreState(snapshot, restoreError), "Latch snapshot restores");
	core.advanceTick();
	expectState(core, input, 4, 0, 1, "restored Latch commits its queued rising-edge transition");
}

void testTransparentConnectorSnapshotRestoresPendingGate() {
	CompileInput input = makeInput(5, 1);
	setKind(input, 0, 0, ToolKind::Clock);
	setKind(input, 1, 0, ToolKind::Read);
	setKind(input, 2, 0, ToolKind::Trace);
	setKind(input, 3, 0, ToolKind::Write);
	setKind(input, 4, 0, ToolKind::Buffer);
	SimulationCore core;
	CompileError error;
	expect(core.compile(input, error), "transparent connector snapshot fixture compiles");
	core.advanceTick();
	expectState(core, input, 2, 0, 1, "transparent connector Trace follows the Clock state");
	expectState(core, input, 4, 0, 0, "transparent connector Buffer remains queued before its tick");
	const std::vector<uint8_t> snapshot = core.captureState();
	core.advanceTick();
	expectState(core, input, 4, 0, 1, "transparent connector Buffer commits before restore");
	std::string restoreError;
	expect(core.restoreState(snapshot, restoreError), "transparent connector snapshot restores");
	core.advanceTick();
	expectState(core, input, 4, 0, 1, "transparent connector snapshot restores the pending Buffer state");
}

void testDirectComponentTargetsPreserveTickBarrier() {
	CompileInput input = makeInput(9, 1);
	setKind(input, 0, 0, ToolKind::Clock);
	setKind(input, 1, 0, ToolKind::Read);
	setKind(input, 2, 0, ToolKind::Trace);
	setKind(input, 3, 0, ToolKind::Write);
	setKind(input, 4, 0, ToolKind::Buffer);
	setKind(input, 5, 0, ToolKind::Read);
	setKind(input, 6, 0, ToolKind::Trace);
	setKind(input, 7, 0, ToolKind::Write);
	setKind(input, 8, 0, ToolKind::Buffer);
	SimulationCore core;
	CompileError error;
	expect(core.compile(input, error), "two-stage Buffer pipeline compiles for direct target scheduling");
	core.advanceTick();
	expectState(core, input, 4, 0, 0, "first Buffer remains delayed after the Clock transition");
	core.advanceTick();
	expectState(core, input, 4, 0, 1, "first Buffer receives the prior Clock state");
	expectState(core, input, 8, 0, 0, "second Buffer remains delayed behind the first Buffer");
	core.advanceTick();
	expectState(core, input, 4, 0, 0, "first Buffer sees the next Clock state");
	expectState(core, input, 8, 0, 1, "second Buffer evaluates the first Buffer's prior state");
}

void testEncodedDirectComponentTargetPreservesDeferredState() {
	CompileInput input = makeInput(8, 1);
	setKind(input, 0, 0, ToolKind::Buffer);
	setKind(input, 1, 0, ToolKind::Write);
	setKind(input, 2, 0, ToolKind::Trace);
	setKind(input, 3, 0, ToolKind::Read);
	setKind(input, 4, 0, ToolKind::Write);
	setKind(input, 5, 0, ToolKind::Trace);
	setKind(input, 6, 0, ToolKind::Read);
	setKind(input, 7, 0, ToolKind::Latch);
	SimulationCore core;
	CompileError error;
	std::vector<int32_t> changes;
	std::string toggleError;
	expect(core.compile(input, error), "reverse direct-target pipeline compiles");
	expect(core.toggleLatch(cellIndex(input, 7, 0), changes, toggleError), "source Latch toggles high");
	expectState(core, input, 5, 0, 1, "connector source resolves before its deferred Buffer target");
	expectState(core, input, 0, 0, 0, "component zero remains deferred after direct connector propagation");

	const std::vector<uint8_t> snapshot = core.captureState();
	core.reset();
	expectState(core, input, 7, 0, 0, "reset clears the direct-target Latch source");
	expectState(core, input, 5, 0, 0, "reset clears the direct connector source");
	expectState(core, input, 0, 0, 0, "reset keeps component zero low");
	std::string restoreError;
	expect(core.restoreState(snapshot, restoreError), "direct-target snapshot restores");
	expectState(core, input, 5, 0, 1, "snapshot restores the direct connector source");
	expectState(core, input, 0, 0, 0, "snapshot preserves the pending Buffer delay");

	core.advanceTick();
	expectState(core, input, 0, 0, 1, "component zero commits on the following tick");
	expect(core.toggleLatch(cellIndex(input, 7, 0), changes, toggleError), "source Latch toggles low");
	expectState(core, input, 5, 0, 0, "direct connector source clears immediately");
	expectState(core, input, 0, 0, 1, "component zero keeps its prior state until the next tick");
	core.advanceTick();
	expectState(core, input, 0, 0, 0, "component zero commits the later low state");
}

void testSharedConnectorMultipleSourceDelta() {
	CompileInput input = makeInput(7, 3);
	setKind(input, 0, 0, ToolKind::Clock);
	setKind(input, 1, 0, ToolKind::Read);
	for (int32_t x = 2; x <= 4; ++x) {
		setKind(input, x, 0, ToolKind::Trace);
	}
	setKind(input, 5, 0, ToolKind::Read);
	setKind(input, 6, 0, ToolKind::Clock);
	setKind(input, 3, 1, ToolKind::Write);
	setKind(input, 3, 2, ToolKind::Buffer);
	SimulationCore core;
	CompileError error;
	expect(core.compile(input, error), "shared connector multiple-source circuit compiles");
	expect(
			core.advanceTick() == std::vector<int32_t>({0, 1, 1, 1, 2, 1, 3, 1, 4, 1, 5, 1, 6, 1, 10, 1}),
			"two high source transitions produce one high connector output");
	expect(
			core.advanceTick() == std::vector<int32_t>({0, 0, 1, 0, 2, 0, 3, 0, 4, 0, 5, 0, 6, 0, 10, 0, 17, 1}),
			"two low source transitions produce one low connector output");
	expect(
			core.advanceTick() == std::vector<int32_t>({0, 1, 1, 1, 2, 1, 3, 1, 4, 1, 5, 1, 6, 1, 10, 1, 17, 0}),
			"shared connector output delta preserves the delayed Buffer input count");
}

void testOppositeClockFanoutPreservesResolvedConnector() {
	constexpr int32_t FanoutCount = 8;
	constexpr int32_t Width = FanoutCount * 2 + 3;
	CompileInput input = makeInput(Width, 3);
	setKind(input, 0, 0, ToolKind::Clock);
	input.clockHoldTicks[cellIndex(input, 0, 0)] = 1;
	setKind(input, 1, 0, ToolKind::Read);
	for (int32_t x = 2; x <= FanoutCount * 2; ++x) {
		setKind(input, x, 0, ToolKind::Trace);
	}
	setKind(input, Width - 2, 0, ToolKind::Read);
	setKind(input, Width - 1, 0, ToolKind::Clock);
	input.clockHoldTicks[cellIndex(input, Width - 1, 0)] = 2;
	for (int32_t branch = 0; branch < FanoutCount; ++branch) {
		const int32_t x = 2 + branch * 2;
		setKind(input, x, 1, ToolKind::Write);
		setKind(input, x, 2, ToolKind::Buffer);
	}
	SimulationCore core;
	CompileError error;
	expect(core.compile(input, error), "opposite-clock fanout compiles");

	std::vector<int32_t> expected = {0, 1, 1, 1};
	for (int32_t x = 2; x <= FanoutCount * 2; ++x) {
		expected.push_back(x);
		expected.push_back(1);
	}
	for (int32_t branch = 0; branch < FanoutCount; ++branch) {
		expected.push_back(Width + 2 + branch * 2);
		expected.push_back(1);
	}
	expect(core.advanceTick() == expected, "first clock drives the shared fanout Trace");

	expect(
			core.advanceTick() == std::vector<int32_t>({0, 0, 1, 0, 17, 1, 18, 1, 40, 1, 42, 1, 44, 1, 46, 1, 48, 1, 50, 1, 52, 1, 54, 1}),
			"opposite same-tick clock edges preserve the high shared Trace");
	for (int32_t branch = 0; branch < FanoutCount; ++branch) {
		const int32_t x = 2 + branch * 2;
		expectState(core, input, x, 0, 1, "shared Trace remains high after cancelling edges");
		expectState(core, input, x, 1, 1, "each fanout Write remains high after cancelling edges");
		expectState(core, input, x, 2, 1, "each Buffer commits the prior high input");
	}
	expect(
			core.advanceTick() == std::vector<int32_t>({0, 1, 1, 1}),
			"cancelled fanout transition creates no delayed Buffer work");

	expected = {0, 0, 1, 0};
	for (int32_t x = 2; x <= FanoutCount * 2; ++x) {
		expected.push_back(x);
		expected.push_back(0);
	}
	expected.insert(expected.end(), {17, 0, 18, 0});
	for (int32_t branch = 0; branch < FanoutCount; ++branch) {
		expected.push_back(Width + 2 + branch * 2);
		expected.push_back(0);
	}
	expect(core.advanceTick() == expected, "both clocks falling clears the shared Trace but retains delayed Buffers");
	for (int32_t branch = 0; branch < FanoutCount; ++branch) {
		expectState(core, input, 2 + branch * 2, 2, 1, "Buffers retain their prior value until the next tick");
	}

	expected = {0, 1, 1, 1};
	for (int32_t x = 2; x <= FanoutCount * 2; ++x) {
		expected.push_back(x);
		expected.push_back(1);
	}
	for (int32_t branch = 0; branch < FanoutCount; ++branch) {
		expected.push_back(Width + 2 + branch * 2);
		expected.push_back(1);
	}
	for (int32_t branch = 0; branch < FanoutCount; ++branch) {
		expected.push_back(Width * 2 + 2 + branch * 2);
		expected.push_back(0);
	}
	expect(core.advanceTick() == expected, "new Trace edge and delayed Buffer low preserve the tick barrier");
}

void testUnequalDepthConnectorDiamondConverges() {
	CompileInput input = makeInput(8, 6);
	setKind(input, 5, 0, ToolKind::Write);
	setKind(input, 6, 0, ToolKind::Read);
	setKind(input, 5, 1, ToolKind::Trace);
	setKind(input, 6, 1, ToolKind::TraceRed);
	setKind(input, 7, 1, ToolKind::TraceRed);
	setKind(input, 3, 2, ToolKind::Read);
	setKind(input, 4, 2, ToolKind::Trace);
	setKind(input, 5, 2, ToolKind::Read);
	setKind(input, 6, 2, ToolKind::Clock);
	setKind(input, 7, 2, ToolKind::TraceRed);
	setKind(input, 3, 3, ToolKind::Write);
	setKind(input, 4, 3, ToolKind::Write);
	setKind(input, 7, 3, ToolKind::TraceRed);
	setKind(input, 3, 4, ToolKind::TraceRed);
	setKind(input, 4, 4, ToolKind::Buffer);
	setKind(input, 7, 4, ToolKind::TraceRed);
	for (int32_t x = 3; x <= 7; ++x) {
		setKind(input, x, 5, ToolKind::TraceRed);
	}
	SimulationCore core;
	CompileError error;
	expect(core.compile(input, error), "unequal-depth connector diamond compiles");
	expect(
			core.advanceTick() == std::vector<int32_t>({5, 1, 6, 1, 13, 1, 14, 1, 15, 1, 19, 1, 20, 1, 21, 1, 22, 1, 23, 1, 27, 1, 28, 1, 31, 1, 35, 1, 39, 1, 43, 1, 44, 1, 45, 1, 46, 1, 47, 1}),
			"diamond routes both high paths into the convergence Trace");
	expectState(core, input, 4, 2, 1, "convergence Trace starts high");
	expectState(core, input, 4, 4, 0, "downstream Buffer stays delayed");
	expect(
			core.advanceTick() == std::vector<int32_t>({5, 0, 6, 0, 13, 0, 14, 0, 15, 0, 19, 0, 20, 0, 21, 0, 22, 0, 23, 0, 27, 0, 28, 0, 31, 0, 35, 0, 36, 1, 39, 0, 43, 0, 44, 0, 45, 0, 46, 0, 47, 0}),
			"late indirect low delta clears the diamond convergence Trace");
	expectState(core, input, 4, 2, 0, "convergence Trace clears after both path deltas");
	expectState(core, input, 4, 4, 1, "Buffer receives the prior high convergence state");
	expect(
			core.advanceTick() == std::vector<int32_t>({5, 1, 6, 1, 13, 1, 14, 1, 15, 1, 19, 1, 20, 1, 21, 1, 22, 1, 23, 1, 27, 1, 28, 1, 31, 1, 35, 1, 36, 0, 39, 1, 43, 1, 44, 1, 45, 1, 46, 1, 47, 1}),
			"diamond low propagation schedules the downstream Buffer before the next high edge");
}

void testConnectorQueueSpansTopologicalRankWords() {
	constexpr int32_t ConnectorStageCount = 4161;
	CompileInput input = makeInput(ConnectorStageCount * 3 + 5, 1);
	setKind(input, 0, 0, ToolKind::Clock);
	for (int32_t stage = 0; stage < ConnectorStageCount; ++stage) {
		const int32_t readX = stage * 3 + 1;
		setKind(input, readX, 0, ToolKind::Read);
		setKind(input, readX + 1, 0, ToolKind::Trace);
		setKind(input, readX + 2, 0, ToolKind::Write);
	}
	const int32_t finalReadX = ConnectorStageCount * 3 + 1;
	setKind(input, finalReadX, 0, ToolKind::Read);
	setKind(input, finalReadX + 1, 0, ToolKind::Trace);
	setKind(input, finalReadX + 2, 0, ToolKind::Write);
	setKind(input, finalReadX + 3, 0, ToolKind::Led);
	SimulationCore core;
	CompileError error;
	expect(core.compile(input, error), "long connector chain compiles");
	core.advanceTick();
	expectState(core, input, finalReadX + 1, 0, 1, "long connector chain resolves across rank words in one tick");
	expectState(core, input, finalReadX + 3, 0, 0, "long connector chain preserves the LED tick barrier");
	core.advanceTick();
	expectState(core, input, finalReadX + 1, 0, 0, "long connector chain propagates a falling edge across rank words");
	expectState(core, input, finalReadX + 3, 0, 1, "long connector chain commits the delayed LED state on the next tick");
	core.advanceTick();
	expectState(core, input, finalReadX + 1, 0, 1, "long connector chain reactivates the hierarchy after a full drain");
	expectState(core, input, finalReadX + 3, 0, 0, "long connector chain preserves the LED barrier after reactivation");
}

void testLargeComponentFrontierPropagatesAcrossLanes() {
	constexpr int32_t LaneCount = 4097;
	CompileInput input = makeInput(5, LaneCount * 2);
	for (int32_t lane = 0; lane < LaneCount; ++lane) {
		const int32_t y = lane * 2;
		setKind(input, 0, y, ToolKind::Clock);
		setKind(input, 1, y, ToolKind::Read);
		setKind(input, 2, y, ToolKind::Trace);
		setKind(input, 3, y, ToolKind::Write);
		setKind(input, 4, y, ToolKind::Buffer);
	}
	SimulationCore core;
	CompileError error;
	expect(core.compile(input, error), "large component frontier compiles");
	core.advanceTicksSilent(2);
	const std::vector<int32_t> highStates = core.getStates();
	for (int32_t lane : {0, LaneCount / 2, LaneCount - 1}) {
		expect(
				highStates[cellIndex(input, 4, lane * 2)] == 1,
				"large component frontier commits selected Buffer states on the next tick");
	}
	core.advanceTicksSilent(1);
	const std::vector<int32_t> lowStates = core.getStates();
	for (int32_t lane : {0, LaneCount / 2, LaneCount - 1}) {
		expect(
				lowStates[cellIndex(input, 4, lane * 2)] == 0,
				"large component frontier clears selected Buffer states on the following tick");
	}
}

void testRuntimeArenaUsesOnePageAlignedAllocationAcrossLargeRecompile() {
	constexpr int32_t LaneCount = 4097;
	CompileInput input = makeInput(5, LaneCount * 2);
	for (int32_t lane = 0; lane < LaneCount; ++lane) {
		const int32_t y = lane * 2;
		setKind(input, 0, y, ToolKind::Clock);
		setKind(input, 1, y, ToolKind::Read);
		setKind(input, 2, y, ToolKind::Trace);
		setKind(input, 3, y, ToolKind::Write);
		setKind(input, 4, y, ToolKind::Buffer);
	}
	SimulationCore core;
	CompileError error;
	expect(core.compile(input, error), "large generic graph compiles into the runtime arena");
	const ocb::RuntimeArenaDebugInfo firstLayout = core.getRuntimeArenaDebugInfo();
	expect(firstLayout.baseAddress % 4096U == 0, "runtime arena base is 4K aligned");
	expect(firstLayout.capacity % 4096U == 0, "runtime arena capacity is rounded to 4K pages");
	expect(firstLayout.used > 0 && firstLayout.used <= firstLayout.capacity, "runtime arena reports bounded usage");
	expect(firstLayout.allocationCount == 1, "large graph uses one runtime arena allocation");
	expect(core.validateRuntimeArenaLayout(), "all large-graph runtime slices reside in the arena");
	core.advanceTicksSilent(2);
	expectState(core, input, 4, (LaneCount / 2) * 2, 1, "arena-backed runtime state advances normally");

	expect(core.compile(input, error), "same core recompiles a large generic graph");
	const ocb::RuntimeArenaDebugInfo secondLayout = core.getRuntimeArenaDebugInfo();
	expect(secondLayout.baseAddress % 4096U == 0, "recompiled runtime arena base remains 4K aligned");
	expect(secondLayout.allocationCount == 1, "recompile replaces the old arena with one allocation");
	expect(core.validateRuntimeArenaLayout(), "recompiled runtime slices reside in the new arena");
}

void testSparseGateFrontierClearsPreviousTick() {
	constexpr int32_t SparseComponentCount = 16385;
	CompileInput input = makeInput(5, SparseComponentCount);
	setKind(input, 0, 0, ToolKind::Clock);
	setKind(input, 1, 0, ToolKind::Read);
	setKind(input, 2, 0, ToolKind::Trace);
	setKind(input, 3, 0, ToolKind::Write);
	setKind(input, 4, 0, ToolKind::Buffer);
	for (int32_t y = 1; y < SparseComponentCount; ++y) {
		setKind(input, 4, y, y % 2 == 0 ? ToolKind::Buffer : ToolKind::Latch);
	}
	SimulationCore core;
	CompileError error;
	expect(core.compile(input, error), "sparse gate frontier circuit compiles");
	core.advanceTick();
	expectState(core, input, 4, 0, 0, "sparse frontier keeps Buffer deferred after the high input");
	core.advanceTick();
	expectState(core, input, 4, 0, 1, "sparse frontier commits the pending high Buffer state");
	core.advanceTick();
	expectState(core, input, 4, 0, 0, "sparse frontier clears the previous gate before scheduling low");
	core.advanceTick();
	expectState(core, input, 4, 0, 1, "sparse frontier schedules a new high gate after clearing");
}

void testSparseGateFrontierHandlesNonMonotonicSummaryIndices() {
	constexpr int32_t SpacerGateCount = 4096;
	constexpr int32_t BottomPipelineRow = SpacerGateCount + 1;
	CompileInput input = makeInput(5, BottomPipelineRow + 1);
	setKind(input, 0, 0, ToolKind::Clock);
	setKind(input, 1, 0, ToolKind::Read);
	setKind(input, 2, 0, ToolKind::Trace);
	setKind(input, 3, 0, ToolKind::Write);
	setKind(input, 4, 0, ToolKind::Latch);
	for (int32_t row = 1; row <= SpacerGateCount; ++row) {
		setKind(input, 4, row, ToolKind::Buffer);
	}
	setKind(input, 0, BottomPipelineRow, ToolKind::Clock);
	setKind(input, 1, BottomPipelineRow, ToolKind::Read);
	setKind(input, 2, BottomPipelineRow, ToolKind::Trace);
	setKind(input, 3, BottomPipelineRow, ToolKind::Write);
	setKind(input, 4, BottomPipelineRow, ToolKind::Buffer);
	SimulationCore core;
	CompileError error;
	expect(core.compile(input, error), "non-monotonic sparse frontier circuit compiles");
	core.advanceTick();
	const std::vector<uint8_t> snapshot = core.captureState();
	expect(!snapshot.empty(), "non-monotonic sparse frontier captures pending gates");
	core.advanceTick();
	expectState(core, input, 4, 0, 1, "low-index Latch commits after a higher summary index was queued first");
	expectState(
			core,
			input,
			4,
			BottomPipelineRow,
			1,
			"high-index Buffer commits after a lower summary index was queued later");
	core.advanceTick();
	expectState(core, input, 4, BottomPipelineRow, 0, "non-monotonic sparse frontier clears the prior Buffer gate");
	std::string restoreError;
	expect(core.restoreState(snapshot, restoreError), "non-monotonic sparse frontier snapshot restores");
	core.advanceTick();
	expectState(core, input, 4, 0, 1, "restored Latch pending gate commits");
	expectState(core, input, 4, BottomPipelineRow, 1, "restored Buffer pending gate commits");
}

void testQueuedComponentGateTracksLaterDelta() {
	CompileInput input = makeInput(5, 1);
	setKind(input, 0, 0, ToolKind::Latch);
	setKind(input, 1, 0, ToolKind::Read);
	setKind(input, 2, 0, ToolKind::Trace);
	setKind(input, 3, 0, ToolKind::Write);
	setKind(input, 4, 0, ToolKind::Buffer);
	SimulationCore core;
	CompileError error;
	std::vector<int32_t> changes;
	std::string toggleError;
	expect(core.compile(input, error), "queued component override fixture compiles");
	expect(core.toggleLatch(0, changes, toggleError), "first Latch toggle queues Buffer high");
	expect(core.toggleLatch(0, changes, toggleError), "second Latch toggle overwrites queued Buffer state");
	core.advanceTick();
	expectState(core, input, 4, 0, 0, "later component delta preserves the pending gate's final low state");
}

void expectQueuedUnaryGateUpdate(ToolKind gateKind, int32_t expectedState, const std::string &name) {
	CompileInput input = makeInput(5, 1);
	setKind(input, 0, 0, ToolKind::Latch);
	setKind(input, 1, 0, ToolKind::Read);
	setKind(input, 2, 0, ToolKind::Trace);
	setKind(input, 3, 0, ToolKind::Write);
	setKind(input, 4, 0, gateKind);
	SimulationCore core;
	CompileError error;
	std::vector<int32_t> changes;
	std::string toggleError;
	expect(core.compile(input, error), name + " queued unary fixture compiles");
	expect(core.toggleLatch(0, changes, toggleError), name + " queues its high-input state");
	expect(core.toggleLatch(0, changes, toggleError), name + " updates its queued state on the falling input");
	core.advanceTick();
	expectState(core, input, 4, 0, expectedState, name + " commits its bucketed queued state");
}

void expectQueuedBinaryGateUpdate(ToolKind gateKind, int32_t expectedState, const std::string &name) {
	CompileInput input = makeInput(5, 3);
	setKind(input, 0, 0, ToolKind::Latch);
	setKind(input, 1, 0, ToolKind::Read);
	setKind(input, 2, 0, ToolKind::Trace);
	setKind(input, 3, 0, ToolKind::Trace);
	setKind(input, 4, 0, ToolKind::Write);
	setKind(input, 4, 1, gateKind);
	setKind(input, 0, 2, ToolKind::Latch);
	setKind(input, 1, 2, ToolKind::Read);
	setKind(input, 2, 2, ToolKind::Trace);
	setKind(input, 3, 2, ToolKind::Trace);
	setKind(input, 4, 2, ToolKind::Write);
	SimulationCore core;
	CompileError error;
	std::vector<int32_t> changes;
	std::string toggleError;
	expect(core.compile(input, error), name + " queued binary fixture compiles");
	expect(core.toggleLatch(cellIndex(input, 0, 0), changes, toggleError), name + " queues its first input");
	expect(core.toggleLatch(cellIndex(input, 0, 2), changes, toggleError), name + " queues its second input");
	expect(core.toggleLatch(cellIndex(input, 0, 0), changes, toggleError), name + " updates its queued result");
	core.advanceTick();
	expectState(core, input, 4, 1, expectedState, name + " commits its bucketed queued result");
}

void testQueuedComponentBucketsTrackUpdates() {
	expectQueuedUnaryGateUpdate(ToolKind::And, 0, "unary AND");
	expectQueuedUnaryGateUpdate(ToolKind::Nand, 1, "unary NAND");
	expectQueuedUnaryGateUpdate(ToolKind::Latch, 1, "Latch");
	expectQueuedBinaryGateUpdate(ToolKind::And, 0, "AND");
	expectQueuedBinaryGateUpdate(ToolKind::Nand, 1, "NAND");
	expectQueuedBinaryGateUpdate(ToolKind::Xor, 1, "XOR");
	expectQueuedBinaryGateUpdate(ToolKind::Xnor, 0, "XNOR");
}

void testTerminalConnectorAliases() {
	CompileInput pipelineInput = makeInput(6, 1);
	setKind(pipelineInput, 0, 0, ToolKind::Clock);
	setKind(pipelineInput, 1, 0, ToolKind::Read);
	setKind(pipelineInput, 2, 0, ToolKind::Trace);
	setKind(pipelineInput, 3, 0, ToolKind::Write);
	setKind(pipelineInput, 4, 0, ToolKind::Read);
	setKind(pipelineInput, 5, 0, ToolKind::Trace);
	SimulationCore pipelineCore;
	CompileError error;
	expect(pipelineCore.compile(pipelineInput, error), "terminal connector pipeline compiles");
	pipelineCore.advanceTick();
	expect(pipelineCore.getStates() == std::vector<int32_t>({1, 1, 1, 1, 1, 1}), "terminal aliases follow their component and connector sources");
	const std::vector<uint8_t> highSnapshot = pipelineCore.captureState();
	pipelineCore.advanceTick();
	expect(pipelineCore.getStates() == std::vector<int32_t>({0, 0, 0, 0, 0, 0}), "terminal aliases clear with their sources");
	std::string restoreError;
	expect(pipelineCore.restoreState(highSnapshot, restoreError), "terminal connector snapshot restores");
	expect(pipelineCore.getStates() == std::vector<int32_t>({1, 1, 1, 1, 1, 1}), "terminal alias snapshot keeps every visible state");

	CompileInput sharedInput = makeInput(3, 3);
	setKind(sharedInput, 0, 0, ToolKind::Latch);
	setKind(sharedInput, 1, 0, ToolKind::Read);
	setKind(sharedInput, 2, 0, ToolKind::Trace);
	setKind(sharedInput, 2, 1, ToolKind::Trace);
	setKind(sharedInput, 0, 2, ToolKind::Latch);
	setKind(sharedInput, 1, 2, ToolKind::Read);
	setKind(sharedInput, 2, 2, ToolKind::Trace);
	setInitialState(sharedInput, 0, 0, 1);
	setInitialState(sharedInput, 0, 2, 1);
	SimulationCore sharedCore;
	std::vector<int32_t> changes;
	std::string toggleError;
	expect(sharedCore.compile(sharedInput, error), "multi-input terminal Trace compiles");
	expect(sharedCore.toggleLatch(cellIndex(sharedInput, 0, 0), changes, toggleError), "first shared source toggles low");
	expectState(sharedCore, sharedInput, 2, 1, 1, "multi-input terminal Trace stays high with one remaining source");
	expect(sharedCore.toggleLatch(cellIndex(sharedInput, 0, 2), changes, toggleError), "second shared source toggles low");
	expectState(sharedCore, sharedInput, 2, 1, 0, "multi-input terminal Trace clears after every source is low");
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
	silentCore.advanceTicksSilent(8);
	expect(silentCore.drainStateChanges() == expectedChanges, "drain returns the same final delta as exact batch advance");
	expect(silentCore.getStates() == exactCore.getStates(), "silent advance reaches the exact batch state");
	expect(silentCore.drainStateChanges().empty(), "second drain is empty after final delta is consumed");

	CompileInput clockInput = makeInput(1, 1);
	setKind(clockInput, 0, 0, ToolKind::Clock);
	SimulationCore clockCore;
	expect(clockCore.compile(clockInput, error), "standalone Clock compiles for final-delta filtering");
	clockCore.advanceTicksSilent(2);
	expect(clockCore.getStates() == std::vector<int32_t>({0}), "silent Clock materializes its returned-to-initial state");
	expect(clockCore.drainStateChanges().empty(), "silent collection omits a cell that returns to its reported state");
	clockCore.advanceTicksSilent(1);
	expect(clockCore.getStates() == std::vector<int32_t>({1}), "silent Clock materializes its changed state after cancellation");
	expect(clockCore.drainStateChanges() == std::vector<int32_t>({0, 1}), "Clock reports a changed state after a cancelled epoch");
	clockCore.advanceTicksSilent(2);
	expect(clockCore.getStates() == std::vector<int32_t>({1}), "silent Clock preserves its materialized state after a second cancellation");
	expect(clockCore.drainStateChanges().empty(), "second cancelled Clock epoch emits no delta");
}

void testDeferredVisibleStateMaterialization() {
	CompileInput input = makeInput(5, 1);
	setKind(input, 0, 0, ToolKind::Clock);
	setKind(input, 1, 0, ToolKind::Read);
	setKind(input, 2, 0, ToolKind::Trace);
	setKind(input, 3, 0, ToolKind::Write);
	setKind(input, 4, 0, ToolKind::Buffer);
	SimulationCore core;
	CompileError error;
	expect(core.compile(input, error), "deferred materialization pipeline compiles");
	core.advanceTicksSilent(1);
	expect(
			core.getStates() == std::vector<int32_t>({1, 1, 1, 1, 0}),
			"getStates materializes the latest node state without advancing simulation");
	expect(
			core.drainStateChanges() == std::vector<int32_t>({0, 1, 1, 1, 2, 1, 3, 1}),
			"getStates does not consume deferred state deltas");
	expect(core.drainStateChanges().empty(), "a deferred delta is only drained once");

	CompileInput crossInput = makeInput(6, 6);
	setKind(crossInput, 0, 3, ToolKind::Clock);
	setKind(crossInput, 1, 3, ToolKind::Read);
	setKind(crossInput, 2, 3, ToolKind::Trace);
	setKind(crossInput, 3, 3, ToolKind::Cross);
	setKind(crossInput, 4, 3, ToolKind::Trace);
	setKind(crossInput, 3, 0, ToolKind::Clock);
	setKind(crossInput, 3, 1, ToolKind::Read);
	setKind(crossInput, 3, 2, ToolKind::Trace);
	setKind(crossInput, 3, 4, ToolKind::Trace);
	crossInput.clockHoldTicks[cellIndex(crossInput, 3, 0)] = 2;
	SimulationCore crossCore;
	expect(crossCore.compile(crossInput, error), "deferred materialization Cross circuit compiles");
	const int32_t crossCell = cellIndex(crossInput, 3, 3);
	const std::vector<int32_t> firstCrossChanges = crossCore.advanceTick();
	expect(countChangesForCell(firstCrossChanges, crossCell) == 1, "Cross emits one delta when one channel turns on");
	expectState(crossCore, crossInput, 3, 3, 1, "Cross becomes visible when its horizontal channel turns on");
	const std::vector<int32_t> secondCrossChanges = crossCore.advanceTick();
	expect(countChangesForCell(secondCrossChanges, crossCell) == 0, "Cross omits a delta when one channel replaces the other");
	expectState(crossCore, crossInput, 3, 3, 1, "Cross remains visible when its vertical channel replaces the horizontal channel");
	SimulationCore cancelledCrossCore;
	expect(cancelledCrossCore.compile(crossInput, error), "deferred cancellation Cross circuit compiles");
	cancelledCrossCore.advanceTicksSilent(4);
	expectState(cancelledCrossCore, crossInput, 3, 3, 0, "Cross materializes its returned-to-initial channels");
	expect(cancelledCrossCore.drainStateChanges().empty(), "Cross omits a delta when both channels return to their reported states");

	CompileInput clockInput = makeInput(1, 1);
	setKind(clockInput, 0, 0, ToolKind::Clock);
	SimulationCore clockCore;
	expect(clockCore.compile(clockInput, error), "deferred materialization Clock compiles");
	clockCore.advanceTicksSilent(1);
	expect(clockCore.reset().empty(), "reset collapses an unreported silent Clock transition");
	clockCore.advanceTicksSilent(1);
	expect(clockCore.drainStateChanges() == std::vector<int32_t>({0, 1}), "drain reports the materialized Clock state");
	const std::vector<uint8_t> highSnapshot = clockCore.captureState();
	expect(clockCore.advanceTick() == std::vector<int32_t>({0, 0}), "Clock advances low before snapshot restore");
	std::string restoreError;
	expect(clockCore.restoreState(highSnapshot, restoreError), "restores a materialized Clock snapshot");
	expect(clockCore.getStates() == std::vector<int32_t>({1}), "restore materializes high component state");
	expect(clockCore.drainStateChanges().empty(), "restore resets deferred delta collection");
	expect(clockCore.advanceTick() == std::vector<int32_t>({0, 0}), "Clock advances from restored state");
}

void testGraphOrderingPreservesExternalStatesAndDeltas() {
	CompileInput input = makeInput(4, 11);
	setKind(input, 0, 0, ToolKind::Clock);
	setKind(input, 1, 0, ToolKind::Read);
	setKind(input, 2, 0, ToolKind::Trace);
	setKind(input, 3, 0, ToolKind::Mesh);
	input.meshIds[cellIndex(input, 3, 0)] = 1;
	setKind(input, 0, 2, ToolKind::Clock);
	setKind(input, 1, 2, ToolKind::Read);
	setKind(input, 2, 2, ToolKind::Trace);
	setKind(input, 3, 2, ToolKind::Mesh);
	input.meshIds[cellIndex(input, 3, 2)] = 2;

	setKind(input, 0, 5, ToolKind::Mesh);
	input.meshIds[cellIndex(input, 0, 5)] = 1;
	setKind(input, 1, 5, ToolKind::Trace);
	setKind(input, 2, 5, ToolKind::Write);
	setKind(input, 3, 5, ToolKind::Buffer);
	for (int32_t y : {7, 9}) {
		setKind(input, 0, y, ToolKind::Mesh);
		input.meshIds[cellIndex(input, 0, y)] = 2;
		setKind(input, 1, y, ToolKind::Trace);
		setKind(input, 2, y, ToolKind::Write);
		setKind(input, 3, y, ToolKind::Buffer);
	}
	SimulationCore baselineCore(false, true);
	SimulationCore orderedCore(true, true);
	CompileError error;
	expect(baselineCore.compile(input, error), "unreordered reference circuit compiles");
	expect(orderedCore.compile(input, error), "reordered reference circuit compiles");
	const int64_t baselineScore = baselineCore.getGraphLocalityScore();
	const int64_t orderedScore = orderedCore.getGraphLocalityScore();
	if (orderedCore.isGraphLocalityOrderingApplied()) {
		expect(orderedScore > baselineScore, "accepted ordering improves the execution graph locality score");
	} else {
		expect(orderedScore == baselineScore, "rejected ordering preserves the compact baseline locality score");
	}
	expect(orderedCore.getStates() == baselineCore.getStates(), "reordered compile preserves initial visible states");
	for (int32_t tick = 0; tick < 3; ++tick) {
		const std::vector<int32_t> baselineChanges = baselineCore.advanceTick();
		const std::vector<int32_t> orderedChanges = orderedCore.advanceTick();
		expect(orderedChanges == baselineChanges, "reordered execution preserves sorted external delta order");
		expect(orderedCore.getStates() == baselineCore.getStates(), "reordered execution preserves each tick's visible state");
	}
	const std::vector<uint8_t> snapshot = baselineCore.captureState();
	expect(!snapshot.empty(), "baseline final-layout snapshot captures connector and component state");
	orderedCore.advanceTick();
	expect(orderedCore.getStates() != baselineCore.getStates(), "ordered core advances away from the captured snapshot state");
	std::string restoreError;
	expect(orderedCore.restoreState(snapshot, restoreError), "ordered final-layout restores a baseline snapshot");
	expect(orderedCore.getStates() == baselineCore.getStates(), "cross-layout snapshot restore preserves visible state");
	for (int32_t tick = 3; tick < 12; ++tick) {
		const std::vector<int32_t> baselineChanges = baselineCore.advanceTick();
		const std::vector<int32_t> orderedChanges = orderedCore.advanceTick();
		expect(orderedChanges == baselineChanges, "restored reordered execution preserves sorted external delta order");
		expect(orderedCore.getStates() == baselineCore.getStates(), "restored reordered execution preserves each tick's visible state");
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
	expectState(core, input, 3, 0, 1, "Cross is visible when one isolated channel is powered");
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
	expect(writeWithTwoTraceSidesCore.compile(writeWithTwoTraceSides, error), "Write accepts multiple Trace inputs as a wired-OR port");

	CompileInput ambiguousRead = makeInput(3, 2);
	setKind(ambiguousRead, 0, 0, ToolKind::Trace);
	setKind(ambiguousRead, 1, 0, ToolKind::Write);
	setKind(ambiguousRead, 0, 1, ToolKind::Latch);
	setKind(ambiguousRead, 1, 1, ToolKind::Read);
	setKind(ambiguousRead, 2, 1, ToolKind::Trace);
	SimulationCore ambiguousReadCore;
	expect(ambiguousReadCore.compile(ambiguousRead, error), "Read accepts simultaneous device and Write sources as a wired-OR port");
}

void testAggregatedReadAndWritePorts() {
	CompileInput readInput = makeInput(2, 3);
	setKind(readInput, 0, 0, ToolKind::Latch);
	setInitialState(readInput, 0, 0, 1);
	setKind(readInput, 1, 0, ToolKind::Latch);
	setKind(readInput, 0, 1, ToolKind::Read);
	setKind(readInput, 1, 1, ToolKind::Read);
	setKind(readInput, 0, 2, ToolKind::Trace);
	setKind(readInput, 1, 2, ToolKind::TraceRed);
	SimulationCore readCore;
	CompileError error;
	std::vector<int32_t> changes;
	std::string toggleError;
	expect(readCore.compile(readInput, error), "aggregated Read ports compile");
	expectState(readCore, readInput, 0, 2, 1, "aggregated Read OR drives its first Trace output");
	expectState(readCore, readInput, 1, 2, 1, "aggregated Read fans out to its second Trace output");
	expect(readCore.toggleLatch(cellIndex(readInput, 0, 0), changes, toggleError), "first aggregated Read source toggles low");
	expectState(readCore, readInput, 0, 2, 0, "aggregated Read clears when every source is low");
	expectState(readCore, readInput, 1, 2, 0, "aggregated Read clears every fanout output");
	expect(readCore.toggleLatch(cellIndex(readInput, 1, 0), changes, toggleError), "second aggregated Read source toggles high");
	expectState(readCore, readInput, 0, 2, 1, "aggregated Read accepts its second source");
	expectState(readCore, readInput, 1, 2, 1, "aggregated Read restores every output from its second source");

	CompileInput writeInput = makeInput(6, 3);
	setKind(writeInput, 0, 0, ToolKind::Latch);
	setInitialState(writeInput, 0, 0, 1);
	setKind(writeInput, 1, 0, ToolKind::Read);
	setKind(writeInput, 2, 0, ToolKind::Trace);
	setKind(writeInput, 3, 0, ToolKind::TraceRed);
	setKind(writeInput, 4, 0, ToolKind::Read);
	setKind(writeInput, 5, 0, ToolKind::Latch);
	setKind(writeInput, 2, 1, ToolKind::Write);
	setKind(writeInput, 3, 1, ToolKind::Write);
	setKind(writeInput, 2, 2, ToolKind::Buffer);
	setKind(writeInput, 3, 2, ToolKind::Led);
	SimulationCore writeCore;
	expect(writeCore.compile(writeInput, error), "aggregated Write ports compile");
	expectState(writeCore, writeInput, 2, 1, 1, "aggregated Write OR is visible on its first cell");
	expectState(writeCore, writeInput, 3, 1, 1, "aggregated Write OR is visible on its second cell");
	writeCore.advanceTick();
	expectState(writeCore, writeInput, 2, 2, 1, "aggregated Write fans out to Buffer targets");
	expectState(writeCore, writeInput, 3, 2, 1, "aggregated Write fans out to LED targets");
	expect(writeCore.toggleLatch(cellIndex(writeInput, 0, 0), changes, toggleError), "first aggregated Write source toggles low");
	writeCore.advanceTick();
	expectState(writeCore, writeInput, 2, 2, 0, "aggregated Write clears Buffer after every input falls");
	expectState(writeCore, writeInput, 3, 2, 0, "aggregated Write clears LED after every input falls");
	expect(writeCore.toggleLatch(cellIndex(writeInput, 5, 0), changes, toggleError), "second aggregated Write source toggles high");
	writeCore.advanceTick();
	expectState(writeCore, writeInput, 2, 2, 1, "aggregated Write accepts its second input");
	expectState(writeCore, writeInput, 3, 2, 1, "aggregated Write restores every target from its second input");
}

void testMergedGateAcceptsDistributedWritePorts() {
	CompileInput input = makeInput(4, 4);
	setKind(input, 0, 0, ToolKind::Latch);
	setInitialState(input, 0, 0, 1);
	setKind(input, 1, 0, ToolKind::Read);
	setKind(input, 2, 0, ToolKind::Trace);
	setKind(input, 3, 0, ToolKind::Write);
	setKind(input, 3, 1, ToolKind::And);
	setKind(input, 3, 2, ToolKind::And);
	setKind(input, 0, 3, ToolKind::Latch);
	setKind(input, 1, 3, ToolKind::Read);
	setKind(input, 2, 3, ToolKind::Trace);
	setKind(input, 3, 3, ToolKind::Write);
	SimulationCore core;
	CompileError error;
	std::vector<int32_t> changes;
	std::string toggleError;
	expect(core.compile(input, error), "merged AND with distributed Write ports compiles");
	core.advanceTick();
	expectState(core, input, 3, 1, 0, "merged AND remains low with one active Write port");
	expectState(core, input, 3, 2, 0, "every cell of merged AND shares the one-input state");
	expect(core.toggleLatch(cellIndex(input, 0, 3), changes, toggleError), "second merged AND input toggles high");
	core.advanceTick();
	expectState(core, input, 3, 1, 1, "merged AND becomes high when A equals T");
	expectState(core, input, 3, 2, 1, "every cell of merged AND shares the all-high state");
	expect(core.toggleLatch(cellIndex(input, 0, 0), changes, toggleError), "first merged AND input toggles low");
	core.advanceTick();
	expectState(core, input, 3, 1, 0, "merged AND clears when one distributed input falls");
	expectState(core, input, 3, 2, 0, "every cell of merged AND clears together");
}

void testLatchMultipleRisingEdgesCancel() {
	CompileInput input = makeInput(5, 3);
	setKind(input, 0, 2, ToolKind::Latch);
	setKind(input, 1, 2, ToolKind::Read);
	setKind(input, 2, 2, ToolKind::Trace);
	setKind(input, 3, 2, ToolKind::Write);
	setKind(input, 4, 2, ToolKind::Latch);
	setKind(input, 1, 1, ToolKind::Trace);
	setKind(input, 1, 0, ToolKind::Trace);
	setKind(input, 2, 0, ToolKind::Trace);
	setKind(input, 3, 0, ToolKind::Trace);
	setKind(input, 4, 0, ToolKind::Trace);
	setKind(input, 4, 1, ToolKind::Write);
	SimulationCore core;
	CompileError error;
	std::vector<int32_t> changes;
	std::string toggleError;
	expect(core.compile(input, error), "dual-rising-edge Latch circuit compiles");
	expect(core.toggleLatch(cellIndex(input, 0, 2), changes, toggleError), "dual-rising-edge source toggles high");
	expectState(core, input, 4, 2, 0, "Latch waits for the next logical tick");
	core.advanceTick();
	expectState(core, input, 4, 2, 0, "two simultaneous Write rising edges cancel their Latch flips");
}

void testAdjacentReadWriteGroupsShareOneLogicalPort() {
	const auto makeInputForTarget = [](ToolKind targetKind) {
		CompileInput input = makeInput(4, 3);
		setKind(input, 0, 1, ToolKind::Latch);
		setKind(input, 1, 0, ToolKind::Read);
		setKind(input, 1, 1, ToolKind::Read);
		setKind(input, 1, 2, ToolKind::Read);
		setKind(input, 2, 0, ToolKind::Write);
		setKind(input, 2, 2, ToolKind::Write);
		setKind(input, 3, 0, targetKind);
		setKind(input, 3, 1, targetKind);
		setKind(input, 3, 2, targetKind);
		return input;
	};

	CompileError error;
	std::vector<int32_t> changes;
	std::string toggleError;
	CompileInput latchInput = makeInputForTarget(ToolKind::Latch);
	SimulationCore latchCore;
	expect(latchCore.compile(latchInput, error), "adjacent Read/Write Latch fixture compiles");
	expect(latchCore.toggleLatch(cellIndex(latchInput, 0, 1), changes, toggleError), "logical-port source toggles high");
	expectState(latchCore, latchInput, 3, 1, 0, "logical-port Latch waits for its next tick");
	latchCore.advanceTick();
	expectState(latchCore, latchInput, 3, 1, 1, "adjacent Read/Write group produces one Latch rising edge");

	CompileInput xorInput = makeInputForTarget(ToolKind::Xor);
	SimulationCore xorCore;
	expect(xorCore.compile(xorInput, error), "adjacent Read/Write XOR fixture compiles");
	expect(xorCore.toggleLatch(cellIndex(xorInput, 0, 1), changes, toggleError), "logical-port XOR source toggles high");
	xorCore.advanceTick();
	expectState(xorCore, xorInput, 3, 1, 1, "adjacent Read/Write group contributes one XOR input");
}

void testManualLatchTogglePreservesQueuedWriteEdge() {
	CompileInput input = makeInput(5, 1);
	setKind(input, 0, 0, ToolKind::Clock);
	setKind(input, 1, 0, ToolKind::Read);
	setKind(input, 2, 0, ToolKind::Trace);
	setKind(input, 3, 0, ToolKind::Write);
	setKind(input, 4, 0, ToolKind::Latch);
	SimulationCore core;
	CompileError error;
	std::vector<int32_t> changes;
	std::string toggleError;
	expect(core.compile(input, error), "manual-toggle Latch pipeline compiles");
	core.advanceTick();
	expectState(core, input, 4, 0, 0, "Write rising edge remains queued before the manual toggle");
	expect(core.toggleLatch(cellIndex(input, 4, 0), changes, toggleError), "queued Latch can still be toggled manually");
	expectState(core, input, 4, 0, 1, "manual Latch toggle applies immediately");
	core.advanceTick();
	expectState(core, input, 4, 0, 0, "queued Write rising edge still flips the manually toggled Latch");
}

void testContinuousCrossChannels() {
	CompileInput input = makeInput(8, 1);
	setKind(input, 0, 0, ToolKind::Latch);
	setInitialState(input, 0, 0, 1);
	setKind(input, 1, 0, ToolKind::Read);
	setKind(input, 2, 0, ToolKind::Trace);
	setKind(input, 3, 0, ToolKind::Cross);
	setKind(input, 4, 0, ToolKind::Cross);
	setKind(input, 5, 0, ToolKind::Trace);
	setKind(input, 6, 0, ToolKind::Write);
	setKind(input, 7, 0, ToolKind::Led);
	SimulationCore core;
	CompileError error;
	std::vector<int32_t> changes;
	std::string toggleError;
	expect(core.compile(input, error), "continuous Cross channel circuit compiles");
	expectState(core, input, 3, 0, 1, "first Cross cell is active on its horizontal channel");
	expectState(core, input, 4, 0, 1, "second Cross cell extends the horizontal channel");
	expectState(core, input, 5, 0, 1, "continuous Cross channel drives its remote Trace");
	core.advanceTick();
	expectState(core, input, 7, 0, 1, "continuous Cross channel reaches the delayed LED target");
	expect(core.toggleLatch(0, changes, toggleError), "continuous Cross source toggles low");
	expectState(core, input, 3, 0, 0, "first Cross channel clears with its source");
	expectState(core, input, 4, 0, 0, "second Cross channel clears with its source");
	expectState(core, input, 5, 0, 0, "continuous Cross remote Trace clears with its source");
}

void testCrossAxesRemainIsolated() {
	CompileInput input = makeInput(7, 5);
	setKind(input, 0, 0, ToolKind::Latch);
	setInitialState(input, 0, 0, 1);
	setKind(input, 1, 0, ToolKind::Read);
	setKind(input, 2, 0, ToolKind::Trace);
	setKind(input, 3, 0, ToolKind::Trace);
	setKind(input, 3, 1, ToolKind::Trace);
	setKind(input, 0, 2, ToolKind::Latch);
	setInitialState(input, 0, 2, 1);
	setKind(input, 1, 2, ToolKind::Read);
	setKind(input, 2, 2, ToolKind::Trace);
	setKind(input, 3, 2, ToolKind::Cross);
	setKind(input, 4, 2, ToolKind::Trace);
	setKind(input, 5, 2, ToolKind::Write);
	setKind(input, 6, 2, ToolKind::Led);
	setKind(input, 3, 3, ToolKind::Trace);
	setKind(input, 3, 4, ToolKind::Write);
	setKind(input, 4, 4, ToolKind::Led);
	SimulationCore core;
	CompileError error;
	std::vector<int32_t> changes;
	std::string toggleError;
	expect(core.compile(input, error), "same-color Cross axes fixture compiles");
	expectState(core, input, 4, 2, 1, "horizontal Cross channel reaches its remote Trace");
	expectState(core, input, 3, 3, 1, "vertical Cross channel reaches its remote Trace");
	expect(core.toggleLatch(cellIndex(input, 0, 2), changes, toggleError), "horizontal Cross source toggles low");
	expectState(core, input, 4, 2, 0, "horizontal Cross channel clears independently");
	expectState(core, input, 3, 3, 1, "vertical Cross channel remains high after horizontal clear");
	expectState(core, input, 3, 2, 1, "Cross remains visible while its vertical channel is high");
	expect(core.toggleLatch(cellIndex(input, 0, 0), changes, toggleError), "vertical Cross source toggles low");
	expectState(core, input, 3, 3, 0, "vertical Cross channel clears independently");
	expectState(core, input, 3, 2, 0, "Cross clears after both isolated channels are low");
}

void testMultiColorMeshConnectivity() {
	CompileInput input = makeInput(9, 5);
	setKind(input, 3, 4, ToolKind::Latch);
	setKind(input, 3, 3, ToolKind::Read);
	setKind(input, 3, 2, ToolKind::TraceBlue);
	setKind(input, 0, 1, ToolKind::Latch);
	setInitialState(input, 0, 1, 1);
	setKind(input, 1, 1, ToolKind::Read);
	setKind(input, 2, 1, ToolKind::TraceRed);
	setKind(input, 3, 1, ToolKind::Mesh);
	setKind(input, 5, 1, ToolKind::Mesh);
	input.meshIds[cellIndex(input, 3, 1)] = 17;
	input.meshIds[cellIndex(input, 5, 1)] = 17;
	setKind(input, 6, 1, ToolKind::TraceRed);
	setKind(input, 7, 1, ToolKind::Write);
	setKind(input, 8, 1, ToolKind::Led);
	setKind(input, 5, 2, ToolKind::TraceBlue);
	setKind(input, 6, 2, ToolKind::Write);
	setKind(input, 7, 2, ToolKind::Buffer);
	SimulationCore core;
	CompileError error;
	std::vector<int32_t> changes;
	std::string toggleError;
	expect(core.compile(input, error), "multi-color Mesh endpoints compile");
	expectState(core, input, 3, 1, 1, "source Mesh is visible from its active red channel");
	expectState(core, input, 5, 1, 1, "remote Mesh is visible from its active red channel");
	expectState(core, input, 6, 1, 1, "red Mesh channel reaches the remote Trace");
	expectState(core, input, 5, 2, 0, "blue Mesh channel remains low before its source rises");
	core.advanceTick();
	expectState(core, input, 8, 1, 1, "red Mesh channel reaches the delayed LED target");
	expect(core.toggleLatch(cellIndex(input, 3, 4), changes, toggleError), "blue Mesh source toggles high");
	expectState(core, input, 5, 2, 1, "blue Mesh channel reaches the remote Trace independently");
	expectState(core, input, 6, 2, 1, "blue Mesh channel reaches its Write port independently");
	core.advanceTick();
	expectState(core, input, 7, 2, 1, "blue Mesh channel reaches the delayed Buffer target");
	expect(core.toggleLatch(cellIndex(input, 0, 1), changes, toggleError), "red Mesh source toggles low");
	expectState(core, input, 6, 1, 0, "red Mesh channel clears independently");
	expectState(core, input, 3, 1, 1, "source Mesh remains visible from its blue channel");
	expectState(core, input, 5, 1, 1, "remote Mesh remains visible from its blue channel");
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
	expectMultiWriteAllowed(ToolKind::Buffer, "Buffer");
	expectMultiWriteAllowed(ToolKind::Not, "NOT");
	expectMultiWriteAllowed(ToolKind::Latch, "Latch");
	expectMultiWriteAllowed(ToolKind::Led, "LED");
}

void testMultiWriteGatePropagatesAllInputs() {
	CompileInput input = makeInput(5, 3);
	setKind(input, 0, 2, ToolKind::Latch);
	setKind(input, 1, 2, ToolKind::Read);
	setKind(input, 2, 2, ToolKind::Trace);
	setKind(input, 3, 2, ToolKind::Write);
	setKind(input, 4, 2, ToolKind::And);
	setKind(input, 1, 1, ToolKind::Trace);
	setKind(input, 1, 0, ToolKind::Trace);
	setKind(input, 2, 0, ToolKind::Trace);
	setKind(input, 3, 0, ToolKind::Trace);
	setKind(input, 4, 0, ToolKind::Trace);
	setKind(input, 4, 1, ToolKind::Write);

	SimulationCore core;
	CompileError error;
	std::vector<int32_t> changes;
	std::string toggleError;
	expect(core.compile(input, error), "dual-Write AND circuit compiles");
	expect(core.toggleLatch(cellIndex(input, 0, 2), changes, toggleError), "Latch enables both AND inputs");
	expect(
			core.getStates() == std::vector<int32_t>({0, 1, 1, 1, 1, 0, 1, 0, 0, 1, 1, 1, 1, 1, 0}),
			"dual Read outputs settle before the AND tick");
	core.advanceTick();
	expectState(core, input, 4, 2, 1, "AND receives both settled Write inputs on the next tick");

	expect(core.toggleLatch(cellIndex(input, 0, 2), changes, toggleError), "Latch disables both AND inputs");
	expect(
			core.getStates() == std::vector<int32_t>({0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1}),
			"AND keeps its prior value until the scheduled low-input tick");
	core.advanceTick();
	expectState(core, input, 4, 2, 0, "AND clears after both input decrements are applied");
}

void testRelayBypassPreservesInputMultiplicity() {
	CompileInput input = makeInput(5, 3);
	setKind(input, 0, 2, ToolKind::Latch);
	setKind(input, 1, 2, ToolKind::Read);
	setKind(input, 2, 2, ToolKind::Trace);
	setKind(input, 3, 2, ToolKind::Write);
	setKind(input, 4, 2, ToolKind::Xor);
	setKind(input, 1, 1, ToolKind::Trace);
	setKind(input, 1, 0, ToolKind::Trace);
	setKind(input, 2, 0, ToolKind::Trace);
	setKind(input, 3, 0, ToolKind::Trace);
	setKind(input, 4, 0, ToolKind::Trace);
	setKind(input, 4, 1, ToolKind::Write);

	SimulationCore core;
	CompileError error;
	std::vector<int32_t> changes;
	std::string toggleError;
	expect(core.compile(input, error), "dual-Write XOR circuit compiles");
	expect(core.toggleLatch(cellIndex(input, 0, 2), changes, toggleError), "Latch enables both XOR inputs");
	core.advanceTick();
	expectState(core, input, 4, 2, 0, "XOR keeps even parity for two related high inputs");
	expect(core.toggleLatch(cellIndex(input, 0, 2), changes, toggleError), "Latch disables both XOR inputs");
	core.advanceTick();
	expectState(core, input, 4, 2, 0, "XOR keeps even parity after two related low inputs");
}

void testRelayBypassPreservesFeedbackDelay() {
	CompileInput input = makeInput(2, 2);
	setKind(input, 0, 0, ToolKind::Not);
	setKind(input, 1, 0, ToolKind::Read);
	setKind(input, 0, 1, ToolKind::Write);
	setKind(input, 1, 1, ToolKind::Trace);
	SimulationCore core;
	CompileError error;
	expect(core.compile(input, error), "NOT feedback circuit compiles");
	expect(core.getStates() == std::vector<int32_t>({1, 1, 1, 1}), "NOT feedback initializes high through its connector");
	core.advanceTick();
	expect(core.getStates() == std::vector<int32_t>({0, 0, 0, 0}), "NOT feedback falls on the next tick");
	core.advanceTick();
	expect(core.getStates() == std::vector<int32_t>({1, 1, 1, 1}), "NOT feedback rises again after its preserved delay");
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
	const std::vector<int32_t> expected = {0, 0, 0, 0, 1, 1, 1, 1, 0};
	expect(core.getStates() == expected, "zero-write gates use their Boolean identities");
}

void expectUnaryGateEvaluation(ToolKind gateKind, int32_t highInputState, int32_t lowInputState, const std::string &name) {
	CompileInput input = makeInput(5, 1);
	setKind(input, 0, 0, ToolKind::Latch);
	setInitialState(input, 0, 0, 1);
	setKind(input, 1, 0, ToolKind::Read);
	setKind(input, 2, 0, ToolKind::Trace);
	setKind(input, 3, 0, ToolKind::Write);
	setKind(input, 4, 0, gateKind);
	SimulationCore core;
	CompileError error;
	std::vector<int32_t> changes;
	std::string toggleError;
	expect(core.compile(input, error), name + " unary pipeline compiles");
	expectState(core, input, 4, 0, lowInputState, name + " starts from its zero-input state");
	core.advanceTick();
	expectState(core, input, 4, 0, highInputState, name + " evaluates one high input");
	expect(core.toggleLatch(cellIndex(input, 0, 0), changes, toggleError), name + " source toggles low");
	core.advanceTick();
	expectState(core, input, 4, 0, lowInputState, name + " evaluates one low input");
	core.reset();
	expectState(core, input, 4, 0, lowInputState, name + " reset restores its zero-input state");
}

void testUnaryGateEvaluationModes() {
	expectUnaryGateEvaluation(ToolKind::Buffer, 1, 0, "Buffer");
	expectUnaryGateEvaluation(ToolKind::And, 1, 0, "AND");
	expectUnaryGateEvaluation(ToolKind::Or, 1, 0, "OR");
	expectUnaryGateEvaluation(ToolKind::Xor, 1, 0, "XOR");
	expectUnaryGateEvaluation(ToolKind::Not, 0, 1, "NOT");
	expectUnaryGateEvaluation(ToolKind::Nand, 0, 1, "NAND");
	expectUnaryGateEvaluation(ToolKind::Nor, 0, 1, "NOR");
	expectUnaryGateEvaluation(ToolKind::Xnor, 0, 1, "XNOR");
	expectUnaryGateEvaluation(ToolKind::Led, 1, 0, "LED");
}

void expectBinaryGateEvaluation(ToolKind gateKind, const std::vector<int32_t> &expectedStates, const std::string &name) {
	CompileInput input = makeInput(6, 6);
	setKind(input, 0, 1, ToolKind::Latch);
	setKind(input, 1, 1, ToolKind::Read);
	setKind(input, 2, 1, ToolKind::Trace);
	setKind(input, 3, 1, ToolKind::Trace);
	setKind(input, 3, 2, ToolKind::Trace);
	setKind(input, 4, 2, ToolKind::Write);
	setKind(input, 5, 2, gateKind);
	setKind(input, 0, 5, ToolKind::Latch);
	setKind(input, 1, 5, ToolKind::Read);
	setKind(input, 2, 5, ToolKind::Trace);
	setKind(input, 3, 5, ToolKind::Trace);
	setKind(input, 4, 5, ToolKind::Trace);
	setKind(input, 5, 5, ToolKind::Trace);
	setKind(input, 5, 4, ToolKind::Trace);
	setKind(input, 5, 3, ToolKind::Write);
	SimulationCore core;
	CompileError error;
	std::vector<int32_t> changes;
	std::string toggleError;
	expect(expectedStates.size() == 4U, name + " has a complete truth table");
	const bool compiled = core.compile(input, error);
	expect(
			compiled,
			name + " dual-input circuit compiles: " + error.errorReason + " at (" + std::to_string(error.errorX) + ", " +
					std::to_string(error.errorY) + ")");
	expectState(core, input, 5, 2, expectedStates[0], name + " evaluates 00");
	expect(core.toggleLatch(cellIndex(input, 0, 1), changes, toggleError), name + " first input toggles high");
	core.advanceTick();
	expectState(core, input, 5, 2, expectedStates[1], name + " evaluates 10");
	expect(core.toggleLatch(cellIndex(input, 0, 5), changes, toggleError), name + " second input toggles high");
	core.advanceTick();
	expectState(core, input, 5, 2, expectedStates[3], name + " evaluates 11");
	expect(core.toggleLatch(cellIndex(input, 0, 1), changes, toggleError), name + " first input toggles low");
	core.advanceTick();
	expectState(core, input, 5, 2, expectedStates[2], name + " evaluates 01");
	expect(core.toggleLatch(cellIndex(input, 0, 5), changes, toggleError), name + " second input toggles low");
	core.advanceTick();
	expectState(core, input, 5, 2, expectedStates[0], name + " returns to 00");
}

void testBinaryGateEvaluationModes() {
	expectBinaryGateEvaluation(ToolKind::Buffer, {0, 1, 1, 1}, "Buffer");
	expectBinaryGateEvaluation(ToolKind::And, {0, 0, 0, 1}, "AND");
	expectBinaryGateEvaluation(ToolKind::Not, {1, 0, 0, 0}, "NOT");
	expectBinaryGateEvaluation(ToolKind::Nand, {1, 1, 1, 0}, "NAND");
	expectBinaryGateEvaluation(ToolKind::Or, {0, 1, 1, 1}, "OR");
	expectBinaryGateEvaluation(ToolKind::Nor, {1, 0, 0, 0}, "NOR");
	expectBinaryGateEvaluation(ToolKind::Xor, {0, 1, 1, 0}, "XOR");
	expectBinaryGateEvaluation(ToolKind::Xnor, {1, 0, 0, 1}, "XNOR");
	expectBinaryGateEvaluation(ToolKind::Led, {0, 1, 1, 1}, "LED");
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
	expect(!snapshot.empty(), "snapshot captures the aggregated connector payload");
	core.advanceTick();
	expect(core.getStates() != expectedStates, "second tick changes the direct connector chain");
	std::string restoreError;
	expect(core.restoreState(snapshot, restoreError), "snapshot restores onto the same topology");
	expect(core.getStates() == expectedStates, "snapshot restores every visible state");
	core.advanceTick();
	expectState(core, input, 3, 1, 1, "snapshot restores the pending unary Buffer transition");
	core.reset();
	expectState(core, input, 1, 0, 0, "reset clears the Read output Trace");
	expectState(core, input, 2, 1, 0, "reset clears the direct Read-to-Write signal");
	expectState(core, input, 3, 1, 0, "reset clears the logical target");
}

} // namespace

int main() {
	testReadWritePipeline();
	testBatchAdvanceMatchesSingleTicks();
	testConnectorQueueEventEncoding();
	testGateAndClockCommitBeforeDrain();
	testInputDrivenLatchPreservesNormalFlushDelay();
	testInputDrivenLatchIgnoresStaticWriteState();
	testMixedDeferredAndNormalGateFrontiers();
	testSnapshotRestoresPendingLatchTransition();
	testTransparentConnectorSnapshotRestoresPendingGate();
	testDirectComponentTargetsPreserveTickBarrier();
	testEncodedDirectComponentTargetPreservesDeferredState();
	testSharedConnectorMultipleSourceDelta();
	testOppositeClockFanoutPreservesResolvedConnector();
	testUnequalDepthConnectorDiamondConverges();
	testConnectorQueueSpansTopologicalRankWords();
	testLargeComponentFrontierPropagatesAcrossLanes();
	testRuntimeArenaUsesOnePageAlignedAllocationAcrossLargeRecompile();
	testSparseGateFrontierClearsPreviousTick();
	testSparseGateFrontierHandlesNonMonotonicSummaryIndices();
	testQueuedComponentGateTracksLaterDelta();
	testQueuedComponentBucketsTrackUpdates();
	testTerminalConnectorAliases();
	testSilentAdvanceDrainsOnlyFinalChanges();
	testDeferredVisibleStateMaterialization();
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
	testAggregatedReadAndWritePorts();
	testMergedGateAcceptsDistributedWritePorts();
	testWriteMultiplicity();
	testMultiWriteGatePropagatesAllInputs();
	testLatchMultipleRisingEdgesCancel();
	testAdjacentReadWriteGroupsShareOneLogicalPort();
	testManualLatchTogglePreservesQueuedWriteEdge();
	testRelayBypassPreservesInputMultiplicity();
	testRelayBypassPreservesFeedbackDelay();
	testContinuousCrossChannels();
	testCrossAxesRemainIsolated();
	testMultiColorMeshConnectivity();
	testLatchInitialStateVariantsRemainSeparate();
	testLatchToggle();
	testZeroWriteGateIdentities();
	testUnaryGateEvaluationModes();
	testBinaryGateEvaluationModes();
	testSnapshotRestore();
	return 0;
}
