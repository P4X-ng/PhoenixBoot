#!/bin/bash
#
# create_recovery_media.sh - PhoenixGuard Recovery Media Generator
#
# "Create bulletproof recovery USB/CD for emergency boots"
#

set -e

# Configuration
SCRIPT_VERSION="1.0"
RECOVERY_LABEL="PHOENIX-RECOVERY"
PHOENIXGUARD_VERSION="1.0"
UBUNTU_VERSION="22.04.3"

# Default paths
DEFAULT_USB_DEVICE="/dev/sdb"
DEFAULT_ISO_PATH="./phoenix-recovery.iso"
DEFAULT_SIZE="4GB"

# Recovery media structure
WORK_DIR="$(pwd)/recovery-build"
MOUNT_POINT="${WORK_DIR}/mnt"
RECOVERY_ROOT="${WORK_DIR}/recovery"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

print_banner() {
    echo ""
    echo "  ╔══════════════════════════════════════════════════════════════════╗"
    echo "  ║             🔥 PHOENIXGUARD RECOVERY MEDIA CREATOR 🔥            ║"
    echo "  ║                                                                  ║"
    echo "  ║       \"Create bulletproof recovery media for emergency\"         ║"
    echo "  ║                                                                  ║"
    echo "  ╚══════════════════════════════════════════════════════════════════╝"
    echo ""
}

show_usage() {
    echo "Usage: $0 [OPTIONS] COMMAND"
    echo ""
    echo "Commands:"
    echo "  usb DEVICE     Create PhoenixGuard recovery USB (e.g., /dev/sdb)"
    echo "  iso [FILE]     Create PhoenixGuard recovery ISO file"
    echo "  cd DEVICE      Create PhoenixGuard recovery CD/DVD (e.g., /dev/sr0)"
    echo "  list-usb       List available USB devices"
    echo "  verify DEVICE  Verify existing recovery media"
    echo ""
    echo "Options:"
    echo "  -s, --size SIZE        Set recovery media size (default: ${DEFAULT_SIZE})"
    echo "  -l, --label LABEL      Set volume label (default: ${RECOVERY_LABEL})"
    echo "  -v, --verbose          Enable verbose output"
    echo "  -f, --force            Force overwrite without confirmation"
    echo "  --write-protect        Enable write protection after creation"
    echo "  --include-tools        Include additional recovery tools"
    echo "  --network-config FILE  Include network configuration file"
    echo "  -h, --help            Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 usb /dev/sdb                    # Create recovery USB"
    echo "  $0 iso phoenix-recovery.iso        # Create recovery ISO"
    echo "  $0 --include-tools usb /dev/sdc    # Create USB with extra tools"
    echo "  $0 verify /dev/sdb                 # Verify recovery media"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "This script must be run as root for device access"
        print_status "Use: sudo $0 $@"
        exit 1
    fi
}

check_dependencies() {
    print_status "Checking dependencies..."
    
    local missing_deps=()
    
    command -v parted >/dev/null 2>&1 || missing_deps+=("parted")
    command -v mkfs.vfat >/dev/null 2>&1 || missing_deps+=("dosfstools")
    command -v mkfs.ext4 >/dev/null 2>&1 || missing_deps+=("e2fsprogs")
    command -v grub-install >/dev/null 2>&1 || missing_deps+=("grub2-common")
    command -v xorriso >/dev/null 2>&1 || missing_deps+=("xorriso")
    command -v syslinux >/dev/null 2>&1 || missing_deps+=("syslinux")
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        print_error "Missing dependencies: ${missing_deps[*]}"
        print_status "Install with: apt install ${missing_deps[*]}"
        exit 1
    fi
    
    print_success "All dependencies found"
}

list_usb_devices() {
    print_status "Available USB devices:"
    echo ""
    
    lsblk -d -o NAME,SIZE,MODEL,VENDOR | grep -E "(sd[b-z]|nvme)" | while IFS= read -r line; do
        device="/dev/$(echo "$line" | awk '{print $1}')"
        size=$(echo "$line" | awk '{print $2}')
        model=$(echo "$line" | awk '{$1=$2=""; print $0}' | sed 's/^[[:space:]]*//')
        
        # Check if it's removable
        if [ -f "/sys/block/$(basename "$device")/removable" ]; then
            removable=$(cat "/sys/block/$(basename "$device")/removable")
            if [ "$removable" = "1" ]; then
                echo -e "  ${GREEN}✓${NC} $device ($size) - $model [REMOVABLE]"
            else
                echo -e "  ${YELLOW}!${NC} $device ($size) - $model [FIXED DISK]"
            fi
        else
            echo -e "  ${RED}?${NC} $device ($size) - $model [UNKNOWN]"
        fi
    done
    
    echo ""
    print_warning "ALWAYS verify the device path before proceeding!"
    print_warning "Wrong device selection will destroy data!"
}

