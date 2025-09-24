# Hardware Firmware Recovery Documentation

## Overview

PhoenixGuard's Hardware Firmware Recovery system provides comprehensive protection against firmware-level attacks by implementing direct SPI flash access, bootkit protection bypass, and automated integrity verification.

## Core Capabilities

### 🔧 **SPI Flash Extraction**
- Direct hardware-level firmware dumps using `flashrom`
- Bypasses OS-level security restrictions
- Creates timestamped binary dumps with SHA256 verification
- Supports all major SPI flash chips

### 🛡️ **Bootkit Protection Bypass**
- Automatic detection of hardware write locks
- Multiple bypass methods:
  - Chipsec register manipulation
  - Flashrom forced parameters
  - Alternative programmer interfaces
- Supports bypassing FLOCKDN, BIOSWE, and SPI protected ranges

### 📊 **Baseline Integrity Verification**
- Compare firmware against known-good signature database
- Hardware-specific baseline matching
- Support for multiple firmware versions per hardware platform
- Automatic detection of known malicious firmware signatures

### 💾 **Secure Backup & Restore**
- Automated backup creation before any write operations
- Cryptographic verification of backup integrity
- One-command firmware restoration from verified backups
- Support for external backup storage

## Hardware Firmware Recovery Script

### Command-Line Interface

```bash
# Basic firmware integrity check (safe, no writes)
sudo python3 scripts/hardware_firmware_recovery.py --verify-only /dev/null

# Full recovery with clean firmware image
sudo python3 scripts/hardware_firmware_recovery.py clean_firmware.bin

# Verbose output for debugging
sudo python3 scripts/hardware_firmware_recovery.py --verbose clean_firmware.bin

# Custom results output location
sudo python3 scripts/hardware_firmware_recovery.py --output results.json clean_firmware.bin
```

### Python API Usage

```python
from scripts.hardware_firmware_recovery import HardwareFirmwareRecovery

# Create recovery instance
recovery = HardwareFirmwareRecovery("clean_firmware.bin", verify_only=True)

# Check requirements and hardware
recovery.check_requirements()
recovery.detect_hardware_info()
recovery.detect_flash_chip()

# Detect bootkit protections
protections = recovery.detect_bootkit_protections()

# Extract current firmware
firmware_dump = recovery.dump_flash("current_firmware.bin")

# Verify against baseline
verification = recovery.verify_against_baseline(firmware_hash, hardware_info)

# Write clean firmware (with protection bypass)
success = recovery.write_flash("clean_firmware.bin")

# Restore from backup
recovery.restore_backup("firmware_backup_20250822.bin")
```

## Integration with VM Recovery

### Dom0 Remediation Integration

The hardware firmware recovery system integrates seamlessly with Xen dom0 remediation workflows:

```bash
# Dom0 automatically checks host firmware during remediation
sudo resources/xen/dom0/bootkit-remediate.sh

# Manual firmware check from dom0
ssh host-system "sudo python3 /path/to/hardware_firmware_recovery.py --verify-only /dev/null"
```

### KVM Snapshot Jump

Enhanced KVM snapshot launcher with:

- **CPU Passthrough**: Host CPU features including AES, AVX, AVX2
- **Topology Detection**: Automatic core/thread optimization
- **Secure Boot**: OVMF with Microsoft key templates
- **GPU Passthrough**: NVIDIA GPU with audio passthrough
- **Enhanced Networking**: Bridged networking for SSH access

```bash
# Launch clean snapshot with GPU passthrough
sudo systemctl start kvm-snapshot-jump.service

# Or use PhoenixGuard UEFI menu: Press 'K' for KVM Jump
```

## Baseline Database Format

### Firmware Baseline JSON Structure

```json
{
  "firmware_hashes": {
    "manufacturer_model_version": {
      "hashes": [
        "sha256_hash_of_clean_firmware_1",
        "sha256_hash_of_clean_firmware_2"
      ],
      "description": "ASUS ROG Strix B550-F BIOS 2801",
      "date_added": "2025-01-15T10:30:00Z"
    },
    "known_malicious": [
      "sha256_hash_of_known_bootkit_1",
      "sha256_hash_of_known_bootkit_2"
    ]
  }
}
```

### Baseline Database Locations

The script checks for baseline databases in this order:
1. `firmware_baseline.json` (current directory)
2. `Tegrity/baselines/firmware_baseline.json`
3. `/etc/phoenixguard/firmware_baseline.json`

## Hardware Requirements

### Supported Flash Chips
- Most SPI flash chips supported by flashrom
- Common chips: Winbond, Macronix, SST, AMIC, etc.
- Automatic chip detection and size verification

### Required Tools
- **flashrom**: SPI flash programming tool
- **dmidecode**: Hardware information detection
- **lspci**: PCI device enumeration
- **chipsec** (optional): Hardware register manipulation

