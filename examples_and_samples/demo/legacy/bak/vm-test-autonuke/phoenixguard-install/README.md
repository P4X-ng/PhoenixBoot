# 🔥 PhoenixGuard - Self-Healing Firmware Recovery System

## Project Structure and Getting Started
- See docs/PROJECT_STRUCTURE.md for a guided overview of the repo layout, key scripts, and Makefile targets.
- Secure Boot users: see docs/SECURE_BOOT.md for sb-* targets, custom key enrollment, and QEMU notes.
- Common commands:
  - make check-deps
  - make build
  - make demo
  - make layout

## Quickstart: Clean GRUB Boot (alongside Xen Snapshot Jump)

You can chainload a known-clean GRUB from NuclearBoot as an alternative to the Xen jump. This is useful when you want a simple, non‑hypervisor path while still avoiding a potentially compromised on‑disk bootloader.

Install (on a running Linux with the ESP mounted at /boot/efi):
- Stage clean GRUB/shim and a minimal grub.cfg on the ESP, substituting your root UUID:
  sudo ./scripts/install_clean_grub_boot.sh \
    --esp /boot/efi \
    --root-uuid <ROOT_UUID> \
    [--shim /usr/lib/shim/shimx64.efi.signed] \
    [--grub-efi /usr/lib/grub/x86_64-efi/grubx64.efi] \
    [--vmlinuz /boot/vmlinuz-<ver>] [--initrd /boot/initrd.img-<ver>]

Use at boot:
- In NuclearBoot menu, press G for “Clean GRUB Boot”. It tries \\EFI\\PhoenixGuard\\shimx64.efi, then \\EFI\\PhoenixGuard\\grubx64.efi.

Validate after boot to detect partition switching:
- sudo EXPECT_UUID=<ROOT_UUID> resources/xen/dom0/validate-clean-os.sh

Notes:
- Secure Boot: prefer shimx64.efi.signed and ensure grubx64.efi is trusted (MOK/vendor key).
- The provided grub.cfg pins the root by UUID to avoid “hd” reordering tricks.

For the Xen-based remediation path and passthrough setup, see resources/xen/README.md.

**"Like the mythical phoenix, your system rises from the ashes of compromise"**

## Philosophy: Embrace the Breach

PhoenixGuard implements a revolutionary approach to firmware security:

> **"It's OK to get infected as long as the next boot is clean"**

Instead of trying to prevent every possible attack (which is impossible), PhoenixGuard assumes that compromise will happen and focuses on **automatic recovery and resilience**.

## Core Principles

### 1. **Assume Breach** 
Accept that sophisticated attackers will eventually compromise your firmware. Design for recovery, not prevention.

### 2. **Break the Persistence Chain**
Even if malware infects firmware, prevent it from establishing long-term persistence by ensuring clean boots.

### 3. **Automatic Recovery**
No manual intervention required - the system heals itself automatically when compromise is detected.

### 4. **Multiple Recovery Vectors**
Provide multiple independent recovery paths so attackers cannot block all of them.

### 5. **Clean OS Priority**
As long as the OS is clean, firmware compromise becomes irrelevant for most attack scenarios.

---

## Recovery Strategies

### 🌐 **1. Network Recovery**
```
┌─────────────────────────────────────────────────────────────┐
│                    NETWORK RECOVERY                        │
├─────────────────────────────────────────────────────────────┤
│  1. Download clean BIOS from trusted HTTPS server          │
│  2. Verify cryptographic signature and integrity           │
│  3. Flash clean firmware over compromised version          │
│  4. Reboot with restored firmware                          │
└─────────────────────────────────────────────────────────────┘

Benefits:
✅ Always up-to-date firmware
✅ Centrally managed recovery images
✅ Works even if local storage is compromised
✅ Can be automated in corporate environments

Use Cases:
- Corporate environments with recovery servers
- Cloud-managed security infrastructure
- Automatic security updates and recovery
```

### 💿 **2. Physical Media Recovery**
```
┌─────────────────────────────────────────────────────────────┐
│                  PHYSICAL MEDIA RECOVERY                   │
├─────────────────────────────────────────────────────────────┤
│  1. Detect write-protected CD/DVD/USB with clean firmware  │
│  2. Verify media is truly write-protected                  │
│  3. Load and verify clean firmware image                   │
│  4. Flash firmware from trusted media                      │
└─────────────────────────────────────────────────────────────┘

Benefits:
✅ Air-gapped security (no network required)
✅ Write-protection prevents media infection
✅ Physical control over recovery process
✅ Works even if network is compromised

Use Cases:
- High-security environments
- Air-gapped systems
- Emergency recovery scenarios
- Systems without network access
```

