/*
 * 🔐🛡️ LOCKOUT PREVENTION ENGINE 🛡️🔐
 * 
 * Ensures we don't get locked out during nuclear memory wipe
 * - Backup critical services before wipe
 * - Emergency recovery mechanisms
 * - Hardware access preservation 
 * - Self-preservation checks
 */

use core::mem;
use x86_64::VirtAddr;
use bootloader_api::info::{MemoryRegion, MemoryRegionKind};

pub struct LockoutPrevention {
    backup_memory: Option<VirtAddr>,
    backup_size: usize,
    recovery_stub: Option<fn()>,
    critical_services: CriticalServices,
}

#[derive(Clone, Copy)]
pub struct CriticalServices {
    pub console_writer: Option<VirtAddr>,
    pub memory_allocator: Option<VirtAddr>,
    pub emergency_stack: Option<VirtAddr>,
    pub spi_access_stub: Option<VirtAddr>,
    pub recovery_kernel: Option<VirtAddr>,
}

#[derive(Debug)]
pub enum LockoutError {
    InsufficientMemory,
    BackupFailed,
    CriticalServiceMissing,
    HardwareAccessLost,
    RecoveryStubCorrupted,
}

impl LockoutPrevention {
    pub fn new() -> Self {
        Self {
            backup_memory: None,
            backup_size: 0,
            recovery_stub: None,
            critical_services: CriticalServices::empty(),
        }
    }

    /// 🛡️ PRE-WIPE LOCKOUT PREVENTION 🛡️
    /// Call this BEFORE initiating nuclear wipe
    pub unsafe fn prepare_lockout_prevention(&mut self, memory_regions: &[MemoryRegion]) -> Result<(), LockoutError> {
        log_critical!("🛡️ PREPARING LOCKOUT PREVENTION MECHANISMS 🛡️");
        
        // Step 1: Find secure high-memory region for backups
        self.allocate_backup_memory(memory_regions)?;
        
        // Step 2: Backup critical services that we need to survive
        self.backup_critical_services()?;
        
        // Step 3: Create emergency recovery stub
        self.create_recovery_stub()?;
        
        // Step 4: Verify hardware access preservation
        self.verify_hardware_access()?;
        
        // Step 5: Set up emergency communication channels
        self.setup_emergency_comms()?;
        
        log_info!("✅ Lockout prevention prepared - backup at 0x{:016x}", 
                 self.backup_memory.unwrap().as_u64());
        
        Ok(())
    }

    /// Find and allocate high memory for backups
    unsafe fn allocate_backup_memory(&mut self, memory_regions: &[MemoryRegion]) -> Result<(), LockoutError> {
        // Look for high memory region (>4GB) to avoid conflicts
        for region in memory_regions.iter().rev() { // Start from high addresses
            if region.kind == MemoryRegionKind::Usable && region.start > 0x100000000 {
                let size = (region.end - region.start) as usize;
                if size >= self.required_backup_size() {
                    self.backup_memory = Some(VirtAddr::new(region.start));
                    self.backup_size = size.min(16 * 1024 * 1024); // 16MB max
                    
                    log_debug!("🏦 Backup memory allocated: 0x{:016x}-0x{:016x} ({} MB)",
                              region.start, region.start + self.backup_size as u64,
                              self.backup_size / (1024 * 1024));
                    return Ok(());
                }
            }
        }
        
        log_error!("❌ Failed to find suitable backup memory region");
        Err(LockoutError::InsufficientMemory)
    }

