#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib/common.sh

IMG=out/esp/esp.img
[ -f "$IMG" ] || die "Missing $IMG; run 'just package-esp' first"

ensure_dir out/esp/mount
mount_rw_loop "$IMG" out/esp/mount

[ -f out/esp/mount/EFI/PhoenixGuard/BootX64.efi ] || { sudo umount out/esp/mount; rmdir out/esp/mount; die "ESP missing PhoenixGuard BootX64.efi"; }
BOOT_SHA=$(sudo sha256sum out/esp/mount/EFI/PhoenixGuard/BootX64.efi | awk '{print $1}')
: > out/esp/Allowed.manifest.sha256
printf "%s  EFI/PhoenixGuard/BootX64.efi\n" "$BOOT_SHA" >> out/esp/Allowed.manifest.sha256

if [ -n "${ISO_PATH:-}" ] && [ -f "${ISO_PATH}" ]; then
  ISO_BASENAME=$(basename "${ISO_PATH}")
  ISO_SHA=$(sha256sum "${ISO_PATH}" | awk '{print $1}')
  printf "%s  ISO/%s\n" "$ISO_SHA" "$ISO_BASENAME" >> out/esp/Allowed.manifest.sha256
fi

sudo install -D -m0644 out/esp/Allowed.manifest.sha256 out/esp/mount/EFI/PhoenixGuard/Allowed.manifest.sha256
sudo umount out/esp/mount
rmdir out/esp/mount
ok "Added Allowed.manifest.sha256 to ESP"

