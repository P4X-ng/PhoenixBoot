#!/bin/bash
# reboot-to-metal.sh - Reboot back to Normal Metal Operation
# This restores the original bootloader, cleans up ESP staging, and reboots

set -e

echo "🔄 Restoring system to normal boot operation..."
echo "The system will reboot automatically in 5 seconds. Press Ctrl+C to cancel."
sleep 5 || exit 0

echo "🧹 Cleaning up PhoenixGuard recovery environment..."

# Remove PhoenixGuard boot entries
echo "[uefi] Removing PhoenixGuard boot entries"
BOOTNUMS=$(efibootmgr | awk -F'*' '/PhoenixGuard/{print $1}' | sed 's/Boot//;s/\s*$//')
for num in $BOOTNUMS; do
    if [[ -n "$num" ]]; then
        sudo efibootmgr -b "$num" -B >/dev/null || true
    fi
done

# Clean up ESP staging
echo "[esp] Cleaning up ESP staging"
ESP=$(findmnt -t vfat -n -o TARGET | head -n1 || true)
if [[ -z "$ESP" ]]; then
    ESP="/boot/efi"
fi

if [[ -d "$ESP/EFI/PhoenixGuard" ]]; then
    sudo rm -rf "$ESP/EFI/PhoenixGuard" || true
fi
if [[ -f "$ESP/EFI/xen.efi" ]]; then
    sudo rm -f "$ESP/EFI/xen.efi" || true
fi
if [[ -f "$ESP/EFI/xen.cfg" ]]; then
    sudo rm -f "$ESP/EFI/xen.cfg" || true
fi

# Remove KVM recovery configuration
echo "[cleanup] Removing KVM recovery configuration"
sudo rm -f /etc/phoenixguard/kvm-snapshot.conf || true
sudo systemctl disable kvm-snapshot-jump.service >/dev/null 2>&1 || true
sudo systemctl disable pg-remediate.service >/dev/null 2>&1 || true

# Remove GRUB recovery entries
echo "[grub] Removing GRUB recovery entries"
sudo rm -f /etc/grub.d/42_phoenixguard_recovery || true
sudo update-grub >/dev/null 2>&1 || true

echo "✅ Removed: PhoenixGuard UEFI boot entries"
echo "✅ Cleaned: ESP staging at $ESP/EFI/PhoenixGuard/"
echo "✅ Disabled: KVM recovery services"
echo
echo "🎯 System ready to reboot to normal operation"
echo "   Your original bootloader should now be restored"

sudo reboot
