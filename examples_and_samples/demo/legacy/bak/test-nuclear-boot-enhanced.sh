#!/usr/bin/env bash
set -euo pipefail

# PhoenixGuard Nuclear Boot Enhanced Test Script
# ===============================================
# 
# Test modes:
# - Virtual: QEMU testing with auto-feedback
# - USB: Create bootable USB for real hardware
# - ISO: Create bootable ISO image

log() { echo "[nuclear-test] $*"; }

# Create disk image with progress feedback
create_boot_image() {
    local image_path="$1"
    local image_size="${2:-64}"  # MB
    local label="${3:-PHOENIXGUARD}"
    
    log "💿 Creating ${image_size}MB boot image: $image_path"
    
    # Create image with progress
    log "📝 Allocating disk space..."
    pv -p -s "${image_size}M" /dev/zero 2>/dev/null | dd of="$image_path" bs=1M count="$image_size" 2>/dev/null || \
        dd if=/dev/zero of="$image_path" bs=1M count="$image_size" status=progress 2>/dev/null || \
        { log "⏳ Creating ${image_size}MB image (please wait)..."; dd if=/dev/zero of="$image_path" bs=1M count="$image_size" 2>/dev/null; }
    
    log "🖊️  Formatting as FAT32..."
    mkfs.vfat -F 32 -n "$label" "$image_path" >/dev/null 2>&1
    
    log "✅ Boot image created successfully"
}

# Setup EFI structure on mounted filesystem
setup_efi_structure() {
    local mount_point="$1"
    
    log "📁 Creating EFI directory structure..."
    sudo mkdir -p "$mount_point/EFI/BOOT"
    sudo mkdir -p "$mount_point/EFI/PhoenixGuard"
    
    log "📦 Copying Nuclear Boot application..."
    # Primary auto-boot location
    sudo cp NuclearBootEdk2.efi "$mount_point/EFI/BOOT/BOOTX64.EFI"
    # PhoenixGuard specific location
    sudo cp NuclearBootEdk2.efi "$mount_point/EFI/PhoenixGuard/"
    
    # Copy GRUB if available for 'G' option testing
    if [[ -f /boot/efi/EFI/PhoenixGuard/grubx64.efi ]]; then
        log "🍔 Adding GRUB support for 'G' option..."
        sudo cp /boot/efi/EFI/PhoenixGuard/grubx64.efi "$mount_point/EFI/PhoenixGuard/"
        
        # Create a simple grub.cfg for testing
        sudo tee "$mount_point/EFI/PhoenixGuard/grub.cfg" >/dev/null <<'EOF'
set timeout=5
set default=0

menuentry "PhoenixGuard Test Mode" {
    echo "PhoenixGuard GRUB Test - This would boot your configured system"
    echo "Press any key to return to Nuclear Boot..."
    read
}

menuentry "Return to Nuclear Boot" {
    exit
}
EOF
    fi
    
    # Create startup script for UEFI shell
    sudo tee "$mount_point/startup.nsh" >/dev/null <<'EOF'
@echo off
cls
echo.
echo 🦀🔥 PhoenixGuard Nuclear Boot Auto-Start 🔥🦀
echo ================================================
echo.
echo Starting Nuclear Boot application...
echo.
EFI\BOOT\BOOTX64.EFI
EOF
    
    log "✅ EFI structure setup complete"
}

