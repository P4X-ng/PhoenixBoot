#!/usr/bin/env bash
# Description: Creates a negative attestation ESP without sudo by overwriting the hash via mtools.

set -euo pipefail
SRC=out/esp/esp.img
DST=out/esp/esp-neg-attest.img

[ -f "$SRC" ] || { echo "❌ Missing $SRC; run 'just package-esp' or 'just package-esp-nosudo' first"; exit 1; }
cp "$SRC" "$DST"

NEG_SHA=out/esp/neg-attest.sha
printf '%s\n' "0000000000000000000000000000000000000000000000000000000000000000" > "$NEG_SHA"
mcopy -i "$DST" -o "$NEG_SHA" ::/EFI/PhoenixGuard/NuclearBootEdk2.sha256
rm -f "$NEG_SHA"
sha256sum "$DST" > "$DST.sha256"

echo "✅ Negative attestation ESP (no sudo) at $DST"

