#include "OcbSimulation.hpp"

#include <algorithm>
#include <chrono>
#include <limits>
#include <new>
#include <system_error>
#include <vector>

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/string.hpp>

namespace ocb {
namespace {

int64_t clampToInt64(uint64_t value) {
	return static_cast<int64_t>(std::min<uint64_t>(value, std::numeric_limits<int64_t>::max()));
}

} // namespace

OcbSimulation::~OcbSimulation() {
	stopAsyncWorker();
}

void OcbSimulation::_bind_methods() {
	using godot::ClassDB;
	ClassDB::bind_method(
			godot::D_METHOD("compileGrid", "kinds", "initialStates", "clockHoldTicks", "meshIds", "width", "height"),
			&OcbSimulation::compileGrid);
	ClassDB::bind_method(godot::D_METHOD("advanceTick"), &OcbSimulation::advanceTick);
	ClassDB::bind_method(godot::D_METHOD("advanceTicks", "tickCount"), &OcbSimulation::advanceTicks);
	ClassDB::bind_method(godot::D_METHOD("advanceTicksSilent", "tickCount"), &OcbSimulation::advanceTicksSilent);
	ClassDB::bind_method(
			godot::D_METHOD("advanceTicksForDuration", "durationUsec", "maximumTickCount", "batchTickCount"),
			&OcbSimulation::advanceTicksForDuration);
	ClassDB::bind_method(
			godot::D_METHOD("advanceTicksForDurationAndDrainStateChanges", "durationUsec", "maximumTickCount", "batchTickCount"),
			&OcbSimulation::advanceTicksForDurationAndDrainStateChanges);
	ClassDB::bind_method(godot::D_METHOD("drainStateChanges"), &OcbSimulation::drainStateChanges);
	ClassDB::bind_method(godot::D_METHOD("getStates"), &OcbSimulation::getStates);
	ClassDB::bind_method(godot::D_METHOD("toggleLatch", "cellIndex"), &OcbSimulation::toggleLatch);
	ClassDB::bind_method(godot::D_METHOD("reset"), &OcbSimulation::reset);
	ClassDB::bind_method(godot::D_METHOD("captureState"), &OcbSimulation::captureState);
	ClassDB::bind_method(godot::D_METHOD("restoreState", "snapshot"), &OcbSimulation::restoreState);
	ClassDB::bind_method(godot::D_METHOD("startAsync", "batchTickCount", "publishIntervalUsec"), &OcbSimulation::startAsync);
	ClassDB::bind_method(godot::D_METHOD("pollAsync"), &OcbSimulation::pollAsync);
	ClassDB::bind_method(godot::D_METHOD("stopAsync"), &OcbSimulation::stopAsync);
	ClassDB::bind_method(godot::D_METHOD("isAsyncRunning"), &OcbSimulation::isAsyncRunning);
}

godot::PackedInt32Array OcbSimulation::makePackedInt32Array(const int32_t *values, size_t valueCount) {
	godot::PackedInt32Array result;
	result.resize(static_cast<int64_t>(valueCount));
	for (int64_t index = 0; index < static_cast<int64_t>(valueCount); ++index) {
		result[index] = values[static_cast<size_t>(index)];
	}
	return result;
}

godot::PackedInt32Array OcbSimulation::makePackedInt32Array(const uint8_t *values, size_t valueCount) {
	godot::PackedInt32Array result;
	result.resize(static_cast<int64_t>(valueCount));
	for (int64_t index = 0; index < static_cast<int64_t>(valueCount); ++index) {
		result[index] = values[static_cast<size_t>(index)];
	}
	return result;
}

void OcbSimulation::clearRuntimeBuffers() {
	stateChangeBuffer_.reset();
	visibleStateBuffer_.reset();
	asyncFrameStates_.reset();
	asyncPresentedStates_.reset();
	runtimeCellCount_ = 0;
	asyncPublishedFrame_.store(-1, std::memory_order_relaxed);
	asyncCompletedTickCount_.store(0, std::memory_order_relaxed);
	asyncLastPresentedGeneration_ = 0;
	asyncLastReportedTickCount_ = 0;
	for (AsyncFrame &frame : asyncFrames_) {
		frame.readerCount.store(0, std::memory_order_relaxed);
		frame.generation = 0;
	}
}

void OcbSimulation::allocateRuntimeBuffers() {
	clearRuntimeBuffers();
	const int32_t cellCount = core_.getVisibleCellCount();
	if (cellCount <= 0) {
		return;
	}
	runtimeCellCount_ = static_cast<size_t>(cellCount);
	stateChangeBuffer_ = std::make_unique<int32_t[]>(runtimeCellCount_ * 2U);
	visibleStateBuffer_ = std::make_unique<uint8_t[]>(runtimeCellCount_);
}

size_t OcbSimulation::drainStateChangesToOutput() {
	if (stateChangeBuffer_ == nullptr || runtimeCellCount_ == 0) {
		return 0;
	}
	return core_.drainStateChangesTo(stateChangeBuffer_.get(), runtimeCellCount_ * 2U);
}

godot::Dictionary OcbSimulation::compileGrid(
		const godot::PackedInt32Array &kinds,
		const godot::PackedInt32Array &initialStates,
		const godot::PackedInt32Array &clockHoldTicks,
		const godot::PackedInt32Array &meshIds,
		int32_t width,
		int32_t height) {
	stopAsyncWorker();
	clearRuntimeBuffers();
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
	if (!core_.compile(input, error)) {
		result["ok"] = false;
		result["errorX"] = error.errorX;
		result["errorY"] = error.errorY;
		result["errorReason"] = godot::String(error.errorReason.c_str());
		return result;
	}
	try {
		allocateRuntimeBuffers();
	} catch (const std::bad_alloc &) {
		clearRuntimeBuffers();
		result["ok"] = false;
		result["errorReason"] = "simulation_runtime_allocation_failed";
		return result;
	}
	result["ok"] = true;
	return result;
}

godot::PackedInt32Array OcbSimulation::advanceTick() {
	stopAsyncWorker();
	core_.advanceTicksSilent(1);
	const size_t changeCount = drainStateChangesToOutput();
	return makePackedInt32Array(stateChangeBuffer_.get(), changeCount);
}

godot::PackedInt32Array OcbSimulation::advanceTicks(int32_t tickCount) {
	stopAsyncWorker();
	if (tickCount <= 0) {
		return {};
	}
	core_.advanceTicksSilent(tickCount);
	const size_t changeCount = drainStateChangesToOutput();
	return makePackedInt32Array(stateChangeBuffer_.get(), changeCount);
}

void OcbSimulation::advanceTicksSilent(int32_t tickCount) {
	stopAsyncWorker();
	core_.advanceTicksSilent(tickCount);
}

godot::Dictionary OcbSimulation::advanceTicksForDuration(
		int64_t durationUsec, int32_t maximumTickCount, int32_t batchTickCount) {
	stopAsyncWorker();
	const auto startedAt = std::chrono::steady_clock::now();
	int64_t advancedTickCount = 0;
	if (core_.isCompiled() && durationUsec > 0 && maximumTickCount > 0 && batchTickCount > 0) {
		const auto deadline = startedAt + std::chrono::microseconds(durationUsec);
		while (advancedTickCount < maximumTickCount && std::chrono::steady_clock::now() < deadline) {
			const int32_t remainingTickCount = maximumTickCount - static_cast<int32_t>(advancedTickCount);
			const int32_t nextBatchTickCount = std::min(batchTickCount, remainingTickCount);
			core_.advanceTicksSilent(nextBatchTickCount);
			advancedTickCount += nextBatchTickCount;
		}
	}
	const int64_t elapsedUsec = std::chrono::duration_cast<std::chrono::microseconds>(
			std::chrono::steady_clock::now() - startedAt)
			.count();
	godot::Dictionary result;
	result["advancedTickCount"] = advancedTickCount;
	result["elapsedUsec"] = elapsedUsec;
	return result;
}

godot::Dictionary OcbSimulation::advanceTicksForDurationAndDrainStateChanges(
		int64_t durationUsec, int32_t maximumTickCount, int32_t batchTickCount) {
	godot::Dictionary result = advanceTicksForDuration(durationUsec, maximumTickCount, batchTickCount);
	const size_t changeCount = drainStateChangesToOutput();
	result["changes"] = makePackedInt32Array(stateChangeBuffer_.get(), changeCount);
	return result;
}

godot::PackedInt32Array OcbSimulation::drainStateChanges() {
	stopAsyncWorker();
	const size_t changeCount = drainStateChangesToOutput();
	return makePackedInt32Array(stateChangeBuffer_.get(), changeCount);
}

godot::PackedInt32Array OcbSimulation::getStates() {
	stopAsyncWorker();
	if (visibleStateBuffer_ == nullptr || !core_.copyVisibleStates(visibleStateBuffer_.get(), runtimeCellCount_)) {
		return {};
	}
	return makePackedInt32Array(visibleStateBuffer_.get(), runtimeCellCount_);
}

bool OcbSimulation::enqueueAsyncToggle(int32_t cellIndex) {
	const uint32_t writeIndex = asyncCommandWrite_.load(std::memory_order_relaxed);
	const uint32_t readIndex = asyncCommandRead_.load(std::memory_order_acquire);
	if (writeIndex - readIndex >= AsyncCommandCapacity) {
		return false;
	}
	asyncCommands_[writeIndex % AsyncCommandCapacity] = {AsyncCommandType::ToggleLatch, cellIndex};
	asyncCommandWrite_.store(writeIndex + 1U, std::memory_order_release);
	return true;
}

godot::Dictionary OcbSimulation::toggleLatch(int32_t cellIndex) {
	godot::Dictionary result;
	if (asyncRunning_.load(std::memory_order_acquire)) {
		if (!enqueueAsyncToggle(cellIndex)) {
			result["ok"] = false;
			result["errorReason"] = "simulation_async_command_queue_full";
			return result;
		}
		result["ok"] = true;
		result["queued"] = true;
		result["changes"] = godot::PackedInt32Array();
		return result;
	}
	stopAsyncWorker();
	std::string errorReason;
	if (!core_.toggleLatch(cellIndex, errorReason)) {
		result["ok"] = false;
		result["errorReason"] = godot::String(errorReason.c_str());
		return result;
	}
	const size_t changeCount = drainStateChangesToOutput();
	result["ok"] = true;
	result["changes"] = makePackedInt32Array(stateChangeBuffer_.get(), changeCount);
	return result;
}

godot::PackedInt32Array OcbSimulation::reset() {
	stopAsyncWorker();
	core_.resetSilent();
	const size_t changeCount = drainStateChangesToOutput();
	return makePackedInt32Array(stateChangeBuffer_.get(), changeCount);
}

godot::PackedByteArray OcbSimulation::captureState() {
	stopAsyncWorker();
	const std::vector<uint8_t> snapshot = core_.captureState();
	godot::PackedByteArray result;
	result.resize(static_cast<int64_t>(snapshot.size()));
	for (int64_t index = 0; index < static_cast<int64_t>(snapshot.size()); ++index) {
		result[index] = snapshot[static_cast<size_t>(index)];
	}
	return result;
}

godot::Dictionary OcbSimulation::restoreState(const godot::PackedByteArray &snapshot) {
	stopAsyncWorker();
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
	if (visibleStateBuffer_ == nullptr || !core_.copyVisibleStates(visibleStateBuffer_.get(), runtimeCellCount_)) {
		result["ok"] = false;
		result["errorReason"] = "simulation_runtime_buffer_unavailable";
		return result;
	}
	assert(stateChangeBuffer_ != nullptr);
	for (size_t cell = 0; cell < runtimeCellCount_; ++cell) {
		stateChangeBuffer_[cell * 2U] = static_cast<int32_t>(cell);
		stateChangeBuffer_[cell * 2U + 1U] = visibleStateBuffer_[cell];
	}
	result["ok"] = true;
	result["changes"] = makePackedInt32Array(stateChangeBuffer_.get(), runtimeCellCount_ * 2U);
	return result;
}

bool OcbSimulation::publishAsyncFrame() {
	if (asyncFrameStates_ == nullptr || runtimeCellCount_ == 0) {
		return false;
	}
	const int32_t publishedFrame = asyncPublishedFrame_.load(std::memory_order_acquire);
	int32_t targetFrame = -1;
	for (int32_t frameIndex = 0; frameIndex < static_cast<int32_t>(AsyncFrameCount); ++frameIndex) {
		if (frameIndex == publishedFrame || asyncFrames_[frameIndex].readerCount.load(std::memory_order_acquire) != 0) {
			continue;
		}
		targetFrame = frameIndex;
		break;
	}
	if (targetFrame < 0) {
		return false;
	}
	uint8_t *states = asyncFrameStates_.get() + static_cast<size_t>(targetFrame) * runtimeCellCount_;
	if (!core_.copyVisibleStates(states, runtimeCellCount_)) {
		return false;
	}
	AsyncFrame &frame = asyncFrames_[targetFrame];
	frame.generation = ++asyncNextGeneration_;
	asyncPublishedFrame_.store(targetFrame, std::memory_order_release);
	return true;
}

void OcbSimulation::runAsyncWorker() {
	const auto publishInterval = std::chrono::microseconds(asyncPublishIntervalUsec_);
	auto lastPublishAt = std::chrono::steady_clock::now();
	while (!asyncStopRequested_.load(std::memory_order_acquire)) {
		uint32_t readIndex = asyncCommandRead_.load(std::memory_order_relaxed);
		while (readIndex != asyncCommandWrite_.load(std::memory_order_acquire)) {
			const AsyncCommand command = asyncCommands_[readIndex % AsyncCommandCapacity];
			++readIndex;
			asyncCommandRead_.store(readIndex, std::memory_order_release);
			if (command.type == AsyncCommandType::ToggleLatch) {
				std::string ignoredError;
				core_.toggleLatch(command.cellIndex, ignoredError);
			}
		}
		core_.advanceTicksSilent(asyncBatchTickCount_);
		asyncCompletedTickCount_.fetch_add(static_cast<uint64_t>(asyncBatchTickCount_), std::memory_order_relaxed);
		const auto now = std::chrono::steady_clock::now();
		if (now - lastPublishAt >= publishInterval) {
			publishAsyncFrame();
			lastPublishAt = now;
		}
	}
	publishAsyncFrame();
	core_.endDeferredVisualTracking();
	asyncRunning_.store(false, std::memory_order_release);
}

godot::Dictionary OcbSimulation::startAsync(int32_t batchTickCount, int64_t publishIntervalUsec) {
	stopAsyncWorker();
	godot::Dictionary result;
	if (!core_.isCompiled() || runtimeCellCount_ == 0 || batchTickCount <= 0 || publishIntervalUsec <= 0) {
		result["ok"] = false;
		result["errorReason"] = "simulation_async_configuration_invalid";
		return result;
	}
	try {
		asyncFrameStates_ = std::make_unique<uint8_t[]>(runtimeCellCount_ * AsyncFrameCount);
		asyncPresentedStates_ = std::make_unique<uint8_t[]>(runtimeCellCount_);
	} catch (const std::bad_alloc &) {
		asyncFrameStates_.reset();
		asyncPresentedStates_.reset();
		result["ok"] = false;
		result["errorReason"] = "simulation_async_allocation_failed";
		return result;
	}
	if (!core_.copyVisibleStates(asyncPresentedStates_.get(), runtimeCellCount_) || !core_.beginDeferredVisualTracking()) {
		asyncFrameStates_.reset();
		asyncPresentedStates_.reset();
		result["ok"] = false;
		result["errorReason"] = "simulation_async_start_failed";
		return result;
	}
	for (AsyncFrame &frame : asyncFrames_) {
		frame.readerCount.store(0, std::memory_order_relaxed);
		frame.generation = 0;
	}
	asyncCommandRead_.store(0, std::memory_order_relaxed);
	asyncCommandWrite_.store(0, std::memory_order_relaxed);
	asyncPublishedFrame_.store(-1, std::memory_order_relaxed);
	asyncCompletedTickCount_.store(0, std::memory_order_relaxed);
	asyncBatchTickCount_ = batchTickCount;
	asyncPublishIntervalUsec_ = publishIntervalUsec;
	asyncNextGeneration_ = 0;
	asyncLastPresentedGeneration_ = 0;
	asyncLastReportedTickCount_ = 0;
	asyncStopRequested_.store(false, std::memory_order_release);
	asyncRunning_.store(true, std::memory_order_release);
	try {
		asyncWorker_ = std::thread(&OcbSimulation::runAsyncWorker, this);
	} catch (const std::system_error &) {
		asyncRunning_.store(false, std::memory_order_release);
		core_.endDeferredVisualTracking();
		asyncFrameStates_.reset();
		asyncPresentedStates_.reset();
		result["ok"] = false;
		result["errorReason"] = "simulation_async_thread_start_failed";
		return result;
	}
	result["ok"] = true;
	return result;
}

godot::Dictionary OcbSimulation::pollAsync() {
	godot::Dictionary result;
	result["ok"] = true;
	result["changes"] = godot::PackedInt32Array();
	const uint64_t completedTicks = asyncCompletedTickCount_.load(std::memory_order_acquire);
	const uint64_t advancedTicks = completedTicks - asyncLastReportedTickCount_;
	asyncLastReportedTickCount_ = completedTicks;
	result["advancedTickCount"] = clampToInt64(advancedTicks);
	result["running"] = asyncRunning_.load(std::memory_order_acquire);
	if (asyncFrameStates_ == nullptr || asyncPresentedStates_ == nullptr) {
		return result;
	}
	int32_t frameIndex = -1;
	while (true) {
		frameIndex = asyncPublishedFrame_.load(std::memory_order_acquire);
		if (frameIndex < 0) {
			return result;
		}
		asyncFrames_[frameIndex].readerCount.fetch_add(1, std::memory_order_acq_rel);
		if (asyncPublishedFrame_.load(std::memory_order_acquire) == frameIndex) {
			break;
		}
		asyncFrames_[frameIndex].readerCount.fetch_sub(1, std::memory_order_release);
	}
	AsyncFrame &frame = asyncFrames_[frameIndex];
	if (frame.generation > asyncLastPresentedGeneration_) {
		const uint8_t *states = asyncFrameStates_.get() + static_cast<size_t>(frameIndex) * runtimeCellCount_;
		size_t changeCount = 0;
		for (size_t cell = 0; cell < runtimeCellCount_; ++cell) {
			if (states[cell] != asyncPresentedStates_[cell]) {
				++changeCount;
			}
		}
		if (changeCount != 0) {
			godot::PackedInt32Array changes;
			changes.resize(static_cast<int64_t>(changeCount * 2U));
			size_t outputIndex = 0;
			for (size_t cell = 0; cell < runtimeCellCount_; ++cell) {
				const uint8_t state = states[cell];
				if (state == asyncPresentedStates_[cell]) {
					continue;
				}
				changes[static_cast<int64_t>(outputIndex++)] = static_cast<int32_t>(cell);
				changes[static_cast<int64_t>(outputIndex++)] = state;
				asyncPresentedStates_[cell] = state;
			}
			result["changes"] = changes;
		}
		asyncLastPresentedGeneration_ = frame.generation;
	}
	frame.readerCount.fetch_sub(1, std::memory_order_release);
	return result;
}

void OcbSimulation::stopAsyncWorker() {
	asyncStopRequested_.store(true, std::memory_order_release);
	if (asyncWorker_.joinable()) {
		asyncWorker_.join();
	}
	asyncRunning_.store(false, std::memory_order_release);
}

godot::Dictionary OcbSimulation::stopAsync() {
	stopAsyncWorker();
	godot::Dictionary result;
	result["ok"] = true;
	result["advancedTickCount"] = clampToInt64(asyncCompletedTickCount_.load(std::memory_order_acquire));
	return result;
}

bool OcbSimulation::isAsyncRunning() const {
	return asyncRunning_.load(std::memory_order_acquire);
}

} // namespace ocb
