#!/usr/bin/env bash
# Description: Validates the contents of the ESP image.

set -euo pipefail

IMG=out/esp/esp.img
[ -f "$IMG" ] || { echo "❌ Missing $IMG; run 'just package-esp' or 'just package-esp-nosudo' first"; exit 1; }
FAIL=0

echo "🔎 Listing ESP root:"
mdir -i "$IMG" ::/ || true
echo "🔎 Listing EFI/BOOT:"
mdir -i "$IMG" ::/EFI/BOOT || true
echo "🔎 Listing EFI/PhoenixGuard:"
mdir -i "$IMG" ::/EFI/PhoenixGuard || true

for f in "/EFI/BOOT/BOOTX64.EFI" "/EFI/PhoenixGuard/NuclearBootEdk2.sha256"; do
    if mtype -i "$IMG" ::$f >/dev/null 2>&1; then
        echo "✅ Present: $f"
    else
        echo "❌ Missing: $f"
        FAIL=1
    fi
done

exit $FAIL

