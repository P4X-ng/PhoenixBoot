#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib/common.sh

info "📦 Creating MINIMAL bootable ESP image (no ISOs)..."
require_cmd dd
require_cmd mkfs.fat

ensure_dir out/esp
unmount_if_mounted out/esp/mount
detach_loops_for_image out/esp/esp.img

[ -f out/staging/BootX64.efi ] || die "No BootX64.efi found - run 'just build' first"

# FIXED: Use reasonable 128MB size for ESP (not 3.8GB!)
ESP_MB=128
info "Creating $ESP_MB MB ESP (minimal, no ISOs)"

# Create image and filesystem
rm -f out/esp/esp.img
dd if=/dev/zero of=out/esp/esp.img bs=1M count=${ESP_MB} status=none
mkfs.fat -F32 -n PHOENIX out/esp/esp.img

# Mount and populate
ensure_dir out/esp/mount
mount_rw_loop out/esp/esp.img out/esp/mount

# Create proper directory structure
sudo mkdir -p out/esp/mount/EFI/BOOT
sudo mkdir -p out/esp/mount/EFI/PhoenixGuard
sudo mkdir -p out/esp/mount/recovery

# Copy main bootloader
if [ -f out/staging/BootX64.efi ]; then
    sudo cp out/staging/BootX64.efi out/esp/mount/EFI/BOOT/BOOTX64.EFI
    sudo cp out/staging/BootX64.efi out/esp/mount/EFI/PhoenixGuard/BootX64.efi
fi

# Copy KeyEnroll if available
[ -f out/staging/KeyEnrollEdk2.efi ] && sudo cp out/staging/KeyEnrollEdk2.efi out/esp/mount/EFI/BOOT/

# Copy recovery kernel/initrd if available (but NOT ISOs)
if [ -f out/recovery/vmlinuz ]; then
    sudo cp out/recovery/vmlinuz out/esp/mount/recovery/
    [ -f out/recovery/initrd.img ] && sudo cp out/recovery/initrd.img out/esp/mount/recovery/
fi

# Generate UUID
BUILD_UUID=$(uuidgen)
echo "$BUILD_UUID" | sudo tee out/esp/mount/EFI/PhoenixGuard/BUILD_UUID.txt > /dev/null

# Unmount
sudo umount out/esp/mount
rmdir out/esp/mount

ok "✅ Minimal ESP created: out/esp/esp.img (${ESP_MB}MB)"
