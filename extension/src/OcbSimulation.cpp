#include "OcbSimulation.hpp"

#include <algorithm>
#include <chrono>
#include <cstring>
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
	ClassDB::bind_method(godot::D_METHOD("getStateBytes"), &OcbSimulation::getStateBytes);
	ClassDB::bind_method(godot::D_METHOD("toggleLatch", "cellIndex"), &OcbSimulation::toggleLatch);
	ClassDB::bind_method(godot::D_METHOD("reset"), &OcbSimulation::reset);
	ClassDB::bind_method(godot::D_METHOD("captureState"), &OcbSimulation::captureState);
	ClassDB::bind_method(godot::D_METHOD("restoreState", "snapshot"), &OcbSimulation::restoreState);
	ClassDB::bind_method(godot::D_METHOD("restoreStateSilent", "snapshot"), &OcbSimulation::restoreStateSilent);
	ClassDB::bind_method(godot::D_METHOD("startAsync", "batchTickCount", "publishIntervalUsec"), &OcbSimulation::startAsync);
	ClassDB::bind_method(
			godot::D_METHOD("startAsyncWithBudget", "batchTickCount", "publishIntervalUsec", "batchBudgetUsec"),
			&OcbSimulation::startAsyncWithBudget);
	ClassDB::bind_method(godot::D_METHOD("pollAsync"), &OcbSimulation::pollAsync);
	ClassDB::bind_method(godot::D_METHOD("stopAsync"), &OcbSimulation::stopAsync);
	ClassDB::bind_method(godot::D_METHOD("isAsyncRunning"), &OcbSimulation::isAsyncRunning);
}

godot::PackedInt32Array OcbSimulation::makePackedInt32Array(const int32_t *values, size_t valueCount) {
	godot::PackedInt32Array result;
	result.resize(static_cast<int64_t>(valueCount));
	if (valueCount != 0) {
		assert(values != nullptr);
		std::memcpy(result.ptrw(), values, valueCount * sizeof(int32_t));
	}
	return result;
}

godot::PackedInt32Array OcbSimulation::makePackedInt32Array(const uint8_t *values, size_t valueCount) {
	godot::PackedInt32Array result;
	result.resize(static_cast<int64_t>(valueCount));
	if (valueCount != 0) {
		assert(values != nullptr);
		int32_t *output = result.ptrw();
		for (size_t index = 0; index < valueCount; ++index) {
			output[index] = values[index];
		}
	}
	return result;
}

