use std::alloc::{Layout, alloc_zeroed, dealloc, handle_alloc_error};
use std::{
    marker::PhantomData,
    ops::{Deref, DerefMut},
    ptr::NonNull,
    sync::Arc,
};

// Private POD buffers own non-overlapping regions. The only unsafe code in the
// simulation is the allocator and the slices below. No raw pointer is exported.
struct Storage {
    Pointer: NonNull<u8>,
    Layout: Layout,
}
unsafe impl Send for Storage {}
unsafe impl Sync for Storage {}
impl Drop for Storage {
    fn drop(&mut self) {
        unsafe {
            dealloc(self.Pointer.as_ptr(), self.Layout);
        }
    }
}
pub struct Arena {
    Storage: Arc<Storage>,
    Cursor: usize,
}
impl Arena {
    pub fn new(bytes: usize) -> Self {
        let layout = Layout::from_size_align(bytes.max(1).div_ceil(4096) * 4096, 4096)
            .expect("bounded runtime allocation");
        let pointer = NonNull::new(unsafe { alloc_zeroed(layout) })
            .unwrap_or_else(|| handle_alloc_error(layout));
        Self {
            Storage: Arc::new(Storage {
                Pointer: pointer,
                Layout: layout,
            }),
            Cursor: 0,
        }
    }
    pub fn take<T: Copy>(&mut self, values: Vec<T>) -> Buffer<T> {
        let offset = self.Cursor.div_ceil(64) * 64;
        let bytes = std::mem::size_of_val(values.as_slice());
        assert!(std::mem::align_of::<T>() <= 64 && offset + bytes <= self.Storage.Layout.size());
        self.Cursor = offset + bytes;
        let pointer = unsafe {
            NonNull::new_unchecked(self.Storage.Pointer.as_ptr().add(offset).cast::<T>())
        };
        unsafe {
            std::ptr::copy_nonoverlapping(values.as_ptr(), pointer.as_ptr(), values.len());
        }
        Buffer {
            Pointer: pointer,
            Length: values.len(),
            Storage: Some(self.Storage.clone()),
            Marker: PhantomData,
        }
    }
}
pub struct Buffer<T: Copy> {
    Pointer: NonNull<T>,
    Length: usize,
    #[allow(dead_code)]
    Storage: Option<Arc<Storage>>,
    Marker: PhantomData<T>,
}
unsafe impl<T: Copy + Send> Send for Buffer<T> {}
impl<T: Copy> Default for Buffer<T> {
    fn default() -> Self {
        Self {
            Pointer: NonNull::dangling(),
            Length: 0,
            Storage: None,
            Marker: PhantomData,
        }
    }
}
impl<T: Copy> Deref for Buffer<T> {
    type Target = [T];
    fn deref(&self) -> &[T] {
        unsafe { std::slice::from_raw_parts(self.Pointer.as_ptr(), self.Length) }
    }
}
impl<T: Copy> DerefMut for Buffer<T> {
    fn deref_mut(&mut self) -> &mut [T] {
        unsafe { std::slice::from_raw_parts_mut(self.Pointer.as_ptr(), self.Length) }
    }
}
#[cfg(test)]
impl<T: Copy> Buffer<T> {
    pub fn allocationAddress(&self) -> usize {
        self.Storage
            .as_ref()
            .map_or(0, |s| s.Pointer.as_ptr() as usize)
    }
    pub fn address(&self) -> usize {
        self.Pointer.as_ptr() as usize
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn regionsAreAlignedDisjointAndRetainStorage() {
        let mut arena = Arena::new(8192);
        let mut a = arena.take(vec![3u32; 33]);
        let b = arena.take(vec![7u8; 128]);
        assert_eq!(a.allocationAddress() % 4096, 0);
        assert_eq!(a.allocationAddress(), b.allocationAddress());
        assert_eq!(a.address() % 64, 0);
        assert_eq!(b.address() % 64, 0);
        assert!(b.address() >= a.address() + std::mem::size_of_val(&*a));
        drop(arena);
        a[0] = 9;
        assert_eq!(a[0], 9);
        assert_eq!(b[0], 7);
    }
}
// Indices originate in the validated, immutable execution graph. Debug builds
// retain slice bounds checks; release avoids repeating them for every tick edge.
impl<T: Copy, I: std::slice::SliceIndex<[T]> + Clone> std::ops::Index<I> for Buffer<T> {
    type Output = I::Output;
    #[inline(always)]
    fn index(&self, index: I) -> &Self::Output {
        let slice = unsafe { std::slice::from_raw_parts(self.Pointer.as_ptr(), self.Length) };
        debug_assert!(
            slice.get(index.clone()).is_some(),
            "runtime graph index out of range"
        );
        unsafe { slice.get_unchecked(index) }
    }
}
impl<T: Copy, I: std::slice::SliceIndex<[T]> + Clone> std::ops::IndexMut<I> for Buffer<T> {
    #[inline(always)]
    fn index_mut(&mut self, index: I) -> &mut Self::Output {
        let slice = unsafe { std::slice::from_raw_parts_mut(self.Pointer.as_ptr(), self.Length) };
        debug_assert!(
            slice.get(index.clone()).is_some(),
            "runtime graph index out of range"
        );
        unsafe { slice.get_unchecked_mut(index) }
    }
}