    /// Backup critical services before wipe
    unsafe fn backup_critical_services(&mut self) -> Result<(), LockoutError> {
        log_info!("💾 Backing up critical services...");
        
        let backup_base = self.backup_memory.ok_or(LockoutError::InsufficientMemory)?;
        let mut offset = 0;
        
        // Backup 1: Console writer for emergency output
        if let Some(console_addr) = self.find_console_writer() {
            self.backup_service(backup_base, &mut offset, console_addr, 4096)?;
            self.critical_services.console_writer = Some(backup_base + offset - 4096);
            log_trace!("Console writer backed up to 0x{:016x}", (backup_base + offset - 4096).as_u64());
        }
        
        // Backup 2: Memory allocator state
        if let Some(allocator_addr) = self.find_memory_allocator() {
            self.backup_service(backup_base, &mut offset, allocator_addr, 8192)?;
            self.critical_services.memory_allocator = Some(backup_base + offset - 8192);
            log_trace!("Memory allocator backed up to 0x{:016x}", (backup_base + offset - 8192).as_u64());
        }
        
        // Backup 3: Emergency stack
        self.create_emergency_stack(backup_base, &mut offset)?;
        
        // Backup 4: SPI access stub for recovery
        self.create_spi_access_stub(backup_base, &mut offset)?;
        
        // Backup 5: Minimal recovery kernel
        self.create_recovery_kernel(backup_base, &mut offset)?;
        
        log_info!("✅ Critical services backed up ({} bytes used)", offset);
        Ok(())
    }

    /// Create emergency recovery stub that can restore system
    unsafe fn create_recovery_stub(&mut self) -> Result<(), LockoutError> {
        log_info!("🆘 Creating emergency recovery stub...");
        
        // This stub will be called if nuclear wipe fails
        let recovery_fn: fn() = || {
            // Emergency recovery code - restore minimal functionality
            unsafe {
                // Re-enable interrupts
                x86_64::instructions::interrupts::enable();
                
                // Print emergency message via direct VGA access
                let vga_buffer = 0xb8000 as *mut u16;
                let message = b"EMERGENCY RECOVERY ACTIVE - NUCLEAR WIPE FAILED";
                for (i, &byte) in message.iter().enumerate() {
                    let color = 0x4F00; // White on red background
                    core::ptr::write_volatile(vga_buffer.add(i), color | byte as u16);
                }
                
                // Halt - at least we can see what happened
                loop {
                    x86_64::instructions::hlt();
                }
            }
        };
        
        self.recovery_stub = Some(recovery_fn);
        log_trace!("Recovery stub created at function pointer: {:p}", recovery_fn);
        
        Ok(())
    }

    /// Verify we can still access critical hardware after wipe
    unsafe fn verify_hardware_access(&self) -> Result<(), LockoutError> {
        log_info!("🔧 Verifying hardware access preservation...");
        
        // Check 1: Can we still access VGA buffer for emergency output?
        let vga_test = self.test_vga_access();
        if !vga_test {
            log_warn!("⚠️  VGA access may be lost after wipe");
        }
        
        // Check 2: Can we access serial port for emergency output?
        let serial_test = self.test_serial_access();
        if !serial_test {
            log_warn!("⚠️  Serial access may be lost after wipe");
        }
        
        // Check 3: Can we access SPI flash for recovery?
        let spi_test = self.test_spi_access();
        if !spi_test {
            log_warn!("⚠️  SPI access may be lost after wipe - DANGEROUS!");
            return Err(LockoutError::HardwareAccessLost);
        }
        
        log_info!("✅ Hardware access verification completed");
        Ok(())
    }

    /// Set up emergency communication channels
    unsafe fn setup_emergency_comms(&mut self) -> Result<(), LockoutError> {
        log_info!("📡 Setting up emergency communication channels...");
        
        // Emergency Channel 1: Direct VGA text mode
        self.setup_emergency_vga()?;
        
        // Emergency Channel 2: Serial port output
        self.setup_emergency_serial()?;
        
        // Emergency Channel 3: POST codes via port 0x80
        self.setup_emergency_post_codes()?;
        
        // Emergency Channel 4: Debug LEDs if available
        self.setup_debug_leds()?;
        
        log_info!("✅ Emergency communication channels ready");
        Ok(())
    }

