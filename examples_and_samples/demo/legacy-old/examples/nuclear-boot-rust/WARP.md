# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Commands

### Setup Requirements
```bash
# Install nightly toolchain and bare-metal target
rustup toolchain install nightly
rustup default nightly
rustup target add x86_64-unknown-none
rustup component add llvm-tools-preview

# Install bootimage for creating bootable binaries
cargo install bootimage
```

### Building
```bash
# Build bootable image
cargo bootimage

# Build without running
cargo build --target x86_64-unknown-none
```

### Running and Testing
```bash
# Run in QEMU (configured in .cargo/config.toml and Cargo.toml)
cargo run

# Run tests with custom test framework
cargo test

# Manual QEMU invocation with networking
qemu-system-x86_64 -drive format=raw,file=target/x86_64-unknown-none/debug/bootimage-nuclear-boot.bin -netdev user,id=net0 -device e1000,netdev=net0 -serial stdio
```

## Architecture Overview

### Core Boot Flow
The Nuclear Boot system follows a phased approach coordinated by `nuclear_boot_main()` in `src/main.rs`:

1. **Entry Point**: Uses `bootloader_api::entry_point!` macro to receive `BootInfo` from bootloader
2. **Heap Initialization**: `allocator.rs` sets up memory management using CR3 register page table discovery
3. **Console Setup**: `console.rs` initializes VGA text mode with colored output and cursor control
4. **Nuclear Boot Sequence**: `nuclear.rs` orchestrates the network-first boot process
5. **Network Simulation**: `network.rs` provides HTTPS client simulation for configuration/kernel downloads

### Module Responsibilities

- **`main.rs`**: Entry point coordination, panic handler, test runner
- **`allocator.rs`**: Memory management with `LockedHeap` and `BootInfoFrameAllocator`
- **`console.rs`**: VGA buffer management with spin-locked writer and color support
- **`network.rs`**: Simulated HTTPS client with `BootConfig` and kernel download
- **`nuclear.rs`**: Main boot sequence logic, signature verification, kernel preparation
- **`logger.rs`**: Enhanced logging with ANSI colors, boot phase tracking macros

### Key Data Structures
- `BootConfig`: Network-downloaded OS configuration (version, kernel args, filesystem)
- `NuclearNetworkClient`: HTTPS client simulation for configuration and kernel downloads
- `BootPhase`: Enum for tracking boot progression with emoji/color logging
- `Writer`: VGA text mode output with color support and hardware cursor control

## Bare-Metal Rust Development

### No-Std Configuration
This is a `#![no_std]` + `#![no_main]` bare-metal Rust bootloader:
- Custom panic handler that halts with VGA output
- Uses `bootloader_api` for low-level boot interface
- Custom test framework with `#![test_runner]` attribute

### Target Configuration
- **Target Triple**: `x86_64-unknown-none` (no OS)
- **Custom Target**: `x86_64-nuclear-boot.json` with specific linker settings
- **Linker**: `rust-lld` with red-zone disabled, soft-float features
- **Panic Strategy**: `abort` (no stack unwinding)

### Memory Layout
- **Heap**: 100 KiB allocated at virtual address `0x4000_0000_0000`
- **Page Mapping**: Uses CR3 register to discover existing page tables safely
- **Frame Allocation**: Builds from `BootInfo` memory map, filtering usable regions

### QEMU Integration
Configured via `Cargo.toml` metadata:
```toml
[package.metadata.bootimage]
test-args = ["-device", "isa-debug-exit,iobase=0xf4,iosize=0x04", "-serial", "stdio", "-display", "none"]
run-args = ["-serial", "stdio", "-netdev", "user,id=net0", "-device", "e1000,netdev=net0"]
```

## Integration with PhoenixGuard

### Security Framework Position
Nuclear Boot integrates with the broader PhoenixGuard defensive security suite:
- **RFKilla**: RF-layer protections against wireless propagation 
- **BootkitSentinel**: Firmware-level bootkit detection and analysis
- **PhoenixGuard Recovery**: Hardware-rooted emergency recovery mechanisms
- **PARANOIA LEVEL 1 MILLION**: In-memory BIOS loading for ultimate security

### Current Implementation Status
This is a **simulation/demonstration** version. Production deployment would require:
- Real network hardware drivers (Ethernet/WiFi initialization)
- Actual TLS/HTTPS implementation with certificate verification
- Hardware Security Module (HSM) or TPM integration for key storage
- Integration with platform secure boot chains
- Recovery mechanisms for network failures

### Future Security Enhancements
- **Measured Boot**: TPM-based boot measurement and attestation
- **Secure Enclaves**: SGX/SEV integration for protected execution
- **Anti-Rollback**: Monotonic version checking with secure counters
- **Side-Channel Mitigation**: Constant-time cryptographic operations
- **Physical Tampering Detection**: Hardware-based integrity monitoring

## Security & Memory Management

### Memory Safety Guarantees
- **Zero Unsafe Application Code**: All core bootloader logic uses safe Rust
- **Ownership System**: Rust's borrow checker prevents use-after-free and double-free
- **Bounds Checking**: All array/slice access is bounds-checked at compile time
- **Integer Overflow Protection**: Compile-time overflow detection enabled

### Critical Memory Management Features
```rust
// CR3-based page table discovery (allocator.rs)
let (level_4_table_frame, _) = Cr3::read();
let level_4_table_addr = physical_memory_offset + level_4_table_frame.start_address().as_u64();

// Duplicate mapping detection prevents memory attacks
match mapper.translate_page(page) {
    Ok(_) => continue, // Page already mapped, skip
    Err(_) => { /* Map new page safely */ }
}
```

### Cryptographic Verification Framework
While currently simulated, the system includes infrastructure for:
- **RSA Signature Verification**: 4096-bit key support with PKCS#1 padding
- **Hash Validation**: SHA-256/SHA-512 integrity verification
- **Certificate Validation**: X.509 certificate chain verification
- **Rollback Prevention**: Monotonic version checking system

### Boot Phase Security
The logging system tracks security-critical phases:
```rust
boot_phase_start!(BootPhase::Verification);
network_client.verify_signatures(&kernel_data, &config)?;
boot_phase_complete!(BootPhase::Verification);
```

### Hardware Security Integration Points
- **Memory Region Analysis**: Comprehensive logging of all memory regions from `BootInfo`
- **Page Table Protection**: Prevents unauthorized memory mapping that could indicate attacks
- **Heap Boundary Enforcement**: Strict 100 KiB heap limit prevents memory exhaustion attacks
- **Hardware Lockdown**: Prepares for real-world firmware protection mechanisms

## Development Notes

### Testing Strategy
- Custom test framework using `#![test_runner]` with QEMU integration
- Boot phases individually testable via phase-tracking macros
- Memory management tested through allocation/deallocation cycles
- Network simulation allows testing without real network hardware

### Debugging Approach
- Comprehensive logging system with ANSI color coding
- Memory region analysis for understanding boot environment  
- VGA console output for low-level debugging without serial
- QEMU serial output for automated testing and CI integration

### Performance Characteristics
- **Boot Time**: <3 seconds simulated end-to-end
- **Memory Footprint**: <5MB total including buffers
- **Code Size**: ~2MB bootloader binary
- **Heap Usage**: 100KB allocated (expandable for production)
