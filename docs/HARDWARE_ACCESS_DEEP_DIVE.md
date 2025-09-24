# 🔧 PhoenixGuard Hardware Access Deep Dive

## Overview

PhoenixGuard's bootkit protection bypass capabilities rely on **direct hardware register manipulation** at the chipset level. This document explains the precise mechanisms, register layouts, and access patterns used to circumvent bootkit-installed hardware locks.

## 🏗️ x86 Platform Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                          CPU COMPLEX                           │
│  ┌─────────────────┬─────────────────┬─────────────────────────┐ │
│  │   CPU CORE 0    │   CPU CORE 1    │       SHARED L3         │ │
│  │  ┌───────────┐  │  ┌───────────┐  │  ┌─────────────────────┐ │ │
│  │  │MSR SPACE  │  │  │MSR SPACE  │  │  │   MICROCODE RAM     │ │ │
│  │  │0x0-0x1FFF │  │  │0x0-0x1FFF │  │  │                     │ │ │
│  │  └───────────┘  │  └───────────┘  │  └─────────────────────┘ │ │
│  └─────────────────┴─────────────────┴─────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
                                │
                    ┌───────────▼───────────┐
                    │     MEMORY HUB        │
                    │  ┌─────────────────┐  │
                    │  │  DRAM CHANNELS  │  │
                    │  │     DDR4/DDR5   │  │
                    │  └─────────────────┘  │
                    └───────────┬───────────┘
                                │
    ┌───────────────────────────▼───────────────────────────┐
    │              PLATFORM CONTROLLER HUB (PCH)           │
    │  ┌─────────────────┬─────────────────┬───────────────┐ │
    │  │  SPI CONTROLLER │  LPC CONTROLLER │ OTHER DEVICES │ │
    │  │                 │                 │  (SATA, USB)  │ │
    │  │ ┌─────────────┐ │ ┌─────────────┐ │               │ │
    │  │ │MMIO REGISTERS│ │ │I/O REGISTERS│ │               │ │
    │  │ │0xFED1xxxx   │ │ │0x80-0xFF    │ │               │ │
    │  │ └─────────────┘ │ └─────────────┘ │               │ │
    │  └─────────────────┴─────────────────┴───────────────┘ │
    └─────────────────────────┬─────────────────────────────┘
                              │
              ┌───────────────▼───────────────┐
              │         SPI FLASH CHIP        │
              │  ┌───────────┬───────────────┐ │
              │  │DESCRIPTOR │     BIOS      │ │
              │  │           │   REGION      │ │
              │  │   0-4KB   │   4MB-16MB    │ │
              │  └───────────┴───────────────┘ │
              └───────────────────────────────┘
```

## 🎯 Key Hardware Components PhoenixGuard Manipulates

### 1. **CPU Model Specific Registers (MSRs)**

MSRs are CPU-internal registers that control low-level processor behavior:

```c
// Key MSR addresses PhoenixGuard monitors/manipulates
#define MSR_IA32_BIOS_UPDT_TRIG    0x79   // Microcode update trigger
#define MSR_IA32_BIOS_SIGN_ID      0x8B   // Current microcode signature  
#define MSR_IA32_PLATFORM_ID       0x17   // Platform ID for microcode matching
#define MSR_IA32_FEATURE_CONTROL   0x3A   // VMX, SMX, Lock control
#define MSR_IA32_SMRR_PHYSBASE     0x1F2  // SMM memory range base
#define MSR_IA32_SMRR_PHYSMASK     0x1F3  // SMM memory range mask

// MSR access requires ring 0 (kernel) privileges
static inline uint64_t read_msr(uint32_t msr) {
    uint32_t low, high;
    __asm__ volatile ("rdmsr" : "=a"(low), "=d"(high) : "c"(msr));
    return ((uint64_t)high << 32) | low;
}

static inline void write_msr(uint32_t msr, uint64_t value) {
    uint32_t low = value & 0xFFFFFFFF;
    uint32_t high = value >> 32;
    __asm__ volatile ("wrmsr" : : "c"(msr), "a"(low), "d"(high));
}
```

### 2. **PCH SPI Controller Registers**

The Platform Controller Hub (PCH) contains the SPI flash controller that bootkits target:

```c
// SPI Controller MMIO Base (varies by chipset)
#define PCH_SPI_BASE_ADDRESS       0xFED1F000  // Intel typical
#define PCH_RCRB_BASE              0xFED1C000  // Root Complex Register Block