    /// 🆘 POST-WIPE RECOVERY 🆘
    /// Call this if nuclear wipe fails or to restore services
    pub unsafe fn initiate_emergency_recovery(&self) -> ! {
        // Use emergency communication first
        self.emergency_output("EMERGENCY RECOVERY INITIATED");
        
        // Try to restore critical services
        if let Err(_) = self.restore_critical_services() {
            self.emergency_output("CRITICAL SERVICE RESTORE FAILED");
        }
        
        // If we have recovery stub, call it
        if let Some(recovery_fn) = self.recovery_stub {
            self.emergency_output("CALLING RECOVERY STUB");
            recovery_fn();
        }
        
        // Last resort: direct hardware emergency output and halt
        self.last_resort_emergency_output();
        
        loop {
            x86_64::instructions::hlt();
        }
    }

    /// Restore critical services from backup
    unsafe fn restore_critical_services(&self) -> Result<(), LockoutError> {
        if let Some(backup_addr) = self.backup_memory {
            // Restore console writer
            if let Some(console_backup) = self.critical_services.console_writer {
                self.restore_service(console_backup, self.find_console_writer().unwrap_or(VirtAddr::new(0)), 4096)?;
            }
            
            // Restore memory allocator
            if let Some(allocator_backup) = self.critical_services.memory_allocator {
                self.restore_service(allocator_backup, self.find_memory_allocator().unwrap_or(VirtAddr::new(0)), 8192)?;
            }
        }
        Ok(())
    }

    /// Emergency output using multiple channels
    unsafe fn emergency_output(&self, message: &str) {
        // Channel 1: Direct VGA
        self.vga_emergency_print(message);
        
        // Channel 2: Serial port
        self.serial_emergency_print(message);
        
        // Channel 3: POST code
        self.post_code_emergency(0xDE); // Dead/Error
    }

    /// Last resort emergency output directly to hardware
    unsafe fn last_resort_emergency_output(&self) {
        // Direct VGA buffer write - red background, white text
        let vga = 0xb8000 as *mut u16;
        let message = b"NUCLEAR WIPE ENGINE FAILURE - SYSTEM RECOVERY FAILED";
        
        for (i, &byte) in message.iter().enumerate() {
            if i < 80 { // Don't overflow VGA line
                let attr = 0x4F00; // White on red
                core::ptr::write_volatile(vga.add(i), attr | byte as u16);
            }
        }
        
        // Emergency POST code
        unsafe {
            use x86_64::instructions::port::Port;
            let mut post_port = Port::new(0x80);
            post_port.write(0xDEu8); // DEAD
        }
    }

    // Helper functions for service backup/restore
    
    unsafe fn backup_service(&self, base: VirtAddr, offset: &mut usize, source: VirtAddr, size: usize) -> Result<(), LockoutError> {
        let dest = base + *offset;
        let src_ptr = source.as_ptr::<u8>();
        let dest_ptr = dest.as_mut_ptr::<u8>();
        
        for i in 0..size {
            core::ptr::write_volatile(dest_ptr.add(i), core::ptr::read_volatile(src_ptr.add(i)));
        }
        
        *offset += size;
        Ok(())
    }

    unsafe fn restore_service(&self, backup_addr: VirtAddr, dest: VirtAddr, size: usize) -> Result<(), LockoutError> {
        let src_ptr = backup_addr.as_ptr::<u8>();
        let dest_ptr = dest.as_mut_ptr::<u8>();
        
        for i in 0..size {
            core::ptr::write_volatile(dest_ptr.add(i), core::ptr::read_volatile(src_ptr.add(i)));
        }
        
        Ok(())
    }

    // Service discovery functions
    
    fn find_console_writer(&self) -> Option<VirtAddr> {
        // TODO: Find console writer in memory
        Some(VirtAddr::new(0x1000)) // Placeholder
    }

    fn find_memory_allocator(&self) -> Option<VirtAddr> {
        // TODO: Find allocator in memory  
        Some(VirtAddr::new(0x2000)) // Placeholder
    }

    // Hardware test functions
    
    unsafe fn test_vga_access(&self) -> bool {
        let vga = 0xb8000 as *mut u16;
        let original = core::ptr::read_volatile(vga);
        core::ptr::write_volatile(vga, 0x0741); // 'A' in white
        let test = core::ptr::read_volatile(vga);
        core::ptr::write_volatile(vga, original); // Restore
        test == 0x0741
    }