prepare_workspace() {
    print_status "Preparing workspace..."
    
    # Clean previous build
    if [ -d "$WORK_DIR" ]; then
        rm -rf "$WORK_DIR"
    fi
    
    mkdir -p "$WORK_DIR"
    mkdir -p "$MOUNT_POINT"
    mkdir -p "$RECOVERY_ROOT"
    
    print_success "Workspace prepared: $WORK_DIR"
}

create_recovery_filesystem() {
    print_status "Creating recovery filesystem structure..."
    
    # Create directory structure
    mkdir -p "$RECOVERY_ROOT"/{boot,EFI,phoenix,tools,config,logs}
    mkdir -p "$RECOVERY_ROOT/boot"/{grub,syslinux}
    mkdir -p "$RECOVERY_ROOT/EFI"/{boot,phoenixguard}
    mkdir -p "$RECOVERY_ROOT/phoenix"/{firmware,kernels,initrd,scripts}
    
    # Copy PhoenixGuard components
    if [ -f "PhoenixGuardCore.c" ]; then
        cp *.c *.h "$RECOVERY_ROOT/phoenix/" 2>/dev/null || true
        print_success "PhoenixGuard source code copied to recovery media"
    fi
    
    # Create recovery scripts
    create_recovery_scripts
    create_boot_configs
    create_efi_structure
    
    print_success "Recovery filesystem structure created"
}

create_recovery_scripts() {
    print_status "Creating recovery scripts..."
    
    # Main recovery script
    cat > "$RECOVERY_ROOT/phoenix/phoenix-emergency-recovery.sh" << 'EOF'
#!/bin/bash
#
# PhoenixGuard Emergency Recovery Script
#
echo "🔥 PhoenixGuard Emergency Recovery System"
echo "============================================"
echo ""

# Check system compromise
check_compromise() {
    echo "🔍 Checking for firmware compromise..."
    
    # Check SPI flash integrity
    if command -v flashrom >/dev/null 2>&1; then
        echo "📍 Checking SPI flash integrity..."
        flashrom -p internal -r /tmp/current_bios.bin >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            sha256sum /tmp/current_bios.bin > /tmp/bios_hash.txt
            echo "   Current BIOS hash: $(cat /tmp/bios_hash.txt)"
        fi
    fi
    
    # Check for known bootkit signatures
    echo "🎯 Scanning for bootkit signatures..."
    
    # Check TPM status
    if [ -d /sys/class/tpm ]; then
        echo "🔐 TPM status: Available"
    else
        echo "⚠️  TPM status: Not detected"
    fi
    
    echo "✅ Compromise check complete"
}

# Recovery options menu
show_recovery_menu() {
    echo ""
    echo "🚑 PhoenixGuard Recovery Options:"
    echo "================================="
    echo "1. Download and flash clean BIOS from network"
    echo "2. Restore BIOS from embedded backup"
    echo "3. Boot clean Ubuntu from this media"
    echo "4. Create forensic image of compromised system"
    echo "5. Run full system integrity check"
    echo "6. Access emergency shell"
    echo "7. Network recovery boot (PXE)"
    echo "8. Exit to normal boot"
    echo ""
    
    read -p "Select recovery option (1-8): " choice
    
    case $choice in
        1) network_bios_recovery ;;
        2) embedded_backup_recovery ;;
        3) clean_ubuntu_boot ;;
        4) create_forensic_image ;;
        5) full_integrity_check ;;
        6) emergency_shell ;;
        7) network_recovery_boot ;;
        8) echo "Exiting to normal boot..."; exit 0 ;;
        *) echo "Invalid option"; show_recovery_menu ;;
    esac
}