// Critical SPI registers (relative to SPI_BASE)
#define HSFS                       0x04    // Hardware Sequencing Flash Status
#define HSFC                       0x06    // Hardware Sequencing Flash Control
#define FADDR                      0x08    // Flash Address Register
#define FDATA0                     0x10    // Flash Data Register 0
#define FREG0                      0x20    // Flash Region 0 (Descriptor)
#define FREG1                      0x24    // Flash Region 1 (BIOS)
#define PR0                        0x20    // Protected Range 0
#define PR1                        0x24    // Protected Range 1
#define PR2                        0x28    // Protected Range 2
#define PR3                        0x2C    // Protected Range 3
#define PR4                        0x30    // Protected Range 4

// BIOS Control Register (in PCH LPC space)
#define BIOS_CNTL                  0xDC0   // Relative to LPC base
```

### 3. **Critical Register Bitfields**

Understanding the individual bits is crucial for bypass operations:

```c
// HSFS (Hardware Sequencing Flash Status) Register Bitfield
typedef union {
    struct {
        UINT32  FDONE   : 1;  // [0]    Flash Cycle Done
        UINT32  FCERR   : 1;  // [1]    Flash Cycle Error  
        UINT32  AEL     : 1;  // [2]    Access Error Log
        UINT32  BERASE  : 2;  // [4:3]  Block/Sector Erase Size
        UINT32  SCIP    : 1;  // [5]    SPI Cycle In Progress
        UINT32  FDOPSS  : 1;  // [6]    Flash Descriptor Override Pin Strap Status
        UINT32  FDV     : 1;  // [7]    Flash Descriptor Valid
        UINT32  FLOCKDN : 1;  // [15]   Flash Configuration Lock-Down *** KEY BIT ***
    } Bits;
    UINT32 Uint32;
} HSFS_REGISTER;

// BIOS_CNTL (BIOS Control) Register Bitfield  
typedef union {
    struct {
        UINT32  BIOSWE  : 1;  // [0]    BIOS Write Enable *** KEY BIT ***
        UINT32  BLE     : 1;  // [1]    BIOS Lock Enable
        UINT32  SRC     : 2;  // [3:2]  SPI Read Configuration
        UINT32  TSS     : 1;  // [4]    Top Swap Status
        UINT32  SMM_BWP : 1;  // [5]    SMM BIOS Write Protection
        UINT32  BBS     : 1;  // [6]    Boot BIOS Straps
        UINT32  BILD    : 1;  // [7]    BIOS Interface Lock Down
    } Bits;
    UINT32 Uint32;
} BIOS_CNTL_REGISTER;

// Protected Range Register Bitfield
typedef union {
    struct {
        UINT32  RBA     : 13; // [12:0]  Range Base Address (4KB aligned)
        UINT32  Reserved: 3;  // [15:13] Reserved
        UINT32  RLA     : 13; // [28:16] Range Limit Address (4KB aligned)  
        UINT32  Reserved2:2;  // [30:29] Reserved
        UINT32  WPE     : 1;  // [31]    Write Protection Enable *** KEY BIT ***
    } Bits;
    UINT32 Uint32;
} PROTECTED_RANGE_REGISTER;
```

## 🔓 How PhoenixGuard Bypasses Bootkit Locks

### Method 1: Direct MMIO Register Manipulation

```python
#!/usr/bin/env python3
"""
PhoenixGuard Hardware Register Bypass
Direct memory-mapped I/O access to PCH registers
"""
import mmap
import os
import struct
import ctypes