### Installation
```bash
# Ubuntu/Debian
sudo apt install flashrom dmidecode pciutils

# Optional but recommended for bootkit bypass
pip install chipsec
```

## Security Considerations

### Root Privileges
- Hardware firmware recovery requires root access
- Direct hardware access bypasses OS security restrictions
- All operations are logged and auditable

### Protection Bypass Ethics
- Only bypasses protections on hardware you own
- Designed for legitimate recovery scenarios
- Can potentially brick systems if used incorrectly

### Backup Safety
- Always creates backups before any write operations
- Verifies backup integrity with SHA256 hashing
- Stores backups with timestamps for tracking

## Troubleshooting

### Common Issues

**"Flash chip not detected"**
```bash
# Check if flashrom can access the chip
sudo flashrom --programmer internal --probe

# Verify hardware is supported
sudo flashrom --programmer internal --verbose
```

**"Protection bypass failed"**
```bash
# Check if chipsec is installed
pip install chipsec

# Verify hardware register access
sudo chipsec_main -m common.spi_lock
```

**"Baseline database not found"**
```bash
# Create basic baseline database
echo '{"firmware_hashes": {}}' > firmware_baseline.json

# Or use Tegrity baseline location
mkdir -p Tegrity/baselines/
echo '{"firmware_hashes": {}}' > Tegrity/baselines/firmware_baseline.json
```

### Debug Mode
```bash
# Run with maximum verbosity
sudo python3 scripts/hardware_firmware_recovery.py --verbose --verify-only /dev/null

# Check system logs
journalctl -u kvm-snapshot-jump.service -f
```

## Best Practices

### Pre-Recovery Checklist
1. ✅ Verify hardware is supported
2. ✅ Create external backup of critical data  
3. ✅ Ensure clean firmware image is verified
4. ✅ Have hardware programmer available as fallback
5. ✅ Test recovery procedure in lab environment

### Recovery Workflow
1. **Assess**: Run integrity check to understand current state
2. **Backup**: Create verified backup of current firmware
3. **Bypass**: Automatically bypass bootkit protections
4. **Verify**: Check clean firmware against baseline database
5. **Flash**: Write clean firmware with verification
6. **Test**: Verify system boots correctly with clean firmware

### Post-Recovery Validation
```bash
# Verify clean firmware boot
sudo python3 scripts/hardware_firmware_recovery.py --verify-only /dev/null

# Check system integrity
make -C Tegrity verify

# Validate boot process
sudo resources/xen/dom0/validate-clean-os.sh
```

## Advanced Usage

### Custom Baseline Creation
```python
# Create hardware-specific baseline entry
recovery = HardwareFirmwareRecovery("/dev/null", verify_only=True)
recovery.detect_hardware_info()

# Extract firmware hash
firmware_path = recovery.dump_flash()
firmware_hash = recovery._calculate_file_hash(firmware_path)

# Add to baseline database manually or via API
```

### Automated Monitoring
```bash
# Set up automated firmware monitoring
echo "0 2 * * * root python3 /path/to/hardware_firmware_recovery.py --verify-only /dev/null" >> /etc/crontab

# Monitor for changes
inotify-hookable -f /boot/efi -c "python3 /path/to/hardware_firmware_recovery.py --verify-only /dev/null"
```

## API Reference

### Key Classes

**HardwareFirmwareRecovery(recovery_image_path, verify_only=False)**
- Main recovery class
- Handles all firmware operations
- Provides comprehensive logging and results

### Key Methods

**check_requirements()** → bool
- Verify required tools are available
- Check for root privileges
- Return True if ready for operations

**detect_hardware_info()** → None  
- Collect system hardware information
- Store results for baseline matching
- Extract manufacturer/model details

**detect_flash_chip()** → bool
- Detect SPI flash chip type and size
- Verify flashrom compatibility
- Return True if chip detected successfully

**detect_bootkit_protections()** → dict
- Scan for hardware protection mechanisms
- Detect FLOCKDN, BIOSWE, protected ranges
- Return dictionary of protection status

**dump_flash(output_path=None)** → Path
- Extract complete SPI flash contents
- Create timestamped binary dump
- Return path to created dump file

**write_flash(firmware_path, skip_confirmation=False)** → bool
- Write firmware with protection bypass
- Automatic verification after write
- Return True if successful

**restore_backup(backup_path=None)** → bool
- Restore firmware from verified backup
- Use latest backup if path not specified
- Return True if restoration successful

This comprehensive firmware recovery system provides the foundation for PhoenixGuard's "embrace the breach" philosophy - even if firmware is compromised, the system can automatically detect, bypass protections, and restore clean firmware to break the persistence chain.
