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
	expect(core.getStates()[4] == 0, "buffer starts low");
	core.advanceTick();
	expect(core.getStates()[2] == 1, "Read drives trace one tick later");
	expect(core.getStates()[4] == 0, "Write does not pass through in the same tick");
	core.advanceTick();
	expect(core.getStates()[4] == 1, "Write updates target on the following tick");
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
	core.advanceTick();
	expectState(core, input, 3, 0, 1, "source Mesh endpoint is powered");
	expectState(core, input, 5, 0, 1, "remote same-ID Mesh endpoint is powered");
	expectState(core, input, 6, 0, 1, "remote Mesh drives its attached Trace");
	core.advanceTick();
	expectState(core, input, 8, 0, 1, "Write receives the remote Mesh network on the next tick");
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
	readCore.advanceTick();
	expectState(readCore, readInput, 2, 1, 1, "Read still drives a valid Trace output");

	CompileInput writeInput = makeInput(5, 2);
	setKind(writeInput, 0, 1, ToolKind::Latch);
	setInitialState(writeInput, 0, 1, 1);
	setKind(writeInput, 1, 1, ToolKind::Read);
	setKind(writeInput, 2, 1, ToolKind::Trace);
	setKind(writeInput, 3, 1, ToolKind::Write);
	setKind(writeInput, 4, 1, ToolKind::Led);
	setKind(writeInput, 3, 0, ToolKind::Clock);
	SimulationCore writeCore;
	expect(writeCore.compile(writeInput, error), "Write ignores unrelated adjacent components");
	writeCore.advanceTick();
	writeCore.advanceTick();
	expectState(writeCore, writeInput, 4, 1, 1, "Write still drives a valid target");
}

void testReadWriteRequireValidPorts() {
	CompileInput readInput = makeInput(3, 1);
	setKind(readInput, 0, 0, ToolKind::Latch);
	setKind(readInput, 1, 0, ToolKind::Read);
	setKind(readInput, 2, 0, ToolKind::BusYellow);
	SimulationCore readCore;
	CompileError error;
	expect(!readCore.compile(readInput, error), "Read still requires a valid Trace output");
	expect(error.errorReason == "read_requires_trace_output", "Read keeps its missing output diagnostic");

	CompileInput writeInput = makeInput(3, 1);
	setKind(writeInput, 0, 0, ToolKind::BusYellow);
	setKind(writeInput, 1, 0, ToolKind::Write);
	setKind(writeInput, 2, 0, ToolKind::Led);
	SimulationCore writeCore;
	expect(!writeCore.compile(writeInput, error), "Write still requires a valid Trace input");
	expect(error.errorReason == "write_requires_one_trace_input", "Write keeps its missing input diagnostic");

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
	expect(!writeWithTwoTraceSidesCore.compile(writeWithTwoTraceSides, error), "Write rejects two physical Trace sides on one network");
	expect(error.errorReason == "write_requires_one_trace_input", "Write preserves its physical Trace-side diagnostic");
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
	expect(changes == std::vector<int32_t>({0, 1, 1, 1, 2, 1}), "Latch toggle returns every immediately changed visible state");
	expectState(core, input, 0, 0, 1, "first merged Latch is on after toggle");
	expectState(core, input, 1, 0, 1, "clicked merged Latch is on after toggle");
	expectState(core, input, 3, 0, 0, "Latch toggle does not update Read output in the same tick");

	const std::vector<uint8_t> snapshot = core.captureState();
	core.advanceTick();
	expectState(core, input, 3, 0, 1, "toggled Latch reaches Read output on the next tick");
	std::string restoreError;
	expect(core.restoreState(snapshot, restoreError), "snapshot restores toggled Latch state");
	expectState(core, input, 0, 0, 1, "restored snapshot keeps toggled Latch state");
	expectState(core, input, 3, 0, 0, "restored snapshot keeps pre-tick Trace state");

	expect(core.toggleLatch(0, changes, toggleError), "toggled Latch can be toggled off again");
	expect(changes == std::vector<int32_t>({0, 0, 1, 0, 2, 0}), "second toggle returns every immediately changed off state");
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
	CompileInput input = makeInput(3, 1);
	input.kinds[0] = static_cast<int32_t>(ToolKind::Clock);
	input.kinds[1] = static_cast<int32_t>(ToolKind::Read);
	input.kinds[2] = static_cast<int32_t>(ToolKind::Trace);
	input.clockHoldTicks[0] = 1;
	SimulationCore core;
	CompileError error;
	expect(core.compile(input, error), "Clock source compiles");
	core.advanceTick();
	const std::vector<int32_t> expectedStates = core.getStates();
	const std::vector<uint8_t> snapshot = core.captureState();
	core.advanceTick();
	expect(core.getStates() != expectedStates, "second tick changes clock or trace state");
	std::string restoreError;
	expect(core.restoreState(snapshot, restoreError), "snapshot restores onto the same topology");
	expect(core.getStates() == expectedStates, "snapshot restores every visible state");
}

} // namespace

int main() {
	testReadWritePipeline();
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
