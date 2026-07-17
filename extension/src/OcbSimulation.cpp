#include "OcbSimulation.hpp"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/string.hpp>

namespace ocb {

void OcbSimulation::_bind_methods() {
	using godot::ClassDB;
	ClassDB::bind_method(
			godot::D_METHOD("compileGrid", "kinds", "initialStates", "clockHoldTicks", "meshIds", "width", "height"),
			&OcbSimulation::compileGrid);
	ClassDB::bind_method(godot::D_METHOD("advanceTick"), &OcbSimulation::advanceTick);
	ClassDB::bind_method(godot::D_METHOD("advanceTicks", "tickCount"), &OcbSimulation::advanceTicks);
	ClassDB::bind_method(godot::D_METHOD("advanceTicksSilent", "tickCount"), &OcbSimulation::advanceTicksSilent);
	ClassDB::bind_method(godot::D_METHOD("drainStateChanges"), &OcbSimulation::drainStateChanges);
	ClassDB::bind_method(godot::D_METHOD("getStates"), &OcbSimulation::getStates);
	ClassDB::bind_method(godot::D_METHOD("toggleLatch", "cellIndex"), &OcbSimulation::toggleLatch);
	ClassDB::bind_method(godot::D_METHOD("reset"), &OcbSimulation::reset);
	ClassDB::bind_method(godot::D_METHOD("captureState"), &OcbSimulation::captureState);
	ClassDB::bind_method(godot::D_METHOD("restoreState", "snapshot"), &OcbSimulation::restoreState);
}

godot::PackedInt32Array OcbSimulation::makePackedInt32Array(const std::vector<int32_t> &values) {
	godot::PackedInt32Array result;
	result.resize(static_cast<int64_t>(values.size()));
	for (int64_t index = 0; index < static_cast<int64_t>(values.size()); ++index) {
		result[index] = values[static_cast<size_t>(index)];
	}
	return result;
}

godot::Dictionary OcbSimulation::compileGrid(
		const godot::PackedInt32Array &kinds,
		const godot::PackedInt32Array &initialStates,
		const godot::PackedInt32Array &clockHoldTicks,
		const godot::PackedInt32Array &meshIds,
		int32_t width,
		int32_t height) {
	CompileInput input;
	input.width = width;
	input.height = height;
	const auto copyArray = [](const godot::PackedInt32Array &source, std::vector<int32_t> &target) {
		target.resize(static_cast<size_t>(source.size()));
		for (int64_t index = 0; index < source.size(); ++index) {
			target[static_cast<size_t>(index)] = source[index];
		}
	};
	copyArray(kinds, input.kinds);
	copyArray(initialStates, input.initialStates);
	copyArray(clockHoldTicks, input.clockHoldTicks);
	copyArray(meshIds, input.meshIds);

	CompileError error;
	godot::Dictionary result;
	if (core_.compile(input, error)) {
		result["ok"] = true;
		return result;
	}
	result["ok"] = false;
	result["errorX"] = error.errorX;
	result["errorY"] = error.errorY;
	result["errorReason"] = godot::String(error.errorReason.c_str());
	return result;
}

godot::PackedInt32Array OcbSimulation::advanceTick() {
	return makePackedInt32Array(core_.advanceTick());
}

godot::PackedInt32Array OcbSimulation::advanceTicks(int32_t tickCount) {
	return makePackedInt32Array(core_.advanceTicks(tickCount));
}

godot::PackedInt32Array OcbSimulation::advanceTicksSilent(int32_t tickCount) {
	return makePackedInt32Array(core_.advanceTicksSilent(tickCount));
}

godot::PackedInt32Array OcbSimulation::drainStateChanges() {
	return makePackedInt32Array(core_.drainStateChanges());
}

godot::PackedInt32Array OcbSimulation::getStates() const {
	return makePackedInt32Array(core_.getStates());
}

godot::Dictionary OcbSimulation::toggleLatch(int32_t cellIndex) {
	std::vector<int32_t> changes;
	std::string errorReason;
	godot::Dictionary result;
	if (!core_.toggleLatch(cellIndex, changes, errorReason)) {
		result["ok"] = false;
		result["errorReason"] = godot::String(errorReason.c_str());
		return result;
	}
	result["ok"] = true;
	result["changes"] = makePackedInt32Array(changes);
	return result;
}

godot::PackedInt32Array OcbSimulation::reset() {
	return makePackedInt32Array(core_.reset());
}

godot::PackedByteArray OcbSimulation::captureState() const {
	const std::vector<uint8_t> snapshot = core_.captureState();
	godot::PackedByteArray result;
	result.resize(static_cast<int64_t>(snapshot.size()));
	for (int64_t index = 0; index < static_cast<int64_t>(snapshot.size()); ++index) {
		result[index] = snapshot[static_cast<size_t>(index)];
	}
	return result;
}

godot::Dictionary OcbSimulation::restoreState(const godot::PackedByteArray &snapshot) {
	std::vector<uint8_t> bytes(static_cast<size_t>(snapshot.size()));
	for (int64_t index = 0; index < snapshot.size(); ++index) {
		bytes[static_cast<size_t>(index)] = snapshot[index];
	}
	std::string errorReason;
	godot::Dictionary result;
	if (!core_.restoreState(bytes, errorReason)) {
		result["ok"] = false;
		result["errorReason"] = godot::String(errorReason.c_str());
		return result;
	}
	const std::vector<int32_t> states = core_.getStates();
	std::vector<int32_t> changes;
	changes.reserve(states.size() * 2U);
	for (int32_t cell = 0; cell < static_cast<int32_t>(states.size()); ++cell) {
		changes.push_back(cell);
		changes.push_back(states[cell]);
	}
	result["ok"] = true;
	result["changes"] = makePackedInt32Array(changes);
	return result;
}

} // namespace ocb