### 🔒 **3. Embedded Backup Recovery**
```
┌─────────────────────────────────────────────────────────────┐
│                  EMBEDDED BACKUP RECOVERY                  │
├─────────────────────────────────────────────────────────────┤
│  1. Use backup firmware stored in protected flash region   │
│  2. Verify backup integrity with cryptographic hash        │
│  3. Copy backup to main BIOS region                        │
│  4. Reboot with restored firmware                          │
└─────────────────────────────────────────────────────────────┘

Benefits:
✅ Always available (stored on-chip)
✅ Fastest recovery method
✅ No external dependencies
✅ Protected flash region prevents corruption

Use Cases:
- Systems with dual-BIOS support
- Enterprise motherboards with backup regions
- Critical infrastructure systems
- Embedded systems
```

---

## Clean OS Boot Recovery

### The Ultimate Persistence Breaker

PhoenixGuard's **Clean OS Boot Recovery** implements the philosophy that firmware compromise doesn't matter if you always boot a clean OS:

```
TRADITIONAL APPROACH:        PHOENIXGUARD APPROACH:
┌─────────────────────┐     ┌─────────────────────┐
│   Prevent Infection │     │   Embrace Infection │
│         ↓           │     │         ↓           │
│   ❌ Often Fails    │     │   🔄 Always Recover │
│         ↓           │     │         ↓           │
│   System Halts     │     │   Clean OS Boots    │
│   (Availability ↓)  │     │   (Availability ↑)  │
└─────────────────────┘     └─────────────────────┘
```

### Clean OS Sources

#### 🌐 **Network PXE Boot**
```yaml
Source: Network PXE Server
Priority: 100 (Highest)
Description: Boot clean Ubuntu from trusted network server
Configuration:
  Server: 192.168.1.100
  Kernel: /clean-images/vmlinuz-5.15.0-clean
  Initrd: /clean-images/initrd-clean.img
  Protocol: TFTP (port 69) or HTTPS (port 443)
```

#### 💿 **Read-Only Media Boot**
```yaml
Source: CD/DVD/Write-Protected USB
Priority: 90
Description: Boot from write-protected media
Configuration:
  Device: \EFI\BOOT\BOOTX64.EFI
  Image: \LIVE\CLEAN_UBUNTU_22.04.ISO
  Verification: SHA-256 hash + write-protection check
```

#### 🔐 **Cryptographically Signed Images**
```yaml
Source: Signed OS Image
Priority: 80
Description: Boot from digitally signed OS image
Configuration:
  Image: \CLEAN\SIGNED_UBUNTU.IMG
  Signature: RSA-2048 digital signature
  Verification: Public key cryptographic verification
```

---

## Integration with RFKilla

PhoenixGuard replaces the traditional "halt on compromise" approach in RFKilla:

### Before (Traditional):
```c
if (MicrocodeCompromised || ThermalTampering || BootkitDetected) {
    DEBUG((DEBUG_ERROR, "CRITICAL COMPROMISE DETECTED!"));
    CpuDeadLoop();  // 💀 System halts - availability lost
}
```

### After (PhoenixGuard):
```c
if (MicrocodeCompromised || ThermalTampering || BootkitDetected) {
    DEBUG((DEBUG_ERROR, "COMPROMISE DETECTED - INITIATING RECOVERY!"));
    
    // 🔥 Phoenix rises from the ashes
    Status = PhoenixGuardExecuteRecovery(CompromiseType, SecurityLevel);
    
    if (!EFI_ERROR(Status)) {
        // 🎉 System recovered and rebooting clean
        gRT->ResetSystem(EfiResetCold, EFI_SUCCESS, 0, NULL);
    } else {
        // 🛡️ Fall back to clean OS boot
        PhoenixGuardCleanOsBoot();
    }
}
```

### Benefits Over Traditional Approach

| Aspect | Traditional Halt | PhoenixGuard Recovery |
|--------|------------------|----------------------|
| **Availability** | ❌ System down until manual intervention | ✅ System automatically recovers |
| **Response Time** | ❌ Hours/days for manual recovery | ✅ Minutes for automatic recovery |
| **Expertise Required** | ❌ Skilled technician needed | ✅ Fully automated |
| **Attack Persistence** | ❌ Malware may survive manual recovery | ✅ Clean firmware/OS breaks persistence |
| **Business Impact** | ❌ Significant downtime costs | ✅ Minimal business disruption |
| **Scalability** | ❌ Doesn't scale to many systems | ✅ Scales to enterprise deployments |

---

## Use Case Scenarios

### 🏢 **Corporate Environment**
```
Scenario: 1000 workstations, sophisticated APT attack
Traditional: 1000 systems halt, IT team overwhelmed
PhoenixGuard: Systems auto-recover from network, business continues

Recovery Flow:
1. RFKilla detects microcode tampering
2. PhoenixGuard downloads clean BIOS from corporate recovery server
3. Firmware flashed automatically
4. System reboots with clean firmware
5. Clean Ubuntu PXE boot from corporate server
6. User back to work in < 10 minutes
```

