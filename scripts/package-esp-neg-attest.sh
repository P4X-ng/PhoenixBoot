#!/usr/bin/env bash
# Description: Creates a negative attestation ESP by corrupting the sidecar hash.

set -euo pipefail
SRC=out/esp/esp.img
DST=out/esp/esp-neg-attest.img

[ -f "$SRC" ] || { echo "❌ Missing $SRC; run 'just package-esp' first"; exit 1; }
cp "$SRC" "$DST"

# Preflight: clear any previous mount state
if mountpoint -q out/esp/mount 2>/dev/null; then
    echo "🔧 Unmounting previous out/esp/mount"
    sudo umount out/esp/mount || sudo umount -l out/esp/mount || true
fi
rmdir out/esp/mount 2>/dev/null || true
mkdir -p out/esp/mount
sudo mount -o loop,rw "$DST" out/esp/mount

# Overwrite sidecar with wrong digest
sudo bash -c "echo 0000000000000000000000000000000000000000000000000000000000000000 > out/esp/mount/EFI/PhoenixGuard/NuclearBootEdk2.sha256"

sudo umount out/esp/mount
rmdir out/esp/mount
sha256sum "$DST" > "$DST.sha256"

echo "✅ Negative attestation ESP at $DST"