class HardwareBypass:
    def __init__(self):
        # Open /dev/mem for direct hardware access (requires root)
        self.mem_fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
        
        # Intel PCH register base addresses (chipset-dependent)
        self.PCH_SPI_BASE = 0xFED1F000
        self.PCH_LPC_BASE = 0xFED1C000
        
        # Map SPI controller registers
        self.spi_mmio = mmap.mmap(
            self.mem_fd, 
            0x1000,  # 4KB mapping
            offset=self.PCH_SPI_BASE,
            access=mmap.ACCESS_WRITE
        )
        
        # Map LPC controller registers  
        self.lpc_mmio = mmap.mmap(
            self.mem_fd,
            0x1000,  # 4KB mapping  
            offset=self.PCH_LPC_BASE,
            access=mmap.ACCESS_WRITE
        )
    
    def read_spi_register(self, offset):
        """Read 32-bit value from SPI controller register"""
        return struct.unpack_from("<I", self.spi_mmio, offset)[0]
    
    def write_spi_register(self, offset, value):
        """Write 32-bit value to SPI controller register"""
        struct.pack_into("<I", self.spi_mmio, offset, value)
    
    def bypass_flash_locks(self):
        """
        PhoenixGuard's core bypass sequence
        This is what makes bootkit-proof recovery possible
        """
        print("🔧 PhoenixGuard Hardware Lock Bypass")
        print("=" * 50)
        
        # Step 1: Check current lock status
        hsfs = self.read_spi_register(0x04)  # HSFS register
        bios_cntl = struct.unpack_from("<I", self.lpc_mmio, 0xDC0)[0]
        
        print(f"Current HSFS: 0x{hsfs:08x}")
        print(f"Current BIOS_CNTL: 0x{bios_cntl:08x}")
        
        # Check if FLOCKDN (Flash Lock Down) is set
        if hsfs & (1 << 15):  # FLOCKDN = bit 15
            print("⚠️  FLOCKDN is SET - bootkit has locked configuration")
            print("🔧 Attempting bypass...")
            
            # BYPASS METHOD 1: Clear FLOCKDN bit directly
            # This works if the bootkit hasn't set additional protections
            new_hsfs = hsfs & ~(1 << 15)  # Clear bit 15
            self.write_spi_register(0x04, new_hsfs)
            
            # Verify the bypass worked
            verify_hsfs = self.read_spi_register(0x04)
            if verify_hsfs & (1 << 15):
                print("❌ Direct FLOCKDN bypass failed - trying alternative method")
                return self._advanced_bypass()
            else:
                print("✅ FLOCKDN bypass successful!")
        
        # Step 2: Enable BIOS Write Enable (BIOSWE)
        if not (bios_cntl & 1):  # BIOSWE = bit 0
            print("🔧 Enabling BIOS Write Enable...")
            new_bios_cntl = bios_cntl | 1  # Set bit 0
            struct.pack_into("<I", self.lpc_mmio, 0xDC0, new_bios_cntl)
            
            verify_bios_cntl = struct.unpack_from("<I", self.lpc_mmio, 0xDC0)[0]
            if verify_bios_cntl & 1:
                print("✅ BIOSWE enabled successfully!")
            else:
                print("❌ BIOSWE enable failed")
                return False
        
        # Step 3: Clear Protected Ranges (PR0-PR4)
        print("🔧 Clearing SPI Protected Ranges...")
        for i in range(5):  # PR0 through PR4
            pr_offset = 0x20 + (i * 4)  # Each PR register is 4 bytes
            current_pr = self.read_spi_register(pr_offset)
            
            if current_pr & (1 << 31):  # WPE = bit 31 (Write Protection Enable)
                print(f"   Clearing PR{i} (was 0x{current_pr:08x})")
                self.write_spi_register(pr_offset, 0)  # Clear entire register
            
        print("✅ Hardware bypass complete!")
        return True
    
    def _advanced_bypass(self):
        """
        Advanced bypass for sophisticated bootkits
        Uses multiple techniques when direct register writes fail
        """
        print("🚨 Attempting advanced bypass techniques...")
        
        # Method 1: Reset SPI controller
        print("   Trying SPI controller reset...")
        # Implementation would reset the entire SPI controller
        
        # Method 2: Use SMM (System Management Mode) if available
        print("   Checking SMM bypass options...")
        # Implementation would use SMI generation to bypass locks
        
        # Method 3: Chipset-specific exploits
        print("   Applying chipset-specific bypasses...")
        # Implementation would use known chipset vulnerabilities
        
        # For now, return failure - these require more complex implementation
        print("❌ Advanced bypass methods require additional implementation")
        return False
    
    def close(self):
        """Clean up memory mappings"""
        self.spi_mmio.close()
        self.lpc_mmio.close()
        os.close(self.mem_fd)

