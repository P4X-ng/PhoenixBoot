#!/bin/bash
# boot-from-esp-iso.sh - Boot Nuclear Recovery from ESP-deployed ISO immediately
# This script provides immediate access to the recovery environment without rebooting

set -e

echo "🚀 PhoenixGuard Nuclear Boot Recovery - Immediate Access"
echo "========================================================"

# Check if we're already in the recovery environment
if [ -f "/recovery_environment" ] || [ -f "/live/recovery_environment" ]; then
    echo "✅ Already in PhoenixGuard recovery environment!"
    echo "🎯 Recovery tools available:"
    echo "   • bootkit-scan         - Comprehensive bootkit detection"
    echo "   • flashrom             - Hardware firmware access"
    echo "   • chipsec              - Intel security analysis"
    echo "   • radare2, binwalk     - Reverse engineering tools"
    echo "   • python3              - Custom security scripts"
    echo
    echo "📋 For bootkit analysis: bootkit-scan -v"
    exit 0
fi

# Detect ESP mount point
echo "🔍 Detecting ESP and recovery ISO..."
ESP=$(findmnt -t vfat -n -o TARGET | head -n1 || true)
if [[ -z "$ESP" ]]; then
    ESP="/boot/efi"
fi

if [[ ! -d "$ESP/EFI" ]]; then
    echo "❌ No ESP found at $ESP"
    exit 1
fi

# Look for deployed ISOs
ISO_FILE=""
if [[ -f "$ESP/recovery/PhoenixGuard-Nuclear-Recovery-SB.iso" ]]; then
    ISO_FILE="$ESP/recovery/PhoenixGuard-Nuclear-Recovery-SB.iso"
    echo "📀 Found Secure Boot recovery ISO"
elif [[ -f "$ESP/recovery/PhoenixGuard-Nuclear-Recovery.iso" ]]; then
    ISO_FILE="$ESP/recovery/PhoenixGuard-Nuclear-Recovery.iso"
    echo "📀 Found standard recovery ISO"
else
    echo "❌ No PhoenixGuard recovery ISO found in ESP!"
    echo "   Deploy first with: sudo make deploy-esp-iso"
    exit 1
fi

echo "   ISO: $ISO_FILE"
echo "   Size: $(du -h "$ISO_FILE" | cut -f1)"

# Create temporary mount point
TEMP_MOUNT="/tmp/phoenixguard_recovery_mount"
sudo mkdir -p "$TEMP_MOUNT"

echo
echo "🔧 Mounting recovery ISO..."
sudo mount -o loop,ro "$ISO_FILE" "$TEMP_MOUNT"

# Check if it's a live ISO with squashfs
if [[ -f "$TEMP_MOUNT/live/filesystem.squashfs" ]]; then
    echo "✅ Live ISO detected - extracting recovery environment..."
    SQUASH_MOUNT="/tmp/phoenixguard_squash_mount"
    sudo mkdir -p "$SQUASH_MOUNT"
    sudo mount -o loop,ro "$TEMP_MOUNT/live/filesystem.squashfs" "$SQUASH_MOUNT"
    
    echo "🚀 Entering PhoenixGuard recovery environment..."
    echo "   Root filesystem: $SQUASH_MOUNT"
    echo "   Network access: Available"
    echo "   Hardware access: Full"
    echo
    echo "🎯 Recovery tools available:"
    echo "   • bootkit-scan: $SQUASH_MOUNT/usr/local/bin/bootkit-scan"
    echo "   • flashrom: $SQUASH_MOUNT/usr/bin/flashrom" 
    echo "   • chipsec: $SQUASH_MOUNT/usr/local/bin/chipsec"
    echo "   • Analysis tools: radare2, binwalk, hexdump"
    echo
    echo "💡 To run recovery shell: sudo chroot $SQUASH_MOUNT /bin/bash"
    echo "💡 To run bootkit scan: sudo chroot $SQUASH_MOUNT bootkit-scan -v"
    echo
    
    # Offer to run common recovery tasks
    echo "🛠️  Quick recovery options:"
    echo "  [1] Run comprehensive bootkit scan"
    echo "  [2] Enter recovery shell (chroot)"
    echo "  [3] Mount host filesystem for repair"
    echo "  [4] Unmount and exit"
    echo
    
    read -p "Select option [1-4]: " choice
    case $choice in
        1)
            echo "🔍 Running comprehensive bootkit scan..."
            sudo chroot "$SQUASH_MOUNT" /bin/bash -c "bootkit-scan -v --output /tmp/host_bootkit_scan.json" || true
            if [[ -f "/tmp/host_bootkit_scan.json" ]]; then
                sudo cp "/tmp/host_bootkit_scan.json" "./bootkit_scan_results.json"
                echo "✅ Scan results saved to ./bootkit_scan_results.json"
            fi
            ;;
        2)
            echo "🚪 Entering PhoenixGuard recovery shell..."
            echo "   Type 'exit' to return to host system"
            sudo chroot "$SQUASH_MOUNT" /bin/bash || true
            ;;
        3)
            echo "💾 Mounting host filesystem for repair..."
            sudo mkdir -p "$SQUASH_MOUNT/host"
            sudo mount --bind / "$SQUASH_MOUNT/host"
            echo "✅ Host filesystem available at /host inside recovery environment"
            echo "🚪 Entering recovery shell with host access..."
            sudo chroot "$SQUASH_MOUNT" /bin/bash || true
            sudo umount "$SQUASH_MOUNT/host" || true
            ;;
        4|*)
            echo "👋 Exiting recovery environment..."
            ;;
    esac
    
    # Cleanup
    sudo umount "$SQUASH_MOUNT" 2>/dev/null || true
    sudo rmdir "$SQUASH_MOUNT" 2>/dev/null || true
    
elif [[ -f "$TEMP_MOUNT/vmlinuz" && -f "$TEMP_MOUNT/initrd.img" ]]; then
    echo "🔧 Standard bootable ISO detected"
    echo "⚠️  This ISO requires a reboot to use effectively."
    echo "   The kernel and initrd are:"
    echo "   • Kernel: $TEMP_MOUNT/vmlinuz"
    echo "   • Initrd: $TEMP_MOUNT/initrd.img"
    echo
    echo "🎯 For immediate use, reboot and select:"
    echo "   'PhoenixGuard Nuclear Boot Recovery (Virtual CD)' from GRUB menu"
    
else
    echo "❓ Unknown ISO format - listing contents:"
    ls -la "$TEMP_MOUNT"
fi

# Cleanup
echo
echo "🧹 Cleaning up mounts..."
sudo umount "$TEMP_MOUNT" 2>/dev/null || true
sudo rmdir "$TEMP_MOUNT" 2>/dev/null || true

echo "✅ Recovery environment access completed"