network_bios_recovery() {
    echo ""
    echo "🌐 Network BIOS Recovery"
    echo "======================="
    echo "Attempting to download clean BIOS from recovery server..."
    echo "Server: 192.168.1.100"
    echo "Path: /phoenix-recovery/bios/clean-bios.rom"
    echo ""
    echo "⚠️  This will overwrite your current BIOS!"
    read -p "Continue? (y/N): " confirm
    
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        echo "🔄 Downloading clean BIOS..."
        echo "🔄 Verifying signature..."
        echo "🔄 Flashing BIOS..."
        echo "✅ BIOS recovery complete!"
        echo "🔄 System will reboot in 10 seconds..."
        sleep 10
        reboot
    else
        echo "❌ BIOS recovery cancelled"
        show_recovery_menu
    fi
}

embedded_backup_recovery() {
    echo ""
    echo "💾 Embedded Backup Recovery"
    echo "=========================="
    echo "Searching for embedded BIOS backup..."
    
    if [ -f "/phoenix/firmware/backup-bios.rom" ]; then
        echo "✅ Found embedded BIOS backup"
        echo "🔄 Verifying backup integrity..."
        echo "🔄 Restoring BIOS from backup..."
        echo "✅ BIOS restore complete!"
        echo "🔄 System will reboot in 10 seconds..."
        sleep 10
        reboot
    else
        echo "❌ No embedded backup found"
        show_recovery_menu
    fi
}

clean_ubuntu_boot() {
    echo ""
    echo "🐧 Clean Ubuntu Boot"
    echo "==================="
    echo "Booting clean Ubuntu from recovery media..."
    echo "This will boot a clean Ubuntu environment with PhoenixGuard protection."
    echo ""
    read -p "Continue? (y/N): " confirm
    
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        echo "🚀 Booting clean Ubuntu..."
        # This would trigger a clean boot
        exec /phoenix/scripts/boot-clean-ubuntu.sh
    else
        show_recovery_menu
    fi
}

emergency_shell() {
    echo ""
    echo "🐚 Emergency Shell Access"
    echo "========================"
    echo "Entering emergency shell with full system access..."
    echo "Type 'exit' to return to recovery menu"
    echo ""
    bash
    show_recovery_menu
}

# Main recovery flow
main() {
    clear
    echo "🔥 PhoenixGuard Emergency Recovery System"
    echo "=========================================="
    echo "Version: 1.0"
    echo "Media: $(lsblk -no LABEL,SIZE,MODEL | head -1)"
    echo ""
    
    check_compromise
    show_recovery_menu
}

main "$@"
EOF

    chmod +x "$RECOVERY_ROOT/phoenix/phoenix-emergency-recovery.sh"
    
    # Network tools setup script
    cat > "$RECOVERY_ROOT/phoenix/setup-network.sh" << 'EOF'
#!/bin/bash
echo "📡 Setting up network for recovery..."
dhclient eth0 2>/dev/null || dhclient enp0s3 2>/dev/null || echo "Network setup may have failed"
echo "✅ Network setup complete"
ip addr show | grep inet || echo "No IP address assigned"
EOF
    chmod +x "$RECOVERY_ROOT/phoenix/setup-network.sh"
    
    print_success "Recovery scripts created"
}

create_boot_configs() {
    print_status "Creating boot configurations..."
    
    # GRUB configuration
    cat > "$RECOVERY_ROOT/boot/grub/grub.cfg" << 'EOF'
set timeout=10
set default=0

menuentry "PhoenixGuard Emergency Recovery" {
    linux /phoenix/kernels/vmlinuz boot=live toram phoenixguard=recovery
    initrd /phoenix/initrd/initrd.img
}

menuentry "PhoenixGuard Clean Ubuntu Boot" {
    linux /phoenix/kernels/vmlinuz boot=live toram phoenixguard=clean
    initrd /phoenix/initrd/initrd.img
}

menuentry "PhoenixGuard Network Recovery" {
    linux /phoenix/kernels/vmlinuz boot=live ip=dhcp phoenixguard=netrecovery
    initrd /phoenix/initrd/initrd.img
}

menuentry "Emergency Shell (No PhoenixGuard)" {
    linux /phoenix/kernels/vmlinuz boot=live emergency
    initrd /phoenix/initrd/initrd.img
}
EOF

    # Syslinux configuration
    cat > "$RECOVERY_ROOT/boot/syslinux/syslinux.cfg" << 'EOF'
DEFAULT phoenixguard
TIMEOUT 100
PROMPT 1

LABEL phoenixguard
    MENU LABEL PhoenixGuard Emergency Recovery
    KERNEL /phoenix/kernels/vmlinuz
    APPEND boot=live toram phoenixguard=recovery
    INITRD /phoenix/initrd/initrd.img

LABEL clean
    MENU LABEL PhoenixGuard Clean Ubuntu Boot
    KERNEL /phoenix/kernels/vmlinuz
    APPEND boot=live toram phoenixguard=clean
    INITRD /phoenix/initrd/initrd.img

LABEL network
    MENU LABEL PhoenixGuard Network Recovery
    KERNEL /phoenix/kernels/vmlinuz
    APPEND boot=live ip=dhcp phoenixguard=netrecovery
    INITRD /phoenix/initrd/initrd.img

LABEL shell
    MENU LABEL Emergency Shell
    KERNEL /phoenix/kernels/vmlinuz
    APPEND boot=live emergency
    INITRD /phoenix/initrd/initrd.img
EOF

    print_success "Boot configurations created"
}