# Usage example
if __name__ == "__main__":
    if os.geteuid() != 0:
        print("❌ Root privileges required for hardware access")
        exit(1)
    
    bypass = HardwareBypass()
    try:
        success = bypass.bypass_flash_locks()
        if success:
            print("🎉 System is ready for firmware recovery!")
        else:
            print("❌ Hardware bypass failed - external programmer may be needed")
    finally:
        bypass.close()
```

### Method 2: Using Chipsec for Advanced Bypass

```python
#!/usr/bin/env python3
"""
PhoenixGuard Chipsec Integration
Uses chipsec library for sophisticated hardware manipulation
"""
import sys
import os

# Add chipsec to path if installed
try:
    from chipsec.hal.spi import SPI
    from chipsec.hal.mmio import MMIO  
    from chipsec.chipset import Chipset
    from chipsec_main import logger
except ImportError:
    print("❌ Chipsec not available - install with: pip install chipsec")
    sys.exit(1)

class ChipsecBypass:
    def __init__(self):
        # Initialize chipsec chipset interface
        self.cs = Chipset()
        self.cs.init(None, True)  # True = load platform specific modules
        
        # Initialize SPI and MMIO interfaces
        self.spi = SPI(self.cs)
        self.mmio = MMIO(self.cs)
    
    def analyze_protection_mechanisms(self):
        """
        Deep analysis of current bootkit protection mechanisms
        """
        print("🔍 PhoenixGuard Protection Analysis")
        print("=" * 40)
        
        results = {
            'spi_flash_locked': False,
            'bios_write_locked': False, 
            'protected_ranges_active': [],
            'flash_descriptor_locked': False,
            'bypass_methods': []
        }
        
        # Check SPI Flash Configuration Lock-Down
        try:
            hsfs = self.spi.read_HSFS()
            if hsfs & 0x8000:  # FLOCKDN bit
                print("🚨 SPI Flash Configuration LOCKED (FLOCKDN)")
                results['spi_flash_locked'] = True
                results['bypass_methods'].append('direct_register_clear')
            else:
                print("✅ SPI Flash Configuration unlocked")
        except Exception as e:
            print(f"⚠️  Could not read HSFS: {e}")
        
        # Check BIOS Write Enable
        try:
            bios_cntl = self.cs.read_register('BIOS_CNTL')
            if not (bios_cntl & 1):  # BIOSWE bit
                print("🚨 BIOS Write DISABLED (BIOSWE=0)")
                results['bios_write_locked'] = True
                results['bypass_methods'].append('enable_bioswe')
            else:
                print("✅ BIOS Write enabled")
        except Exception as e:
            print(f"⚠️  Could not read BIOS_CNTL: {e}")
        
        # Check Protected Ranges
        for i in range(5):  # PR0-PR4
            try:
                pr_value = self.spi.read_PR(i)
                if pr_value & 0x80000000:  # WPE bit
                    base = (pr_value & 0x1FFF) * 4096  # 4KB alignment
                    limit = ((pr_value >> 16) & 0x1FFF) * 4096
                    print(f"🚨 Protected Range {i}: 0x{base:x}-0x{limit:x}")
                    results['protected_ranges_active'].append({
                        'range': i,
                        'base': base,
                        'limit': limit
                    })
                    results['bypass_methods'].append(f'clear_pr{i}')
            except Exception as e:
                print(f"⚠️  Could not read PR{i}: {e}")
        
        return results
    
    def execute_bypass(self, protection_analysis):
        """
        Execute bypass methods based on detected protections
        """
        print("\n🔧 Executing PhoenixGuard Bypass Sequence")
        print("=" * 50)
        
        success_count = 0
        total_methods = len(protection_analysis['bypass_methods'])
        
        for method in protection_analysis['bypass_methods']:
            print(f"Executing: {method}")
            
            if method == 'direct_register_clear':
                if self._bypass_flockdn():
                    success_count += 1
                    print("✅ FLOCKDN bypass successful")
                else:
                    print("❌ FLOCKDN bypass failed")
            
            elif method == 'enable_bioswe':
                if self._enable_bioswe():
                    success_count += 1
                    print("✅ BIOSWE enable successful") 
                else:
                    print("❌ BIOSWE enable failed")
                    
            elif method.startswith('clear_pr'):
                pr_num = int(method[-1])
                if self._clear_protected_range(pr_num):
                    success_count += 1
                    print(f"✅ PR{pr_num} clear successful")
                else:
                    print(f"❌ PR{pr_num} clear failed")
        
        print(f"\n🎯 Bypass Results: {success_count}/{total_methods} successful")
        return success_count == total_methods
    
    def _bypass_flockdn(self):
        """Clear Flash Configuration Lock-Down bit"""
        try:
            current_hsfs = self.spi.read_HSFS()
            new_hsfs = current_hsfs & ~0x8000  # Clear FLOCKDN bit
            self.spi.write_HSFS(new_hsfs)
            
            # Verify the change took effect
            verify_hsfs = self.spi.read_HSFS()
            return not (verify_hsfs & 0x8000)
        except Exception:
            return False
    
    def _enable_bioswe(self):
        """Enable BIOS Write Enable bit"""
        try:
            current_bios_cntl = self.cs.read_register('BIOS_CNTL')
            new_bios_cntl = current_bios_cntl | 1  # Set BIOSWE bit
            self.cs.write_register('BIOS_CNTL', new_bios_cntl)
            
            # Verify the change took effect
            verify_bios_cntl = self.cs.read_register('BIOS_CNTL')
            return bool(verify_bios_cntl & 1)
        except Exception:
            return False
    
    def _clear_protected_range(self, pr_num):
        """Clear a specific Protected Range register"""
        try:
            self.spi.write_PR(pr_num, 0)  # Clear entire PR register
            
            # Verify the change took effect  
            verify_pr = self.spi.read_PR(pr_num)
            return verify_pr == 0
        except Exception:
            return False

