#pragma once

#include <array>
#include <atomic>
#include <cstddef>
#include <cstdint>
#include <memory>
#include <thread>
#include <type_traits>

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>

#include "SimulationCore.hpp"

namespace ocb {

class OcbSimulation : public godot::RefCounted {
	GDCLASS(OcbSimulation, godot::RefCounted)

public:
	~OcbSimulation();

	godot::Dictionary compileGrid(
			const godot::PackedInt32Array &kinds,
			const godot::PackedInt32Array &initialStates,
			const godot::PackedInt32Array &clockHoldTicks,
			const godot::PackedInt32Array &meshIds,
			int32_t width,
			int32_t height);
	godot::PackedInt32Array advanceTick();
	godot::PackedInt32Array advanceTicks(int32_t tickCount);
	void advanceTicksSilent(int32_t tickCount);
	godot::Dictionary advanceTicksForDuration(int64_t durationUsec, int32_t maximumTickCount, int32_t batchTickCount);
	godot::Dictionary advanceTicksForDurationAndDrainStateChanges(
			int64_t durationUsec, int32_t maximumTickCount, int32_t batchTickCount);
	godot::PackedInt32Array drainStateChanges();
	godot::PackedInt32Array getStates();
	godot::PackedByteArray getStateBytes();
	godot::Dictionary toggleLatch(int32_t cellIndex);
	godot::PackedInt32Array reset();
	godot::PackedByteArray captureState();
	godot::Dictionary restoreState(const godot::PackedByteArray &snapshot);
	godot::Dictionary restoreStateSilent(const godot::PackedByteArray &snapshot);
	godot::Dictionary startAsync(int32_t batchTickCount, int64_t publishIntervalUsec);
	godot::Dictionary startAsyncWithBudget(int32_t batchTickCount, int64_t publishIntervalUsec, int64_t batchBudgetUsec);
	godot::Dictionary pollAsync();
	godot::Dictionary stopAsync();
	bool isAsyncRunning() const;

protected:
	static void _bind_methods();

private:
	static godot::PackedInt32Array makePackedInt32Array(const int32_t *values, size_t valueCount);
	static godot::PackedInt32Array makePackedInt32Array(const uint8_t *values, size_t valueCount);
	static godot::PackedByteArray makePackedByteArray(const uint8_t *values, size_t valueCount);

	static constexpr size_t AsyncFrameCount = 3;
	static constexpr uint32_t AsyncCommandCapacity = 64;
	static constexpr int32_t AdvanceCheckTickCount = 64;
	static constexpr int64_t AsyncDefaultBatchBudgetUsec = 2000;
	static constexpr size_t AsyncFullStateFallbackDivisor = 8;

	enum class AsyncCommandType : uint8_t {
		ToggleLatch,
	};

	struct AsyncCommand {
		AsyncCommandType type;
		int32_t cellIndex;
	};

	struct AsyncFrame {
		std::atomic<uint32_t> readerCount{0};
		uint64_t generation = 0;
		size_t changeValueCount = 0;
		bool isFullState = false;
		bool awaitingAcknowledgement = false;
	};

	static_assert(std::is_standard_layout_v<AsyncCommand> && std::is_trivially_copyable_v<AsyncCommand>);

	void allocateRuntimeBuffers();
	void clearRuntimeBuffers();
	size_t drainStateChangesToOutput();
	bool enqueueAsyncToggle(int32_t cellIndex);
	bool publishAsyncFrame();
	void processAsyncAcknowledgement();
	godot::Dictionary startAsyncInternal(int32_t batchTickCount, int64_t publishIntervalUsec, int64_t batchBudgetUsec);
	void runAsyncWorker();
	void stopAsyncWorker();

	SimulationCore core_;
	std::unique_ptr<int32_t[]> stateChangeBuffer_;
	std::unique_ptr<uint8_t[]> visibleStateBuffer_;
	size_t runtimeCellCount_ = 0;
	std::unique_ptr<uint8_t[]> asyncFullFrameStates_;
	std::array<AsyncFrame, AsyncFrameCount> asyncFrames_;
	std::array<AsyncCommand, AsyncCommandCapacity> asyncCommands_{};
	std::atomic<uint32_t> asyncCommandRead_{0};
	std::atomic<uint32_t> asyncCommandWrite_{0};
	std::atomic<bool> asyncStopRequested_{false};
	std::atomic<bool> asyncRunning_{false};
	std::atomic<int32_t> asyncPublishedFrame_{-1};
	std::atomic<uint64_t> asyncCompletedTickCount_{0};
	std::atomic<uint64_t> asyncAcknowledgedGeneration_{0};
	std::thread asyncWorker_;
	int32_t asyncBatchTickCount_ = 1;
	int64_t asyncBatchBudgetUsec_ = AsyncDefaultBatchBudgetUsec;
	int64_t asyncPublishIntervalUsec_ = 1;
	uint64_t asyncNextGeneration_ = 0;
	uint64_t asyncOutstandingGeneration_ = 0;
	int32_t asyncOutstandingFrame_ = -1;
	uint64_t asyncLastPresentedGeneration_ = 0;
	uint64_t asyncLastReportedTickCount_ = 0;
};

} // namespace ocb
