/*
 * Heap allocator module - Memory management for Nuclear Boot
 * 
 * Simplified version that uses a static array as heap to avoid
 * complex page mapping issues during early boot.
 */

use linked_list_allocator::LockedHeap;
use bootloader_api::BootInfo;

// Use a static array as heap to avoid page mapping complexity
pub const HEAP_START: usize = 0; // Not applicable for static array, but needed for logging
pub const HEAP_SIZE: usize = 100 * 1024; // 100 KiB
static mut HEAP: [u8; HEAP_SIZE] = [0; HEAP_SIZE];

// Temporarily disabled global allocator
// #[global_allocator]
// static ALLOCATOR: LockedHeap = LockedHeap::empty();

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct HeapInitError;

/// Initialize heap using static memory array
pub fn init_heap(_boot_info: &'static BootInfo) -> Result<(), HeapInitError> {
    // Temporarily disabled - no heap allocation
    // unsafe {
    //     ALLOCATOR.lock().init(HEAP.as_mut_ptr(), HEAP_SIZE);
    // }
    Ok(())
}