# Virtual test with QEMU
test_virtual() {
    log "🖥️  Virtual Test Mode (QEMU)"
    
    local image_path="/tmp/phoenixguard-test-$$.img"
    local vars_path="/tmp/phoenixguard-vars-$$.fd"
    
    # Create bootable image
    create_boot_image "$image_path" 64 "PGTEST"
    
    # Mount and setup
    local mount_point="/tmp/phoenixguard-mount-$$"
    mkdir -p "$mount_point"
    sudo mount -o loop "$image_path" "$mount_point"
    
    setup_efi_structure "$mount_point"
    
    sudo umount "$mount_point"
    rmdir "$mount_point"
    
    # Create OVMF vars
    log "⚙️  Setting up UEFI environment..."
    cp /usr/share/OVMF/OVMF_VARS_4M.fd "$vars_path"
    
    log "🚀 Launching QEMU Virtual Test..."
    log "💡 Expected behavior:"
    log "   - Auto-boot to Nuclear Boot application"
    log "   - PhoenixGuard banner with options menu"
    log "   - [G] = Test Clean GRUB path"
    log "   - [Enter] = Nuclear Boot demo sequence"
    log "   - Press Ctrl+Alt+Q to quit QEMU"
    
    echo
    read -p "Press Enter to launch virtual test..."
    
    qemu-system-x86_64 \
        -machine type=q35 \
        -cpu host \
        -enable-kvm \
        -m 2048 \
        -smp 2 \
        -drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd \
        -drive if=pflash,format=raw,file="$vars_path" \
        -drive file="$image_path",format=raw,if=ide \
        -netdev user,id=net0,hostname=phoenixguard-test \
        -device e1000,netdev=net0 \
        -vga std \
        -display gtk,show-cursor=on \
        -name "PhoenixGuard Nuclear Boot Test" \
        -no-reboot \
        -boot order=c
    
    # Cleanup
    rm -f "$image_path" "$vars_path"
    log "✅ Virtual test completed"
}

# Create bootable USB
create_usb() {
    local usb_device="$1"
    
    if [[ ! -b "$usb_device" ]]; then
        log "❌ Device $usb_device not found or not a block device"
        log "Available devices:"
        lsblk -d -o NAME,SIZE,MODEL | grep -E "(sd|nvme)"
        exit 1
    fi
    
    log "🔥 Creating bootable USB: $usb_device"
    log "⚠️  WARNING: This will DESTROY all data on $usb_device!"
    
    # Show device info
    local device_info
    device_info=$(lsblk -d -o SIZE,MODEL "$usb_device" | tail -1)
    log "📱 Device info: $device_info"
    
    read -p "Type 'YES' to continue with USB creation: " confirm
    if [[ "$confirm" != "YES" ]]; then
        log "❌ Aborted by user"
        exit 1
    fi
    
    log "⚡ Partitioning USB device..."
    # Create GPT partition table with EFI system partition
    sudo parted -s "$usb_device" mklabel gpt
    sudo parted -s "$usb_device" mkpart primary fat32 1MiB 100%
    sudo parted -s "$usb_device" set 1 esp on
    
    # Format the partition
    local usb_partition="${usb_device}1"
    if [[ "$usb_device" == *"nvme"* ]]; then
        usb_partition="${usb_device}p1"
    fi
    
    log "🖊️  Formatting partition as FAT32..."
    sudo mkfs.vfat -F 32 -n "PHOENIXGUARD" "$usb_partition"
    
    # Mount and setup
    local mount_point="/tmp/phoenixguard-usb-$$"
    mkdir -p "$mount_point"
    sudo mount "$usb_partition" "$mount_point"
    
    setup_efi_structure "$mount_point"
    
    # Add README
    sudo tee "$mount_point/README.txt" >/dev/null <<'EOF'
PhoenixGuard Nuclear Boot USB
=============================

This USB contains the PhoenixGuard Nuclear Boot UEFI application.

To boot:
1. Insert USB into target computer
2. Boot to UEFI/BIOS settings
3. Enable UEFI boot mode (disable Legacy/CSM)
4. Set USB as first boot device
5. Save and restart

Expected behavior:
- Auto-boot to Nuclear Boot application
- PhoenixGuard banner with menu options
- [G] = Clean GRUB boot path (if configured)
- [Enter] = Nuclear Boot demonstration

For real deployment, configure your system's GRUB
with the PhoenixGuard installer scripts.

🦀🔥 PhoenixGuard - Secure Boot-to-VM Defense 🔥🦀
EOF
    
    sudo umount "$mount_point"
    rmdir "$mount_point"
    
    # Sync to ensure writes complete
    sync
    
    log "✅ Bootable USB created successfully!"
    log "🎯 You can now boot this USB on real hardware"
    log "📋 See README.txt on the USB for usage instructions"
}