### 🏥 **Critical Infrastructure** 
```
Scenario: Hospital systems under attack, patient safety critical
Traditional: Systems halt, medical equipment offline
PhoenixGuard: Systems recover from embedded backups, operations continue

Recovery Flow:
1. Bootkit detected in medical device firmware
2. PhoenixGuard restores from protected embedded backup
3. Clean medical OS boots from signed image
4. Medical equipment continues operating safely
5. IT notified but no emergency response needed
```

### 🏠 **Home/SOHO Environment**
```
Scenario: Home user infected by sophisticated malware
Traditional: User sees "System Halted" message, calls IT support
PhoenixGuard: System recovers from recovery USB, user notices nothing

Recovery Flow:
1. Thermal management tampering detected
2. PhoenixGuard prompts: "Insert recovery USB or continue online recovery?"
3. User inserts recovery USB (or selects auto-recovery)
4. Clean firmware restored from USB
5. System boots clean Ubuntu Live environment
6. User can continue work while system is cleaned
```

---

## Security Analysis

### Attack Resistance

#### **Network Recovery Attacks**
```
Attack: Compromise recovery server
Mitigation: 
- HTTPS with certificate pinning
- Cryptographic signature verification
- Multiple fallback servers
- Offline embedded backup as failsafe
```

#### **Physical Media Attacks**
```
Attack: Replace recovery media with malicious version
Mitigation:
- Write-protection verification
- Cryptographic hash verification
- Multiple independent media sources
- Tamper-evident media packaging
```

#### **Embedded Backup Attacks**
```
Attack: Corrupt embedded backup region
Mitigation:
- Hardware-protected flash regions
- Error correction codes
- Multiple backup copies
- Redundant storage locations
```

### Threat Model

PhoenixGuard defends against:
- ✅ **Firmware-persistent malware** (bootkits, UEFI rootkits)
- ✅ **Microcode manipulation attacks**
- ✅ **Thermal management sabotage**
- ✅ **SPI flash corruption**
- ✅ **EFI variable tampering**
- ✅ **Supply chain attacks** (if recovery sources are clean)

PhoenixGuard may not defend against:
- ⚠️ **Hardware-level attacks** (if all recovery paths compromised)
- ⚠️ **Physical attacks** (if attacker has physical access to block recovery)
- ⚠️ **Network infrastructure attacks** (if all recovery servers compromised)

---

## Deployment Guide

### Quick Start

1. **Build PhoenixGuard**
   ```bash
   cd PhoenixGuard/
   # Build system will be integrated with RFKilla build process
   ```

2. **Configure Recovery Sources**
   ```c
   // Edit PhoenixGuardCore.c
   mRecoverySources[0].Config.Network.Url = "https://your-recovery-server.com/firmware.rom";
   mRecoverySources[1].Config.PhysicalMedia.DevicePath = L"\\USB\\RECOVERY.ROM";
   ```

3. **Integrate with RFKilla**
   ```c
   // Replace CpuDeadLoop() calls with:
   PhoenixGuardExecuteRecovery(PHOENIX_COMPROMISE_MICROCODE, SecurityLevel);
   ```

### Enterprise Deployment

1. **Set up Recovery Infrastructure**
   - Deploy HTTPS recovery servers
   - Prepare signed firmware images
   - Configure PXE boot servers
   - Create recovery media

2. **Configure Network Recovery**
   ```bash
   # Recovery server setup
   sudo apt install nginx
   # Configure firmware hosting with signature verification
   ```

3. **Test Recovery Scenarios**
   ```bash
   # Simulate compromise and verify recovery
   # Test all recovery paths
   # Verify clean OS boot functionality
   ```

---

## Philosophy in Action

### Real-World Example

**Traditional Security Mindset:**
> "We must prevent all attacks. If we detect compromise, halt the system to prevent further damage."

**PhoenixGuard Mindset:**
> "We assume attacks will succeed. When they do, we automatically recover and continue operations with minimal disruption."

### The Phoenix Metaphor

Just as the mythical phoenix burns to ashes and then rises renewed and purified, PhoenixGuard allows systems to be "burned" by malware attacks and then automatically rise again, clean and restored.

The beauty is that each "rebirth" cycle breaks the attack persistence chain - even the most sophisticated malware cannot survive if the system keeps booting from clean sources.

---

## Future Enhancements

### Planned Features
- **🤖 AI-Powered Recovery**: Machine learning to optimize recovery source selection
- **🔗 Blockchain Verification**: Immutable firmware integrity verification
- **☁️ Cloud Integration**: Integration with cloud security services
- **📱 Mobile Management**: Smartphone app for recovery management
- **🌐 Mesh Recovery**: Peer-to-peer recovery networks

### Advanced Capabilities
- **Predictive Recovery**: Trigger recovery before compromise is complete
- **Stealth Mode**: Recovery without alerting attackers
- **Honeypot Integration**: Use compromised systems as deception platforms
- **Threat Intelligence**: Share attack indicators across recovery network

---

**PhoenixGuard: Because the best defense is a perfect recovery.**

*Part of the RFKilla Security Suite - Disrupting, intercepting, and neutralizing advanced persistent threats through innovative recovery and resilience.*