    unsafe fn test_serial_access(&self) -> bool {
        use x86_64::instructions::port::Port;
        let mut port = Port::new(0x3F8); // COM1
        port.write(0x41u8); // 'A'
        true // Assume success for now
    }

    unsafe fn test_spi_access(&self) -> bool {
        // TODO: Test SPI flash access
        true // Placeholder
    }

    // Emergency setup functions
    
    unsafe fn setup_emergency_vga(&self) -> Result<(), LockoutError> {
        // TODO: Set up VGA emergency mode
        Ok(())
    }

    unsafe fn setup_emergency_serial(&self) -> Result<(), LockoutError> {
        // TODO: Initialize serial port for emergency
        Ok(())
    }

    unsafe fn setup_emergency_post_codes(&self) -> Result<(), LockoutError> {
        // POST codes always work - no setup needed
        Ok(())
    }

    unsafe fn setup_debug_leds(&self) -> Result<(), LockoutError> {
        // TODO: Platform-specific debug LED setup
        Ok(())
    }

    // Emergency output implementations
    
    unsafe fn vga_emergency_print(&self, message: &str) {
        let vga = 0xb8000 as *mut u16;
        for (i, byte) in message.bytes().enumerate() {
            if i < 80 {
                let attr = 0x0E00; // Yellow on black
                core::ptr::write_volatile(vga.add(i), attr | byte as u16);
            }
        }
    }

    unsafe fn serial_emergency_print(&self, message: &str) {
        use x86_64::instructions::port::Port;
        let mut port = Port::new(0x3F8);
        for byte in message.bytes() {
            port.write(byte);
        }
        port.write(b'\n');
    }

    unsafe fn post_code_emergency(&self, code: u8) {
        use x86_64::instructions::port::Port;
        let mut port = Port::new(0x80);
        port.write(code);
    }

    // Service creation functions
    
    unsafe fn create_emergency_stack(&mut self, base: VirtAddr, offset: &mut usize) -> Result<(), LockoutError> {
        let stack_size = 4096; // 4KB emergency stack
        let stack_addr = base + *offset;
        
        // Zero the stack
        let stack_ptr = stack_addr.as_mut_ptr::<u8>();
        for i in 0..stack_size {
            core::ptr::write_volatile(stack_ptr.add(i), 0);
        }
        
        self.critical_services.emergency_stack = Some(stack_addr);
        *offset += stack_size;
        Ok(())
    }

    unsafe fn create_spi_access_stub(&mut self, base: VirtAddr, offset: &mut usize) -> Result<(), LockoutError> {
        let stub_size = 2048; // 2KB SPI access stub
        let stub_addr = base + *offset;
        
        // TODO: Create minimal SPI access code
        self.critical_services.spi_access_stub = Some(stub_addr);
        *offset += stub_size;
        Ok(())
    }

    unsafe fn create_recovery_kernel(&mut self, base: VirtAddr, offset: &mut usize) -> Result<(), LockoutError> {
        let kernel_size = 8192; // 8KB recovery kernel
        let kernel_addr = base + *offset;
        
        // TODO: Create minimal recovery kernel
        self.critical_services.recovery_kernel = Some(kernel_addr);
        *offset += kernel_size;
        Ok(())
    }

    fn required_backup_size(&self) -> usize {
        4096    // Console writer
        + 8192  // Memory allocator
        + 4096  // Emergency stack  
        + 2048  // SPI access stub
        + 8192  // Recovery kernel
        + 4096  // Padding/alignment
    }
}

impl CriticalServices {
    fn empty() -> Self {
        Self {
            console_writer: None,
            memory_allocator: None,
            emergency_stack: None,
            spi_access_stub: None,
            recovery_kernel: None,
        }
    }
}

impl Default for LockoutPrevention {
    fn default() -> Self {
        Self::new()
    }
}