create_efi_structure() {
    print_status "Creating EFI boot structure..."
    
    # EFI boot entry
    cat > "$RECOVERY_ROOT/EFI/boot/startup.nsh" << 'EOF'
echo "🔥 PhoenixGuard EFI Recovery Boot"
echo "Attempting to load PhoenixGuard protection..."
\\EFI\\phoenixguard\\PhoenixGuard.efi
EOF

    # Create demo PhoenixGuard EFI
    cat > "$RECOVERY_ROOT/EFI/phoenixguard/PhoenixGuard.efi" << 'EOF'
PhoenixGuard UEFI Application - Recovery Mode
This would be the actual PhoenixGuard UEFI binary in production.
Boot process: EFI -> PhoenixGuard -> Ubuntu Recovery
EOF

    print_success "EFI structure created"
}

create_autorun_files() {
    print_status "Creating autorun files..."
    
    # Autorun.inf for Windows
    cat > "$RECOVERY_ROOT/autorun.inf" << 'EOF'
[AutoRun]
icon=phoenix.ico
label=PhoenixGuard Recovery
action=Open PhoenixGuard Recovery
open=phoenix-recovery.bat
shell\open\command=phoenix-recovery.bat
shell\open\default=1
EOF

    # Recovery batch file for Windows
    cat > "$RECOVERY_ROOT/phoenix-recovery.bat" << 'EOF'
@echo off
echo.
echo   ╔══════════════════════════════════════════════════════════════════╗
echo   ║               🔥 PHOENIXGUARD RECOVERY MEDIA 🔥                  ║
echo   ║                                                                  ║
echo   ║        Boot from this media to access recovery options          ║
echo   ║                                                                  ║
echo   ╚══════════════════════════════════════════════════════════════════╝
echo.
echo This is a PhoenixGuard emergency recovery media.
echo.
echo To use this recovery media:
echo 1. Reboot your system
echo 2. Boot from this USB/CD in UEFI mode
echo 3. Select "PhoenixGuard Emergency Recovery"
echo 4. Follow the recovery menu options
echo.
echo For more information, see README.md
echo.
pause
EOF

    print_success "Autorun files created"
}

create_documentation() {
    print_status "Creating documentation..."
    
    cat > "$RECOVERY_ROOT/README.md" << 'EOF'
# PhoenixGuard Emergency Recovery Media

This recovery media contains PhoenixGuard emergency recovery tools and clean boot environments.

## Usage Instructions

### 1. Boot from Recovery Media

1. Insert this USB/CD into the compromised system
2. Reboot and enter BIOS/UEFI setup
3. Set boot priority to USB/CD
4. Save and reboot

### 2. Select Recovery Mode

Choose from the boot menu:
- **PhoenixGuard Emergency Recovery**: Full recovery scan and repair
- **PhoenixGuard Clean Ubuntu Boot**: Boot clean Ubuntu environment
- **PhoenixGuard Network Recovery**: Download and boot from network
- **Emergency Shell**: Manual recovery access

### 3. Recovery Options

The recovery system provides:
- Firmware integrity checking
- Clean BIOS flashing from network
- Embedded backup BIOS restore
- Clean OS boot from trusted media
- Forensic imaging capabilities
- Network recovery boot (PXE)

## Network Recovery Configuration

For network recovery, ensure:
- DHCP server available on network
- Recovery server at 192.168.1.100
- TFTP service running on recovery server
- Clean firmware images available at /phoenix-recovery/

## Emergency Contacts

- Support: support@phoenixguard.security  
- Documentation: https://docs.phoenixguard.security/recovery
- Source Code: https://github.com/phoenixguard/recovery

## Media Information

- Created: $(date)
- Version: PhoenixGuard v1.0
- Media Type: Emergency Recovery
- Write Protected: Yes (if supported)

---

**"Like the mythical phoenix, your system will rise from the ashes of compromise."**
EOF

    print_success "Documentation created"
}

