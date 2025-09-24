/*
 * 🦀🔥 PhoenixGuard Nuclear Boot - Rust QEMU Demo 🔥🦀
 * 
 * Memory-safe bootloader that downloads OS from HTTPS
 * NO TFTP! NO PXE! NO BIOS! JUST PURE RUST POWER!
 */

#![no_std]
#![no_main]
#![feature(custom_test_frameworks)]
#![test_runner(crate::test_runner)]
#![reexport_test_harness_main = "test_main"]

// extern crate alloc; // Temporarily disabled

use core::panic::PanicInfo;
use bootloader_api::entry_point;
use bootloader_api::BootInfo;
use x86_64;

mod console;
mod allocator; 
mod network;
mod nuclear;
// TODO: Re-enable nuclear wipe modules after fixing macro imports
// mod wipe_engine;
// mod lockout_prevention;
// mod nuclear_wipe_demo;

#[macro_use]
mod logger;

// Macros are available at root due to #[macro_export]

// Entry point called by bootloader
entry_point!(nuclear_boot_main);

fn nuclear_boot_main(boot_info: &'static mut BootInfo) -> ! {
    // Direct serial output to see if we reach here
    let mut port = x86_64::instructions::port::Port::new(0x3f8);
    for byte in b"ENTRY: Nuclear boot main started\n" {
        unsafe { port.write(*byte); }
    }
    
    use logger::BootPhase;
    
    println!("🦀🔥 PhoenixGuard Nuclear Boot Starting! 🔥🦀");
    println!("===========================================");
    println!("");
    
    // TEMPORARY: Skip heap initialization to test basic boot
    boot_phase_start!(BootPhase::HeapInit);
    println!("Skipping heap initialization for now...");
    boot_phase_complete!(BootPhase::HeapInit);
    // match allocator::init_heap(boot_info) {
    //     Ok(_) => {
    //         boot_phase_complete!(BootPhase::HeapInit);
    //         log_info!("Heap allocated at 0x{:x}, size: {} KB", 
    //                  allocator::HEAP_START, 
    //                  allocator::HEAP_SIZE / 1024);
    //     }
    //     Err(_) => {
    //         boot_phase_failed!(BootPhase::HeapInit, "Failed to initialize heap");
    //         panic!("heap initialization failed");
    //     }
    // }
    
    boot_phase_start!(BootPhase::ConsoleInit);
    console::init();
    boot_phase_complete!(BootPhase::ConsoleInit);
    
    // Log memory map information
    logger::log_memory_regions(&boot_info.memory_regions);
    
    // Run nuclear boot sequence
    nuclear::run_nuclear_boot_sequence(boot_info);
}

#[cfg(not(test))]
#[panic_handler]
fn panic(info: &PanicInfo) -> ! {
    // Direct serial output to see panic
    let mut port = unsafe { x86_64::instructions::port::Port::new(0x3f8) };
    for byte in b"PANIC: panic occurred\n" {
        unsafe { port.write(*byte); }
    }
    
    println!("💀 NUCLEAR PANIC: {}", info);
    println!("🛑 System halted - press Ctrl+C to exit QEMU");
    
    loop {
        x86_64::instructions::hlt();
    }
}

// Test runner for unit tests
#[cfg(test)]
fn test_runner(tests: &[&dyn Fn()]) {
    println!("Running {} tests", tests.len());
    for test in tests {
        test();
    }
}

#[test_case]
fn trivial_assertion() {
    assert_eq!(1, 1);
}