# Usage example
if __name__ == "__main__":
    if os.geteuid() != 0:
        print("❌ Root privileges required for hardware access")
        sys.exit(1)
    
    bypass = ChipsecBypass()
    
    # Step 1: Analyze current protection state
    analysis = bypass.analyze_protection_mechanisms()
    
    # Step 2: Execute bypass if protections detected
    if analysis['bypass_methods']:
        success = bypass.execute_bypass(analysis)
        if success:
            print("\n🎉 All bootkit protections bypassed successfully!")
            print("System is ready for PhoenixGuard firmware recovery.")
        else:
            print("\n⚠️  Some bypass methods failed.")
            print("External hardware programmer may be required.")
    else:
        print("\n✅ No bootkit protections detected - system is clean!")
```

## 🧠 Understanding What Makes This Work

### Why Direct Hardware Access Bypasses Bootkits

1. **Operating Below the Software Layer**: Bootkits operate in firmware/software, but PhoenixGuard manipulates the actual silicon registers that control flash access.

2. **Ring 0 Privilege**: By running in kernel mode (ring 0), PhoenixGuard has the same privilege level as the bootkit, allowing direct register access.

3. **MMIO Cannot Be Virtualized**: Memory-mapped I/O operations directly touch hardware - bootkits cannot intercept these without extremely sophisticated techniques.

4. **Multiple Attack Vectors**: Even if one bypass method fails, PhoenixGuard has several alternatives (direct MMIO, chipsec, external programmers).

### Register Access Timing

The key insight is that **hardware registers must be accessible to legitimate firmware updates**, so there's always a window where they can be manipulated:

```c
// Typical bootkit protection sequence:
// 1. Bootkit loads during boot
// 2. Bootkit sets FLOCKDN=1, clears BIOSWE=0, sets Protected Ranges
// 3. System appears "locked" to normal software

// PhoenixGuard bypass sequence:
// 1. Map hardware registers via /dev/mem  
// 2. Direct MMIO write to clear locks
// 3. Restore normal flash access
// 4. Proceed with firmware recovery
```

This approach is **bootkit-proof** because it operates at the same hardware level where the locks are implemented, but with clean code that's not subject to the bootkit's control.

