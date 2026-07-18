#pragma once

#include <algorithm>
#include <cassert>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <limits>
#include <new>
#include <type_traits>
#include <utility>
#include <vector>

namespace ocb {

struct RuntimeArenaDebugInfo {
	uintptr_t baseAddress = 0;
	size_t capacity = 0;
	size_t used = 0;
	uint32_t allocationCount = 0;
};

class RuntimeArena {
public:
	static constexpr size_t PageAlignment = 4096;
	static constexpr size_t CacheLineAlignment = 64;

	RuntimeArena() = default;
	RuntimeArena(const RuntimeArena &) = delete;
	RuntimeArena &operator=(const RuntimeArena &) = delete;

	~RuntimeArena() {
		reset();
	}

	void beginLayout() noexcept {
		reset();
		isPlanning_ = true;
		isValid_ = true;
	}

	bool allocatePlanned() noexcept {
		if (!isPlanning_ || !isValid_) {
			return false;
		}
		size_t roundedCapacity = 0;
		if (!alignUp(cursor_, PageAlignment, roundedCapacity)) {
			isValid_ = false;
			return false;
		}
		if (roundedCapacity != 0) {
			try {
				storage_ = static_cast<uint8_t *>(::operator new(roundedCapacity, std::align_val_t(PageAlignment)));
			} catch (const std::bad_alloc &) {
				isValid_ = false;
				return false;
			}
			++allocationCount_;
		}
		capacity_ = roundedCapacity;
		cursor_ = 0;
		isPlanning_ = false;
		return true;
	}

	void reset() noexcept {
		if (storage_ != nullptr) {
			::operator delete(storage_, std::align_val_t(PageAlignment));
		}
		storage_ = nullptr;
		capacity_ = 0;
		cursor_ = 0;
		allocationCount_ = 0;
		isPlanning_ = false;
		isValid_ = true;
	}

	template <typename T>
	T *take(size_t count, size_t requestedAlignment = alignof(T)) noexcept {
		static_assert(std::is_trivially_copyable_v<T>);
		static_assert(std::is_trivially_destructible_v<T>);
		if (count == 0) {
			return nullptr;
		}
		const size_t alignment = std::max({alignof(T), requestedAlignment, size_t{1}});
		assert((alignment & (alignment - 1U)) == 0);
		if ((alignment & (alignment - 1U)) != 0 || count > std::numeric_limits<size_t>::max() / sizeof(T)) {
			isValid_ = false;
			return nullptr;
		}
		const size_t byteCount = count * sizeof(T);
		size_t offset = 0;
		if (!alignUp(cursor_, alignment, offset) || offset > std::numeric_limits<size_t>::max() - byteCount) {
			isValid_ = false;
			return nullptr;
		}
		const size_t nextCursor = offset + byteCount;
		if (!isPlanning_ && nextCursor > capacity_) {
			isValid_ = false;
			return nullptr;
		}
		cursor_ = nextCursor;
		if (isPlanning_) {
			return nullptr;
		}
		return reinterpret_cast<T *>(storage_ + offset);
	}

	bool isValid() const {
		return isValid_;
	}

	bool contains(const void *data, size_t byteCount) const {
		if (byteCount == 0) {
			return data == nullptr || storage_ != nullptr;
		}
		if (storage_ == nullptr || data == nullptr) {
			return false;
		}
		const uintptr_t begin = reinterpret_cast<uintptr_t>(storage_);
		const uintptr_t end = begin + capacity_;
		const uintptr_t address = reinterpret_cast<uintptr_t>(data);
		return address >= begin && address <= end && byteCount <= static_cast<size_t>(end - address);
	}

	RuntimeArenaDebugInfo getDebugInfo() const {
		return {
			reinterpret_cast<uintptr_t>(storage_),
			capacity_,
			cursor_,
			allocationCount_,
		};
	}

private:
	static bool alignUp(size_t value, size_t alignment, size_t &result) noexcept {
		assert((alignment & (alignment - 1U)) == 0);
		const size_t padding = alignment - 1U;
		if (value > std::numeric_limits<size_t>::max() - padding) {
			return false;
		}
		result = (value + padding) & ~padding;
		return true;
	}

	uint8_t *storage_ = nullptr;
	size_t capacity_ = 0;
	size_t cursor_ = 0;
	uint32_t allocationCount_ = 0;
	bool isPlanning_ = false;
	bool isValid_ = true;
};

// Staging storage exists only while compile() builds the graph. After commit(), all access goes through the arena slice.
template <typename T>
class PodBuffer {
public:
	using Iterator = T *;
	using ConstIterator = const T *;

	static_assert(std::is_trivially_copyable_v<T>);
	static_assert(std::is_trivially_destructible_v<T>);

	PodBuffer() = default;

	PodBuffer(const PodBuffer &other) {
		assignFrom(other);
	}

	PodBuffer &operator=(const PodBuffer &other) {
		if (this != &other) {
			assignFrom(other);
		}
		return *this;
	}

	PodBuffer &operator=(const std::vector<T> &values) {
		assign(values.begin(), values.end());
		return *this;
	}

	PodBuffer &operator=(std::vector<T> &&values) {
		if (isCommitted_) {
			assert(values.size() <= capacity_);
			std::copy(values.begin(), values.end(), data_);
			size_ = values.size();
			values.clear();
			return *this;
		}
		staging_ = std::move(values);
		syncStagingView();
		return *this;
	}