# Create ISO image
create_iso() {
    local iso_path="$1"
    
    log "💿 Creating bootable ISO: $iso_path"
    
    local temp_dir="/tmp/phoenixguard-iso-$$"
    mkdir -p "$temp_dir"
    
    setup_efi_structure "$temp_dir"
    
    # Create ISO with proper EFI boot
    log "🔄 Building ISO image..."
    if command -v xorriso >/dev/null; then
        xorriso -as mkisofs \
            -V "PHOENIXGUARD" \
            -J -R \
            -e EFI/BOOT/BOOTX64.EFI \
            -no-emul-boot \
            -boot-load-size 4 \
            -boot-info-table \
            -eltorito-alt-boot \
            -efi-boot EFI/BOOT/BOOTX64.EFI \
            -no-emul-boot \
            -isohybrid-gpt-basdat \
            -o "$iso_path" \
            "$temp_dir" >/dev/null 2>&1
    else
        log "❌ xorriso not found. Install with: sudo apt install xorriso"
        rm -rf "$temp_dir"
        exit 1
    fi
    
    rm -rf "$temp_dir"
    
    log "✅ Bootable ISO created: $iso_path"
    log "🔥 You can burn this to CD/DVD or use with virtual machines"
}

# Check system dependencies
check_deps() {
    local missing=()
    
    if ! command -v qemu-system-x86_64 >/dev/null; then
        missing+=("qemu-system-x86_64")
    fi
    
    if [[ ! -f /usr/share/OVMF/OVMF_CODE_4M.fd ]]; then
        missing+=("ovmf")
    fi
    
    if ! command -v mkfs.vfat >/dev/null; then
        missing+=("dosfstools")
    fi
    
    if [[ ! -f NuclearBootEdk2.efi ]]; then
        log "❌ NuclearBootEdk2.efi not found. Build it first with:"
        log "   ./build-nuclear-boot-edk2.sh"
        exit 1
    fi
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log "❌ Missing dependencies: ${missing[*]}"
        log "Install with: sudo apt install ${missing[*]}"
        exit 1
    fi
    
    log "✅ Dependencies check passed"
}

# Show usage
usage() {
    cat <<EOF
PhoenixGuard Nuclear Boot Enhanced Test Script

Usage: $0 <mode> [options]

Modes:
  virtual                    - Test in QEMU (default)
  usb <device>              - Create bootable USB 
  iso <output.iso>          - Create bootable ISO image
  
Examples:
  $0 virtual                         # QEMU test
  $0 usb /dev/sdb                   # Create bootable USB
  $0 iso phoenixguard-boot.iso      # Create ISO image

Hardware Testing:
  1. Create USB: $0 usb /dev/sdX
  2. Boot target machine from USB
  3. Should auto-start Nuclear Boot application

Safety Notes:
  - USB creation DESTROYS all data on target device
  - Only use on spare/test systems for experimentation
  - Real deployment uses PhoenixGuard installer scripts

🦀🔥 PhoenixGuard - Battle-tested UEFI bootloader 🔥🦀

EOF
}

# Main execution
main() {
    log "🦀🔥 PhoenixGuard Nuclear Boot Enhanced Test 🔥🦀"
    
    check_deps
    
    case "${1:-virtual}" in
        virtual|test)
            test_virtual
            ;;
        usb)
            if [[ -z "${2:-}" ]]; then
                log "❌ USB device required"
                log "Usage: $0 usb /dev/sdX"
                log "Available devices:"
                lsblk -d -o NAME,SIZE,MODEL | grep -E "(sd|nvme)"
                exit 1
            fi
            create_usb "$2"
            ;;
        iso)
            if [[ -z "${2:-}" ]]; then
                log "❌ ISO output path required"
                log "Usage: $0 iso output.iso"
                exit 1
            fi
            create_iso "$2"
            ;;
        help|--help|-h)
            usage
            ;;
        *)
            log "❌ Unknown mode: $1"
            usage
            exit 1
            ;;
    esac
}

main "$@"
