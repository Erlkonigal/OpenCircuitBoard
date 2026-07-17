#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>

#include "SimulationCore.hpp"

namespace ocb {

class OcbSimulation : public godot::RefCounted {
	GDCLASS(OcbSimulation, godot::RefCounted)

public:
	godot::Dictionary compileGrid(
			const godot::PackedInt32Array &kinds,
			const godot::PackedInt32Array &initialStates,
			const godot::PackedInt32Array &clockHoldTicks,
			const godot::PackedInt32Array &meshIds,
			int32_t width,
			int32_t height);
	godot::PackedInt32Array advanceTick();
	godot::PackedInt32Array advanceTicks(int32_t tickCount);
	godot::PackedInt32Array advanceTicksSilent(int32_t tickCount);
	godot::PackedInt32Array drainStateChanges();
	godot::PackedInt32Array getStates() const;
	godot::Dictionary toggleLatch(int32_t cellIndex);
	godot::PackedInt32Array reset();
	godot::PackedByteArray captureState() const;
	godot::Dictionary restoreState(const godot::PackedByteArray &snapshot);

protected:
	static void _bind_methods();

private:
	static godot::PackedInt32Array makePackedInt32Array(const std::vector<int32_t> &values);
	SimulationCore core_;
};

} // namespace ocb