	void reset() {
		std::vector<T>().swap(staging_);
		data_ = nullptr;
		size_ = 0;
		capacity_ = 0;
		isCommitted_ = false;
	}

	void clear() {
		if (isCommitted_) {
			size_ = 0;
			return;
		}
		staging_.clear();
		syncStagingView();
	}

	void clearRuntime() {
		assert(isCommitted_);
		size_ = 0;
	}

	void reserve(size_t capacity) {
		if (isCommitted_) {
			assert(capacity <= capacity_);
			return;
		}
		staging_.reserve(capacity);
		syncStagingView();
	}

	void assign(size_t count, const T &value) {
		if (isCommitted_) {
			assert(count <= capacity_);
			std::fill(data_, data_ + count, value);
			size_ = count;
			return;
		}
		staging_.assign(count, value);
		syncStagingView();
	}

	template <typename IteratorType, typename = std::enable_if_t<!std::is_integral_v<IteratorType>>>
	void assign(IteratorType first, IteratorType last) {
		if (isCommitted_) {
			const size_t count = static_cast<size_t>(last - first);
			assert(count <= capacity_);
			std::copy(first, last, data_);
			size_ = count;
			return;
		}
		staging_.assign(first, last);
		syncStagingView();
	}

	void resize(size_t count) {
		resize(count, T{});
	}

	void resize(size_t count, const T &value) {
		if (isCommitted_) {
			assert(count <= capacity_);
			if (count > size_) {
				std::fill(data_ + size_, data_ + count, value);
			}
			size_ = count;
			return;
		}
		staging_.resize(count, value);
		syncStagingView();
	}

	void push_back(const T &value) {
		if (isCommitted_) {
			assert(size_ < capacity_);
			data_[size_++] = value;
			return;
		}
		staging_.push_back(value);
		syncStagingView();
	}

	void pushBackRuntime(const T &value) {
		assert(isCommitted_);
		assert(size_ < capacity_);
		data_[size_++] = value;
	}

	void swap(PodBuffer &other) {
		if (isCommitted_ || other.isCommitted_) {
			assert(isCommitted_ && other.isCommitted_);
			std::swap(data_, other.data_);
			std::swap(size_, other.size_);
			std::swap(capacity_, other.capacity_);
			return;
		}
		staging_.swap(other.staging_);
		syncStagingView();
		other.syncStagingView();
	}

	bool plan(RuntimeArena &arena, size_t alignment = RuntimeArena::CacheLineAlignment) const {
		if (isCommitted_) {
			return false;
		}
		arena.template take<T>(staging_.capacity(), alignment);
		return arena.isValid();
	}

	bool commit(RuntimeArena &arena, size_t alignment = RuntimeArena::CacheLineAlignment) {
		if (isCommitted_) {
			return false;
		}
		const size_t stagingCapacity = staging_.capacity();
		const size_t stagingSize = staging_.size();
		T *target = arena.template take<T>(stagingCapacity, alignment);
		if (stagingCapacity != 0 && target == nullptr) {
			return false;
		}
		if (stagingSize != 0) {
			std::memcpy(target, staging_.data(), stagingSize * sizeof(T));
		}
		std::vector<T>().swap(staging_);
		data_ = target;
		size_ = stagingSize;
		capacity_ = stagingCapacity;
		isCommitted_ = true;
		return true;
	}

	bool isCommitted() const {
		return isCommitted_;
	}

	size_t size() const {
		return size_;
	}

	size_t capacity() const {
		return capacity_;
	}

	bool empty() const {
		return size() == 0;
	}

	T *data() {
		return data_;
	}

	const T *data() const {
		return data_;
	}

	T &operator[](size_t index) {
		assert(index < size());
		return data()[index];
	}

	const T &operator[](size_t index) const {
		assert(index < size());
		return data()[index];
	}

	T &back() {
		assert(!empty());
		return (*this)[size() - 1U];
	}

	const T &back() const {
		assert(!empty());
		return (*this)[size() - 1U];
	}

	Iterator begin() {
		return data();
	}

	Iterator end() {
		return empty() ? data() : data() + size();
	}

	ConstIterator begin() const {
		return data();
	}

	ConstIterator end() const {
		return empty() ? data() : data() + size();
	}

	bool isInArena(const RuntimeArena &arena) const {
		return capacity() == 0 || arena.contains(data(), capacity() * sizeof(T));
	}

	bool isAligned(size_t alignment) const {
		assert((alignment & (alignment - 1U)) == 0);
		return capacity() == 0 || (reinterpret_cast<uintptr_t>(data()) & (alignment - 1U)) == 0;
	}

private:
	void assignFrom(const PodBuffer &other) {
		if (isCommitted_) {
			assert(other.size() <= capacity_);
			std::copy(other.begin(), other.end(), data_);
			size_ = other.size();
			return;
		}
		staging_.assign(other.begin(), other.end());
		syncStagingView();
	}

	void syncStagingView() {
		data_ = staging_.data();
		size_ = staging_.size();
		capacity_ = staging_.capacity();
	}

	std::vector<T> staging_;
	T *data_ = nullptr;
	size_t size_ = 0;
	size_t capacity_ = 0;
	bool isCommitted_ = false;
};

} // namespace ocb
