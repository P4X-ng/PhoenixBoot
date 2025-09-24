/*
 * Enhanced logging module for Nuclear Boot with detailed tracing
 */

use core::fmt::Write;

// ANSI color codes for enhanced output
pub const RESET: &str = "\x1b[0m";
pub const BOLD: &str = "\x1b[1m";
pub const RED: &str = "\x1b[31m";
pub const GREEN: &str = "\x1b[32m";
pub const YELLOW: &str = "\x1b[33m";
pub const BLUE: &str = "\x1b[34m";
pub const MAGENTA: &str = "\x1b[35m";
pub const CYAN: &str = "\x1b[36m";
pub const WHITE: &str = "\x1b[37m";

// Log levels
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LogLevel {
    Trace,
    Debug,
    Info,
    Warn,
    Error,
    Critical,
}

impl LogLevel {
    pub fn color(&self) -> &'static str {
        match self {
            LogLevel::Trace => CYAN,
            LogLevel::Debug => BLUE,
            LogLevel::Info => GREEN,
            LogLevel::Warn => YELLOW,
            LogLevel::Error => RED,
            LogLevel::Critical => MAGENTA,
        }
    }

    pub fn prefix(&self) -> &'static str {
        match self {
            LogLevel::Trace => "TRACE",
            LogLevel::Debug => "DEBUG", 
            LogLevel::Info => "INFO ",
            LogLevel::Warn => "WARN ",
            LogLevel::Error => "ERROR",
            LogLevel::Critical => "CRIT ",
        }
    }
}

// Enhanced logging macros
#[macro_export]
macro_rules! log_trace {
    ($($arg:tt)*) => {
        $crate::logger::log_with_level($crate::logger::LogLevel::Trace, format_args!($($arg)*));
    };
}

#[macro_export]
macro_rules! log_debug {
    ($($arg:tt)*) => {
        $crate::logger::log_with_level($crate::logger::LogLevel::Debug, format_args!($($arg)*));
    };
}

#[macro_export]
macro_rules! log_info {
    ($($arg:tt)*) => {
        $crate::logger::log_with_level($crate::logger::LogLevel::Info, format_args!($($arg)*));
    };
}

#[macro_export]
macro_rules! log_warn {
    ($($arg:tt)*) => {
        $crate::logger::log_with_level($crate::logger::LogLevel::Warn, format_args!($($arg)*));
    };
}

#[macro_export]
macro_rules! log_error {
    ($($arg:tt)*) => {
        $crate::logger::log_with_level($crate::logger::LogLevel::Error, format_args!($($arg)*));
    };
}

#[macro_export]
macro_rules! log_critical {
    ($($arg:tt)*) => {
        $crate::logger::log_with_level($crate::logger::LogLevel::Critical, format_args!($($arg)*));
    };
}

pub fn log_with_level(level: LogLevel, args: core::fmt::Arguments) {
    use crate::console::WRITER;
    
    let mut writer = WRITER.lock();
    write!(writer, "{}{}[{}]{} ", 
           BOLD, level.color(), level.prefix(), RESET).unwrap();
    writer.write_fmt(args).unwrap();
    writeln!(writer).unwrap();
}

// Boot phase tracking
#[derive(Debug, Clone, Copy)]
pub enum BootPhase {
    Reset,
    HeapInit,
    ConsoleInit,
    HardwareInit,
    NetworkInit,
    ImageDownload,
    Verification,
    // Nuclear Wipe Phases
    LockoutPrevention,
    UefiAnalysis,
    NuclearWipe,
    SystemRecovery,
    OsJump,
    Complete,
}

impl BootPhase {
    pub fn description(&self) -> &'static str {
        match self {
            BootPhase::Reset => "System Reset",
            BootPhase::HeapInit => "Heap Allocation",
            BootPhase::ConsoleInit => "Console Initialization",
            BootPhase::HardwareInit => "Hardware Initialization",
            BootPhase::NetworkInit => "Network Stack",
            BootPhase::ImageDownload => "OS Image Download",
            BootPhase::Verification => "Cryptographic Verification",
            BootPhase::LockoutPrevention => "Lockout Prevention Setup",
            BootPhase::UefiAnalysis => "UEFI Analysis & Bootkit Detection",
            BootPhase::NuclearWipe => "Nuclear Memory Wipe",
            BootPhase::SystemRecovery => "System Recovery & Restoration",
            BootPhase::OsJump => "OS Entry Point Jump",
            BootPhase::Complete => "Boot Complete",
        }
    }

    pub fn emoji(&self) -> &'static str {
        match self {
            BootPhase::Reset => "🔄",
            BootPhase::HeapInit => "🧠",
            BootPhase::ConsoleInit => "📺",
            BootPhase::HardwareInit => "⚙️",
            BootPhase::NetworkInit => "🌐",
            BootPhase::ImageDownload => "📥",
            BootPhase::Verification => "🔐",
            BootPhase::LockoutPrevention => "🛡️",
            BootPhase::UefiAnalysis => "🔍",
            BootPhase::NuclearWipe => "💀",
            BootPhase::SystemRecovery => "🆘",
            BootPhase::OsJump => "🚀",
            BootPhase::Complete => "✅",
        }
    }
}

#[macro_export]
macro_rules! boot_phase_start {
    ($phase:expr) => {
        $crate::log_info!("{} {} Starting: {}", 
                         $crate::logger::BOLD, 
                         $phase.emoji(), 
                         $phase.description());
    };
}

#[macro_export]
macro_rules! boot_phase_complete {
    ($phase:expr) => {
        $crate::log_info!("{}{} {} Complete: {}{}", 
                         $crate::logger::GREEN,
                         $crate::logger::BOLD,
                         $phase.emoji(), 
                         $phase.description(),
                         $crate::logger::RESET);
    };
}

#[macro_export]
macro_rules! boot_phase_failed {
    ($phase:expr, $error:expr) => {
        $crate::log_error!("{}{} ❌ Failed: {} - {}{}", 
                          $crate::logger::RED,
                          $crate::logger::BOLD,
                          $phase.description(),
                          $error,
                          $crate::logger::RESET);
    };
}

// Memory region logging
pub fn log_memory_regions(memory_regions: &[bootloader_api::info::MemoryRegion]) {
    log_info!("Memory Map ({} regions):", memory_regions.len());
    for (i, region) in memory_regions.iter().enumerate() {
        let kind_str = match region.kind {
            bootloader_api::info::MemoryRegionKind::Usable => "USABLE",
            bootloader_api::info::MemoryRegionKind::Bootloader => "BOOTLOADER",
            bootloader_api::info::MemoryRegionKind::UnknownUefi(_) => "UNKNOWN_UEFI",
            bootloader_api::info::MemoryRegionKind::UnknownBios(_) => "UNKNOWN_BIOS",
            _ => "OTHER",
        };
        
        let size_kb = (region.end - region.start) / 1024;
        log_debug!("  Region {}: 0x{:016x}-0x{:016x} ({} KB) [{}]",
                  i, region.start, region.end, size_kb, kind_str);
    }
}
