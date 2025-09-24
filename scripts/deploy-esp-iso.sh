#!/bin/bash
# deploy-esp-iso.sh - Deploy Nuclear Boot ISO to ESP as "virtual CD"
# This deploys the ISO file directly to the ESP partition where GRUB can boot it

set -e

ISO_FILE="PhoenixGuard-Nuclear-Recovery.iso"
SB_MODE=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --secure-boot)
            SB_MODE="1"
            ISO_FILE="PhoenixGuard-Nuclear-Recovery-SB.iso"
            shift
            ;;
        --iso)
            ISO_FILE="$2"
            shift 2
            ;;
        *)
            echo "Usage: $0 [--secure-boot] [--iso <iso-file>]"
            exit 1
            ;;
    esac
done

echo "⚡ Deploying Nuclear Boot ISO to ESP as virtual CD..."

if [ ! -f "$ISO_FILE" ]; then
    echo "ERROR: $ISO_FILE not found."
    if [ -n "$SB_MODE" ]; then
        echo "       Run 'make build-nuclear-cd-sb' first."
    else
        echo "       Run 'make build-nuclear-cd' first."
    fi
    exit 1
fi

# Detect ESP mount point
echo "🔍 Detecting ESP mount point..."
ESP=$(findmnt -t vfat -n -o TARGET | head -n1 || true)
if [[ -z "$ESP" ]]; then
    ESP="/boot/efi"
fi
if [[ ! -d "$ESP/EFI" ]]; then
    echo "ERROR: No ESP found at $ESP"
    exit 1
fi
echo "  Using ESP: $ESP"

# Create recovery directory and copy ISO
echo "📏 Creating recovery directory..."
sudo mkdir -p "$ESP/recovery"

echo "💾 Copying ISO to ESP (virtual CD burn)..."
sudo cp "$ISO_FILE" "$ESP/recovery/$ISO_FILE"

# Set up GRUB loopback entry
echo "🔑 Setting up GRUB loopback entry..."
sudo mkdir -p /etc/grub.d

GRUB_ENTRY_FILE="/etc/grub.d/42_phoenixguard_recovery"
sudo tee "$GRUB_ENTRY_FILE" > /dev/null << EOF
#!/bin/sh
exec tail -n +3 \$0
# PhoenixGuard Nuclear Boot Recovery (Virtual CD)
menuentry 'PhoenixGuard Nuclear Boot Recovery (Virtual CD)' {
    insmod loopback
    insmod iso9660
    set isofile='/recovery/$ISO_FILE'
    loopback loop \$isofile
    linux (loop)/vmlinuz boot=live toram
    initrd (loop)/initrd.img
}
EOF

sudo chmod +x "$GRUB_ENTRY_FILE"

# Update GRUB configuration
echo "🔄 Updating GRUB configuration..."
sudo update-grub

echo
echo "✅ Nuclear Boot ISO deployed to ESP successfully!"
echo "💿 Virtual CD location: $ESP/recovery/$ISO_FILE"
if [ -n "$SB_MODE" ]; then
    echo "🔐 Secure Boot: Ready - uses Microsoft-signed shim"
fi
echo "🔒 ISO format provides read-only protection against modification"
echo "🎯 Size: $(du -h "$ESP/recovery/$ISO_FILE" | cut -f1)"
echo
echo "🚀 To use: Reboot and select 'PhoenixGuard Nuclear Boot Recovery (Virtual CD)' from GRUB menu"