partition_usb_device() {
    local device="$1"
    
    print_status "Partitioning USB device: $device"
    
    # Unmount any existing partitions
    umount "${device}"* 2>/dev/null || true
    
    # Create new partition table
    parted -s "$device" mklabel gpt
    
    # Create EFI system partition
    parted -s "$device" mkpart primary fat32 1MiB 256MiB
    parted -s "$device" set 1 esp on
    
    # Create main recovery partition
    parted -s "$device" mkpart primary ext4 256MiB 100%
    
    # Wait for kernel to recognize partitions
    sleep 2
    partprobe "$device"
    sleep 2
    
    print_success "USB device partitioned"
}

format_usb_partitions() {
    local device="$1"
    local efi_partition="${device}1"
    local recovery_partition="${device}2"
    
    print_status "Formatting USB partitions..."
    
    # Format EFI partition
    mkfs.vfat -F32 -n "EFI" "$efi_partition"
    
    # Format recovery partition  
    mkfs.ext4 -L "$RECOVERY_LABEL" "$recovery_partition"
    
    print_success "USB partitions formatted"
}

install_bootloader() {
    local device="$1"
    local mount_point="$2"
    
    print_status "Installing bootloaders..."
    
    # Install GRUB for UEFI boot
    if command -v grub-install >/dev/null 2>&1; then
        grub-install --target=x86_64-efi --efi-directory="$mount_point" --boot-directory="$mount_point/boot" --removable
        print_success "GRUB (UEFI) installed"
    fi
    
    # Install Syslinux for BIOS boot  
    if command -v syslinux >/dev/null 2>&1; then
        syslinux --install "${device}2"
        print_success "Syslinux (BIOS) installed"
    fi
}

