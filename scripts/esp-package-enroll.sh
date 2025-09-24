#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib/common.sh

info "🔐 Packaging enrollment ESP (mounting rw)"
[ -f staging/boot/KeyEnrollEdk2.efi ] || die "Missing KeyEnrollEdk2.efi in staging/boot/"

ensure_dir out/esp
unmount_if_mounted out/esp/mount

ENROLL_IMG=out/esp/enroll-esp.img
rm -f "$ENROLL_IMG"
dd if=/dev/zero of="$ENROLL_IMG" bs=1M count=16
mkfs.fat -F32 "$ENROLL_IMG"

ensure_dir out/esp/mount
mount_rw_loop "$ENROLL_IMG" out/esp/mount

sudo mkdir -p out/esp/mount/EFI/BOOT
sudo mkdir -p out/esp/mount/EFI/PhoenixGuard/keys
sudo cp staging/boot/KeyEnrollEdk2.efi out/esp/mount/EFI/BOOT/BOOTX64.EFI

# AUTH blobs
for f in PK KEK db; do
  if [ -f "out/securevars/${f}.auth" ]; then
    sudo cp "out/securevars/${f}.auth" "out/esp/mount/EFI/PhoenixGuard/keys/${f,,}.auth"
  elif [ -f "secureboot_certs/${f}.auth" ]; then
    sudo cp "secureboot_certs/${f}.auth" "out/esp/mount/EFI/PhoenixGuard/keys/${f,,}.auth"
  else
    warn "Missing ${f}.auth; enrollment media may be incomplete"
  fi
done

sudo umount out/esp/mount
rmdir out/esp/mount
ok "Enrollment ESP at $ENROLL_IMG"
