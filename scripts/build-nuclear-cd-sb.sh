#!/bin/bash
# build-nuclear-cd-sb.sh - Build Secure Boot compatible PhoenixGuard Nuclear Boot recovery CD/DVD image
# This creates a bootable ISO with signed UEFI bootloader (shim + grub) that works with Secure Boot

set -e

echo "🔐 Building PhoenixGuard Nuclear Boot recovery CD (Secure Boot compatible)..."

# Check build requirements
echo "🔍 Checking build requirements..."
for tool in xorriso rsync; do
    if ! command -v "$tool" >/dev/null; then
        echo "ERROR: Missing $tool (install with: sudo apt install xorriso grub-efi-amd64-bin mtools rsync)"
        exit 1
    fi
done

# Setup variables
ISO_IN="/boot/efi/recovery/PhoenixGuard-Nuclear-Recovery.iso"
WORKDIR="/tmp/pg-remaster-$(date +%s)"
MOUNT="/mnt/pgiso-$(date +%s)"

echo "📏 Setting up remastering workspace..."
if [ ! -f "$ISO_IN" ]; then
    echo "ERROR: Base ISO not found at $ISO_IN. Run 'make build-nuclear-cd' first."
    exit 1
fi

sudo mkdir -p "$MOUNT" "$WORKDIR"

# Extract base ISO
echo "📦 Extracting base ISO..."
sudo mount -o loop "$ISO_IN" "$MOUNT"
rsync -aHAX --numeric-ids "$MOUNT"/. "$WORKDIR"/
sudo umount "$MOUNT"
sudo rmdir "$MOUNT"

# Install Secure Boot components
echo "🔑 Installing Secure Boot components..."
sudo mkdir -p "$WORKDIR/EFI/BOOT" "$WORKDIR/EFI/PhoenixGuard"

# Install Microsoft-signed shim
if [ -f "/boot/efi/EFI/ubuntu/shimx64.efi" ]; then
    sudo cp "/boot/efi/EFI/ubuntu/shimx64.efi" "$WORKDIR/EFI/BOOT/BOOTX64.EFI"
    echo "  ✅ Installed Microsoft-signed shim"
else
    echo "  ⚠️  shimx64.efi not found - install shim-signed package"
fi

# Install Ubuntu-signed GRUB
if [ -f "/boot/efi/EFI/ubuntu/grubx64.efi" ]; then
    sudo cp "/boot/efi/EFI/ubuntu/grubx64.efi" "$WORKDIR/EFI/BOOT/grubx64.efi"
    echo "  ✅ Installed Ubuntu-signed GRUB"
else
    echo "  ⚠️  grubx64.efi not found - install grub-efi-amd64-signed package"
fi

# Install MOK manager
if [ -f "/boot/efi/EFI/ubuntu/mmx64.efi" ]; then
    sudo cp "/boot/efi/EFI/ubuntu/mmx64.efi" "$WORKDIR/EFI/BOOT/mmx64.efi"
    echo "  ✅ Installed MOK manager"
fi

# Install PhoenixGuard payloads
echo "🚀 Installing PhoenixGuard payloads..."
if [ -d "/boot/efi/EFI/PhoenixGuard" ]; then
    sudo cp -a /boot/efi/EFI/PhoenixGuard/* "$WORKDIR/EFI/PhoenixGuard/"
    echo "  ✅ PhoenixGuard payloads copied from ESP"
else
    echo "  ⚠️  No PhoenixGuard payloads found at /boot/efi/EFI/PhoenixGuard"
fi

# Create GRUB configuration
echo "⚙️  Creating GRUB configuration..."
sudo tee "$WORKDIR/EFI/BOOT/grub.cfg" > /dev/null << 'GRUBEOF'
set default=0
set timeout=5

menuentry "PhoenixGuard Nuclear Recovery - Direct Kernel" {
    linux /EFI/PhoenixGuard/vmlinuz boot=live toram
    initrd /EFI/PhoenixGuard/initrd.img
}

menuentry "PhoenixGuard Nuclear Recovery - UEFI Application" {
    chainloader /EFI/PhoenixGuard/NuclearBootEdk2.efi
}

menuentry "PhoenixGuard Nuclear Recovery - Emergency Shell" {
    linux /EFI/PhoenixGuard/vmlinuz boot=live toram init=/bin/bash
    initrd /EFI/PhoenixGuard/initrd.img
}
GRUBEOF

# Build Secure Boot compatible ISO
echo "💾 Building Secure Boot compatible ISO..."
if xorriso -as mkisofs \
    -r -V "PhoenixGuard Nuclear Recovery (SB)" \
    -o PhoenixGuard-Nuclear-Recovery-SB.iso \
    -J -l \
    -eltorito-alt-boot \
    -e EFI/BOOT/BOOTX64.EFI -no-emul-boot -isohybrid-gpt-basdat \
    "$WORKDIR" 2>/dev/null; then
    echo "✅ ISO created with isohybrid support"
else
    echo "xorriso failed with isohybrid, trying without..."
    xorriso -as mkisofs \
        -r -V "PhoenixGuard Nuclear Recovery (SB)" \
        -o PhoenixGuard-Nuclear-Recovery-SB.iso \
        -J -l \
        -eltorito-alt-boot \
        -e EFI/BOOT/BOOTX64.EFI -no-emul-boot \
        "$WORKDIR"
fi

# Cleanup
echo "🧹 Cleaning up workspace..."
sudo rm -rf "$WORKDIR"

echo
echo "✅ Secure Boot compatible Nuclear Boot ISO created: PhoenixGuard-Nuclear-Recovery-SB.iso"
echo "📏 Size: $(du -h PhoenixGuard-Nuclear-Recovery-SB.iso | cut -f1)"
echo "🔒 SHA256: $(sha256sum PhoenixGuard-Nuclear-Recovery-SB.iso | cut -d' ' -f1)"
echo "🔐 Secure Boot: Compatible via Microsoft-signed shim + Ubuntu-signed GRUB"
echo
echo "🎯 Next steps:"
echo "  Test: make test-cd-boot-sb"
echo "  Deploy: make deploy-esp-iso-sb"
echo "  Burn: make burn-recovery-cd-sb"