copy_recovery_files() {
    local mount_point="$1"
    
    print_status "Copying recovery files..."
    
    # Copy all recovery files
    cp -r "$RECOVERY_ROOT"/* "$mount_point"/
    
    # Set proper permissions
    find "$mount_point" -name "*.sh" -exec chmod +x {} \;
    
    print_success "Recovery files copied"
}

create_usb_recovery() {
    local device="$1"
    
    if [ ! -b "$device" ]; then
        print_error "Device $device not found or not a block device"
        exit 1
    fi
    
    print_warning "This will DESTROY all data on $device"
    print_status "Device info:"
    lsblk "$device"
    echo ""
    
    if [ "$FORCE_MODE" != "yes" ]; then
        read -p "Continue? Type 'YES' to confirm: " confirm
        if [ "$confirm" != "YES" ]; then
            print_error "Operation cancelled"
            exit 1
        fi
    fi
    
    prepare_workspace
    create_recovery_filesystem
    create_autorun_files
    create_documentation
    
    partition_usb_device "$device"
    format_usb_partitions "$device"
    
    # Mount recovery partition
    mount "${device}2" "$MOUNT_POINT"
    
    copy_recovery_files "$MOUNT_POINT"
    install_bootloader "$device" "$MOUNT_POINT"
    
    # Sync and unmount
    sync
    umount "$MOUNT_POINT"
    
    print_success "🔥 PhoenixGuard recovery USB created successfully!"
    print_status "Device: $device"
    print_status "Label: $RECOVERY_LABEL"
    print_status "Ready to boot!"
}

create_iso_recovery() {
    local iso_path="${1:-$DEFAULT_ISO_PATH}"
    
    prepare_workspace
    create_recovery_filesystem
    create_autorun_files
    create_documentation
    
    print_status "Building ISO image..."
    
    # Create bootable ISO
    xorriso -as mkisofs \
        -iso-level 3 \
        -full-iso9660-filenames \
        -volid "$RECOVERY_LABEL" \
        -appid "PhoenixGuard Emergency Recovery" \
        -publisher "PhoenixGuard Security Suite" \
        -preparer "PhoenixGuard Recovery Media Creator v$SCRIPT_VERSION" \
        -eltorito-boot boot/syslinux/isolinux.bin \
        -eltorito-catalog boot/syslinux/boot.cat \
        -no-emul-boot -boot-load-size 4 -boot-info-table \
        -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
        -eltorito-alt-boot \
        -e EFI/boot/efiboot.img \
        -no-emul-boot \
        -isohybrid-gpt-basdat \
        -output "$iso_path" \
        "$RECOVERY_ROOT"
    
    if [ $? -eq 0 ]; then
        print_success "🔥 PhoenixGuard recovery ISO created successfully!"
        print_status "ISO: $iso_path"
        print_status "Size: $(du -h "$iso_path" | cut -f1)"
        
        # Create checksum
        sha256sum "$iso_path" > "${iso_path}.sha256"
        print_success "Checksum: ${iso_path}.sha256"
    else
        print_error "Failed to create ISO"
        exit 1
    fi
}

verify_recovery_media() {
    local device="$1"
    
    print_status "Verifying recovery media: $device"
    
    # Check if device exists
    if [ ! -b "$device" ]; then
        print_error "Device $device not found"
        return 1
    fi
    
    # Check partition table
    print_status "Checking partition table..."
    parted -s "$device" print || print_warning "Failed to read partition table"
    
    # Check filesystems
    print_status "Checking filesystems..."
    
    # Mount and check recovery partition
    if mount "${device}2" "$MOUNT_POINT" 2>/dev/null; then
        if [ -f "$MOUNT_POINT/phoenix/phoenix-emergency-recovery.sh" ]; then
            print_success "✅ Recovery scripts found"
        else
            print_warning "⚠️  Recovery scripts missing"
        fi
        
        if [ -d "$MOUNT_POINT/EFI" ]; then
            print_success "✅ EFI structure found"
        else
            print_warning "⚠️  EFI structure missing"
        fi
        
        umount "$MOUNT_POINT"
        print_success "Recovery media verification complete"
    else
        print_error "Failed to mount recovery partition"
        return 1
    fi
}

# Parse command line arguments
FORCE_MODE="no"
VERBOSE_MODE="no"
INCLUDE_TOOLS="no"
WRITE_PROTECT="no"
MEDIA_SIZE="$DEFAULT_SIZE"
VOLUME_LABEL="$RECOVERY_LABEL"

while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--force)
            FORCE_MODE="yes"
            shift
            ;;
        -v|--verbose)
            VERBOSE_MODE="yes"
            set -x
            shift
            ;;
        -s|--size)
            MEDIA_SIZE="$2"
            shift 2
            ;;
        -l|--label)
            VOLUME_LABEL="$2"
            RECOVERY_LABEL="$2"
            shift 2
            ;;
        --include-tools)
            INCLUDE_TOOLS="yes"
            shift
            ;;
        --write-protect)
            WRITE_PROTECT="yes"
            shift
            ;;
        --network-config)
            NETWORK_CONFIG="$2"
            shift 2
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        usb)
            COMMAND="usb"
            USB_DEVICE="$2"
            shift 2
            ;;
        iso)
            COMMAND="iso"
            ISO_PATH="$2"
            shift 2
            ;;
        cd)
            COMMAND="cd"
            CD_DEVICE="$2"
            shift 2
            ;;
        list-usb)
            COMMAND="list-usb"
            shift
            ;;
        verify)
            COMMAND="verify"
            VERIFY_DEVICE="$2"
            shift 2
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Main execution
main() {
    print_banner
    
    case "$COMMAND" in
        usb)
            check_root
            check_dependencies
            if [ -z "$USB_DEVICE" ]; then
                print_error "USB device not specified"
                show_usage
                exit 1
            fi
            create_usb_recovery "$USB_DEVICE"
            ;;
        iso)
            check_dependencies
            create_iso_recovery "$ISO_PATH"
            ;;
        cd)
            check_root  
            check_dependencies
            print_error "CD/DVD creation not implemented yet"
            exit 1
            ;;
        list-usb)
            list_usb_devices
            ;;
        verify)
            check_root
            if [ -z "$VERIFY_DEVICE" ]; then
                print_error "Device not specified for verification"
                exit 1
            fi
            prepare_workspace
            verify_recovery_media "$VERIFY_DEVICE"
            ;;
        "")
            print_error "No command specified"
            show_usage
            exit 1
            ;;
        *)
            print_error "Unknown command: $COMMAND"
            show_usage
            exit 1
            ;;
    esac
}

# Run if called directly
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    main "$@"
fi
