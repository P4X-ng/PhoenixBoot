#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib/common.sh

IMG=out/esp/esp.img
[ -f "$IMG" ] || die "Missing $IMG; run 'just package-esp' first"

FAIL=0
info "🔎 Verifying ESP essentials..."
for f in "/EFI/BOOT/BOOTX64.EFI" "/EFI/PhoenixGuard/NuclearBootEdk2.sha256" "/EFI/BOOT/grub.cfg"; do
  if mtype -i "$IMG" ::$f >/dev/null 2>&1; then
    ok "Present: $f"
  else
    err "Missing: $f"; FAIL=1
  fi
done

if [ -n "${ISO_PATH:-}" ] && [ -f "${ISO_PATH}" ]; then
  ISO_BASENAME=$(basename "${ISO_PATH}")
  if mtype -i "$IMG" ::/ISO/${ISO_BASENAME} >/dev/null 2>&1; then
    ok "ISO present: /ISO/${ISO_BASENAME}"
  else
    err "ISO missing in ESP: /ISO/${ISO_BASENAME}"; FAIL=1
  fi
fi
exit $FAIL

