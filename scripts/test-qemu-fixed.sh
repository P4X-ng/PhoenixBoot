#!/usr/bin/env bash
set -euo pipefail

# Use minimal ESP, not the bloated one
ESP_IMG="${1:-out/esp/esp.img}"

if [ ! -f "$ESP_IMG" ]; then
    echo "❌ ESP image not found: $ESP_IMG"
    echo "Run: just build package-esp"
    exit 1
fi

# Find OVMF
OVMF_CODE=""
for path in \
    "/usr/share/OVMF/OVMF_CODE_4M.secboot.fd" \
    "/usr/share/OVMF/OVMF_CODE.secboot.fd" \
    "/usr/share/OVMF/OVMF_CODE.fd"; do
    [ -f "$path" ] && OVMF_CODE="$path" && break
done

if [ -z "$OVMF_CODE" ]; then
    echo "❌ OVMF not found!"
    exit 1
fi

# Create vars template
OVMF_VARS="/tmp/OVMF_VARS_$$.fd"
cp "${OVMF_CODE/CODE/VARS}" "$OVMF_VARS" 2>/dev/null || \
cp "/usr/share/OVMF/OVMF_VARS.fd" "$OVMF_VARS"

echo "🚀 Launching QEMU with fixed configuration..."
echo "   ESP: $ESP_IMG ($(du -h $ESP_IMG | cut -f1))"
echo "   OVMF: $OVMF_CODE"

qemu-system-x86_64 \
    -machine q35,smm=on,accel=kvm \
    -cpu host \
    -m 2048 \
    -drive if=pflash,format=raw,unit=0,file="$OVMF_CODE",readonly=on \
    -drive if=pflash,format=raw,unit=1,file="$OVMF_VARS" \
    -drive format=raw,file="$ESP_IMG" \
    -display gtk \
    -serial stdio

rm -f "$OVMF_VARS"