void OcbSimulation::clearRuntimeBuffers() {
	stateChangeBuffer_.reset();
	visibleStateBuffer_.reset();
	asyncFullFrameStates_.reset();
	runtimeCellCount_ = 0;
	asyncPublishedFrame_.store(-1, std::memory_order_relaxed);
	asyncCompletedTickCount_.store(0, std::memory_order_relaxed);
	asyncAcknowledgedGeneration_.store(0, std::memory_order_relaxed);
	asyncOutstandingGeneration_ = 0;
	asyncOutstandingFrame_ = -1;
	asyncLastPresentedGeneration_ = 0;
	asyncLastReportedTickCount_ = 0;
	for (AsyncFrame &frame : asyncFrames_) {
		frame.readerCount.store(0, std::memory_order_relaxed);
		frame.generation = 0;
		frame.changeValueCount = 0;
		frame.isFullState = false;
		frame.awaitingAcknowledgement = false;
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
		if (!target.empty()) {
			std::memcpy(target.data(), source.ptr(), target.size() * sizeof(int32_t));
		}
	};
	copyArray(kinds, input.kinds);
	copyArray(initialStates, input.initialStates);
	copyArray(clockHoldTicks, input.clockHoldTicks);
	copyArray(meshIds, input.meshIds);

	CompileError error;
	godot::Dictionary result;
	if (!core_.compile(std::move(input), error)) {
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
			int32_t batchRemainingTickCount = std::min(batchTickCount, remainingTickCount);
			while (batchRemainingTickCount > 0 && std::chrono::steady_clock::now() < deadline) {
				const int32_t nextTickCount = std::min(batchRemainingTickCount, AdvanceCheckTickCount);
				core_.advanceTicksSilent(nextTickCount);
				advancedTickCount += nextTickCount;
				batchRemainingTickCount -= nextTickCount;
			}
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

godot::PackedByteArray OcbSimulation::getStateBytes() {
	stopAsyncWorker();
	if (visibleStateBuffer_ == nullptr || !core_.copyVisibleStates(visibleStateBuffer_.get(), runtimeCellCount_)) {
		return {};
	}
	godot::PackedByteArray result;
	result.resize(static_cast<int64_t>(runtimeCellCount_));
	if (runtimeCellCount_ != 0) {
		std::memcpy(result.ptrw(), visibleStateBuffer_.get(), runtimeCellCount_);
	}
	return result;
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
	if (!snapshot.empty()) {
		std::memcpy(result.ptrw(), snapshot.data(), snapshot.size());
	}
	return result;
}

godot::Dictionary OcbSimulation::restoreState(const godot::PackedByteArray &snapshot) {
	stopAsyncWorker();
	std::vector<uint8_t> bytes(static_cast<size_t>(snapshot.size()));
	if (!bytes.empty()) {
		std::memcpy(bytes.data(), snapshot.ptr(), bytes.size());
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

godot::Dictionary OcbSimulation::restoreStateSilent(const godot::PackedByteArray &snapshot) {
	stopAsyncWorker();
	std::vector<uint8_t> bytes(static_cast<size_t>(snapshot.size()));
	if (!bytes.empty()) {
		std::memcpy(bytes.data(), snapshot.ptr(), bytes.size());
	}
	std::string errorReason;
	godot::Dictionary result;
	if (!core_.restoreState(bytes, errorReason)) {
		result["ok"] = false;
		result["errorReason"] = godot::String(errorReason.c_str());
		return result;
	}
	result["ok"] = true;
	return result;
}

bool OcbSimulation::publishAsyncFrame() {
	if (asyncOutstandingGeneration_ != 0 || asyncFullFrameStates_ == nullptr || runtimeCellCount_ == 0 || stateChangeBuffer_ == nullptr) {
		return false;
	}
	const int32_t publishedFrame = asyncPublishedFrame_.load(std::memory_order_acquire);
	int32_t targetFrame = -1;
	for (int32_t frameIndex = 0; frameIndex < static_cast<int32_t>(AsyncFrameCount); ++frameIndex) {
		if (frameIndex == publishedFrame || asyncFrames_[frameIndex].awaitingAcknowledgement ||
				asyncFrames_[frameIndex].readerCount.load(std::memory_order_acquire) != 0) {
			continue;
		}
		targetFrame = frameIndex;
		break;
	}
	if (targetFrame < 0) {
		return false;
	}
	const size_t changeValueCount = drainStateChangesToOutput();
	assert((changeValueCount & 1U) == 0);
	if (changeValueCount == 0) {
		return false;
	}
	const uint8_t *visibleStates = core_.getVisibleStatesData();
	if (visibleStates == nullptr) {
		return false;
	}
	AsyncFrame &frame = asyncFrames_[targetFrame];
	const size_t fullStateThreshold = std::max<size_t>(1U, (runtimeCellCount_ + AsyncFullStateFallbackDivisor - 1U) /
			AsyncFullStateFallbackDivisor);
	frame.changeValueCount = changeValueCount;
	frame.isFullState = changeValueCount / 2U >= fullStateThreshold;
	if (frame.isFullState) {
		uint8_t *states = asyncFullFrameStates_.get() + static_cast<size_t>(targetFrame) * runtimeCellCount_;
		std::memcpy(states, visibleStates, runtimeCellCount_ * sizeof(uint8_t));
	}
	frame.generation = ++asyncNextGeneration_;
	frame.awaitingAcknowledgement = true;
	asyncOutstandingGeneration_ = frame.generation;
	asyncOutstandingFrame_ = targetFrame;
	asyncPublishedFrame_.store(targetFrame, std::memory_order_release);
	return true;
}

void OcbSimulation::processAsyncAcknowledgement() {
	const uint64_t acknowledgedGeneration = asyncAcknowledgedGeneration_.exchange(0, std::memory_order_acq_rel);
	if (acknowledgedGeneration == 0 || acknowledgedGeneration != asyncOutstandingGeneration_ || asyncOutstandingFrame_ < 0) {
		return;
	}
	AsyncFrame &frame = asyncFrames_[asyncOutstandingFrame_];
	if (!frame.awaitingAcknowledgement || frame.generation != acknowledgedGeneration) {
		return;
	}
	frame.awaitingAcknowledgement = false;
	asyncOutstandingGeneration_ = 0;
	asyncOutstandingFrame_ = -1;
}

void OcbSimulation::runAsyncWorker() {
	const auto publishInterval = std::chrono::microseconds(asyncPublishIntervalUsec_);
	auto lastPublishAt = std::chrono::steady_clock::now();
	while (!asyncStopRequested_.load(std::memory_order_acquire)) {
		processAsyncAcknowledgement();
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

		const auto batchStartedAt = std::chrono::steady_clock::now();
		int32_t remainingTickCount = asyncBatchTickCount_;
		while (remainingTickCount > 0 && !asyncStopRequested_.load(std::memory_order_acquire)) {
			const int32_t tickCount = std::min(remainingTickCount, AdvanceCheckTickCount);
			core_.advanceTicksSilent(tickCount);
			asyncCompletedTickCount_.fetch_add(static_cast<uint64_t>(tickCount), std::memory_order_relaxed);
			remainingTickCount -= tickCount;
			const auto now = std::chrono::steady_clock::now();
			if (now - batchStartedAt >= std::chrono::microseconds(asyncBatchBudgetUsec_) || now - lastPublishAt >= publishInterval) {
				break;
			}
		}
		const auto now = std::chrono::steady_clock::now();
		if (now - lastPublishAt >= publishInterval) {
			publishAsyncFrame();
			lastPublishAt = now;
		}
	}
	processAsyncAcknowledgement();
	if (asyncOutstandingGeneration_ == 0) {
		publishAsyncFrame();
	}
	core_.endDeferredVisualTracking();
	asyncRunning_.store(false, std::memory_order_release);
}

godot::Dictionary OcbSimulation::startAsync(int32_t batchTickCount, int64_t publishIntervalUsec) {
	return startAsyncInternal(batchTickCount, publishIntervalUsec, AsyncDefaultBatchBudgetUsec);
}

godot::Dictionary OcbSimulation::startAsyncWithBudget(
		int32_t batchTickCount, int64_t publishIntervalUsec, int64_t batchBudgetUsec) {
	return startAsyncInternal(batchTickCount, publishIntervalUsec, batchBudgetUsec);
}

godot::Dictionary OcbSimulation::startAsyncInternal(
		int32_t batchTickCount, int64_t publishIntervalUsec, int64_t batchBudgetUsec) {
	stopAsyncWorker();
	godot::Dictionary result;
	if (!core_.isCompiled() || runtimeCellCount_ == 0 || batchTickCount <= 0 || publishIntervalUsec <= 0 || batchBudgetUsec <= 0) {
		result["ok"] = false;
		result["errorReason"] = "simulation_async_configuration_invalid";
		return result;
	}
	try {
		asyncFullFrameStates_ = std::make_unique<uint8_t[]>(runtimeCellCount_ * AsyncFrameCount);
	} catch (const std::bad_alloc &) {
		asyncFullFrameStates_.reset();
		result["ok"] = false;
		result["errorReason"] = "simulation_async_allocation_failed";
		return result;
	}
	if (!core_.beginDeferredVisualTracking()) {
		asyncFullFrameStates_.reset();
		result["ok"] = false;
		result["errorReason"] = "simulation_async_start_failed";
		return result;
	}
	for (AsyncFrame &frame : asyncFrames_) {
		frame.readerCount.store(0, std::memory_order_relaxed);
		frame.generation = 0;
		frame.changeValueCount = 0;
		frame.isFullState = false;
		frame.awaitingAcknowledgement = false;
	}
	asyncCommandRead_.store(0, std::memory_order_relaxed);
	asyncCommandWrite_.store(0, std::memory_order_relaxed);
	asyncPublishedFrame_.store(-1, std::memory_order_relaxed);
	asyncCompletedTickCount_.store(0, std::memory_order_relaxed);
	asyncAcknowledgedGeneration_.store(0, std::memory_order_relaxed);
	asyncBatchTickCount_ = batchTickCount;
	asyncBatchBudgetUsec_ = batchBudgetUsec;
	asyncPublishIntervalUsec_ = publishIntervalUsec;
	asyncNextGeneration_ = 0;
	asyncOutstandingGeneration_ = 0;
	asyncOutstandingFrame_ = -1;
	asyncLastPresentedGeneration_ = 0;
	asyncLastReportedTickCount_ = 0;
	asyncStopRequested_.store(false, std::memory_order_release);
	asyncRunning_.store(true, std::memory_order_release);
	try {
		asyncWorker_ = std::thread(&OcbSimulation::runAsyncWorker, this);
	} catch (const std::system_error &) {
		asyncRunning_.store(false, std::memory_order_release);
		core_.endDeferredVisualTracking();
		asyncFullFrameStates_.reset();
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
	result["isFullState"] = false;
	if (asyncFullFrameStates_ == nullptr || stateChangeBuffer_ == nullptr) {
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
		if (frame.isFullState) {
			const uint8_t *states = asyncFullFrameStates_.get() + static_cast<size_t>(frameIndex) * runtimeCellCount_;
			godot::PackedInt32Array changes;
			changes.resize(static_cast<int64_t>(runtimeCellCount_ * 2U));
			int32_t *output = changes.ptrw();
			for (size_t cell = 0; cell < runtimeCellCount_; ++cell) {
				output[cell * 2U] = static_cast<int32_t>(cell);
				output[cell * 2U + 1U] = states[cell];
			}
			result["changes"] = changes;
			result["isFullState"] = true;
		} else {
			result["changes"] = makePackedInt32Array(stateChangeBuffer_.get(), frame.changeValueCount);
		}
		asyncLastPresentedGeneration_ = frame.generation;
		const uint64_t acknowledgedGeneration = frame.generation;
		frame.readerCount.fetch_sub(1, std::memory_order_release);
		asyncAcknowledgedGeneration_.store(acknowledgedGeneration, std::memory_order_release);
		return result;
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
