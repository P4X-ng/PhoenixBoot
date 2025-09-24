#!/bin/bash
# reboot-to-vm.sh - Reboot into PhoenixGuard Recovery VM Environment
# This is the "nuclear option" - stages PhoenixGuard, configures UEFI boot, and reboots

set -e

echo "🚨 WARNING: This will REBOOT your system into PhoenixGuard recovery mode!"
echo "The system will reboot automatically in 10 seconds. Press Ctrl+C to cancel."
sleep 10 || exit 0

echo "🔧 Initiating PhoenixGuard Recovery VM staging..."

# Run bootkit detection scan first
echo "🎯 Running bootkit detection scan first..."
if [ -f firmware_baseline.json ]; then
    python3 scripts/detect_bootkit.py --output bootkit_scan_prereboot.json || echo "⚠️  Bootkit scan failed, continuing..."
else
    echo "⚠️  No firmware baseline found - creating from clean BIOS..."
    if [ -f drivers/G615LPAS.325 ]; then
        python3 scripts/analyze_firmware_baseline.py drivers/G615LPAS.325 -o firmware_baseline.json || echo "⚠️  Baseline creation failed"
        python3 scripts/detect_bootkit.py --output bootkit_scan_prereboot.json || echo "⚠️  Bootkit scan failed"
    else
        echo "⚠️  Clean BIOS dump not found at drivers/G615LPAS.325"
    fi
fi

# Create backup timestamp
TS=$(date +%F_%H%M%S)
echo "[backup] Current UEFI boot configuration"
sudo mkdir -p /var/lib/phoenixguard/backups
sudo efibootmgr -v | sudo tee "/var/lib/phoenixguard/backups/efibootmgr-backup-$TS.txt" >/dev/null

# Detect ESP
echo "[esp] Detecting ESP mount point"
ESP=$(findmnt -t vfat -n -o TARGET | head -n1 || true)
if [[ -z "$ESP" ]]; then
    ESP="/boot/efi"
fi
if [[ ! -d "$ESP/EFI" ]]; then
    echo "ERROR: No ESP found at $ESP"
    exit 1
fi
echo "  Using ESP: $ESP"

# Stage PhoenixGuard
echo "[stage] PhoenixGuard NuclearBootEdk2.efi to ESP"
sudo mkdir -p "$ESP/EFI/PhoenixGuard"
if [[ -f NuclearBootEdk2.efi ]]; then
    sudo cp NuclearBootEdk2.efi "$ESP/EFI/PhoenixGuard/NuclearBootEdk2.efi"
else
    echo "ERROR: NuclearBootEdk2.efi not found. Run 'make build' first."
    exit 1
fi

# Stage KVM recovery environment
echo "[stage] KVM recovery environment"
VMLINUZ="/boot/vmlinuz-$(uname -r)"
INITRD="/boot/initrd.img-$(uname -r)"
ROOT_UUID=$(findmnt -n -o UUID / || true)
QCOW2="$(pwd)/ubuntu-24.04-minimal-cloudimg-amd64.qcow2"

if [[ ! -f "$QCOW2" ]]; then
    echo "ERROR: Recovery image not found: $QCOW2"
    exit 1
fi

# Install KVM snapshot jump configuration
echo "[kvm] Installing KVM snapshot jump configuration"
./scripts/install_kvm_snapshot_jump.sh \
    --esp "$ESP" --vmlinuz "$VMLINUZ" --initrd "$INITRD" --root-uuid "$ROOT_UUID" \
    --qcow2 "$QCOW2" --loadvm base-snapshot \
    --gpu-bdf 0000:02:00.0 --gpu-ids 10de:2d58 || echo "⚠️  KVM config failed, continuing..."

# Configure UEFI boot entry
echo "[uefi] Configuring UEFI boot entry for PhoenixGuard"
ESP_DEV=$(findmnt -n -o SOURCE "$ESP" || true)
DISK=$(lsblk -no PKNAME "$ESP_DEV" 2>/dev/null | head -n1)
PARTNUM=$(lsblk -no PARTNUM "$ESP_DEV" 2>/dev/null | head -n1)

# Remove existing PhoenixGuard boot entries
BOOTNUM=$(efibootmgr | awk -F'*' '/PhoenixGuard/{print $1}' | sed 's/Boot//;s/\s*$//' | head -n1)
if [[ -n "$BOOTNUM" ]]; then
    sudo efibootmgr -b "$BOOTNUM" -B || true
fi

# Create new boot entry
sudo efibootmgr -c -d "/dev/$DISK" -p "$PARTNUM" -L "PhoenixGuard Recovery" -l "\\EFI\\PhoenixGuard\\NuclearBootEdk2.efi" >/dev/null

# Set as next boot
NEWNUM=$(efibootmgr | awk -F'*' '/PhoenixGuard Recovery/{print $1}' | sed 's/Boot//;s/\s*$//' | head -n1)
if [[ -n "$NEWNUM" ]]; then
    sudo efibootmgr -n "$NEWNUM" >/dev/null
fi

echo "[reboot] System will reboot to PhoenixGuard recovery in 5 seconds..."
echo "✅ Staged: ESP at $ESP/EFI/PhoenixGuard/"
echo "✅ Configured: UEFI boot entry $NEWNUM (set as BootNext)"
echo "✅ Recovery VM: $QCOW2 ready to launch"
echo
echo "🎯 After reboot:"
echo "  1. PhoenixGuard menu will appear"
echo "  2. Select 'KVM Snapshot Jump' to launch recovery VM"
echo "  3. Use recovery VM to fix infected bootloaders safely"
echo "  4. Run 'make reboot-to-metal' when done to return to normal boot"

sleep 5
sudo reboot
