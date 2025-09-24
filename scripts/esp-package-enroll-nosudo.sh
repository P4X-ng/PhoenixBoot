#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib/common.sh

info "🔐 Packaging enrollment ESP (no sudo, mtools)"
[ -f staging/boot/KeyEnrollEdk2.efi ] || die "Missing KeyEnrollEdk2.efi in staging/boot/"

ensure_dir out/esp
ensure_dir out/securevars
ENROLL_IMG=out/esp/enroll-esp.img
rm -f "$ENROLL_IMG"

dd if=/dev/zero of="$ENROLL_IMG" bs=1M count=16
mkfs.fat -F32 "$ENROLL_IMG"

# Resolve AUTH blobs
PK_AUTH=""; KEK_AUTH=""; DB_AUTH=""
if [ -f out/securevars/PK.auth ] && [ -f out/securevars/KEK.auth ] && [ -f out/securevars/db.auth ]; then
  PK_AUTH=out/securevars/PK.auth
  KEK_AUTH=out/securevars/KEK.auth
  DB_AUTH=out/securevars/db.auth
elif [ -f secureboot_certs/PK.auth ] && [ -f secureboot_certs/KEK.auth ] && [ -f secureboot_certs/db.auth ]; then
  PK_AUTH=secureboot_certs/PK.auth
  KEK_AUTH=secureboot_certs/KEK.auth
  DB_AUTH=secureboot_certs/db.auth
else
  if command -v cert-to-efi-sig-list >/dev/null 2>&1 && command -v sign-efi-sig-list >/dev/null 2>&1; then
    info "Generating AUTH blobs via efitools..."
    just --justfile Justfile make-auth || true
    if [ -f out/securevars/PK.auth ] && [ -f out/securevars/KEK.auth ] && [ -f out/securevars/db.auth ]; then
      PK_AUTH=out/securevars/PK.auth
      KEK_AUTH=out/securevars/KEK.auth
      DB_AUTH=out/securevars/db.auth
    else
      die "Failed to generate AUTH blobs; provide them in secureboot_certs/"
    fi
  else
    die "Missing AUTH blobs and efitools; provide secureboot_certs/{PK,KEK,db}.auth or install efitools"
  fi
fi

# Build directories with mtools
mmd -i "$ENROLL_IMG" ::/EFI || true
mmd -i "$ENROLL_IMG" ::/EFI/BOOT || true
mmd -i "$ENROLL_IMG" ::/EFI/PhoenixGuard || true
mmd -i "$ENROLL_IMG" ::/EFI/PhoenixGuard/keys || true

# Copy files
mcopy -i "$ENROLL_IMG" -o staging/boot/KeyEnrollEdk2.efi ::/EFI/BOOT/BOOTX64.EFI
mcopy -i "$ENROLL_IMG" -o "$PK_AUTH" ::/EFI/PhoenixGuard/keys/pk.auth
mcopy -i "$ENROLL_IMG" -o "$KEK_AUTH" ::/EFI/PhoenixGuard/keys/kek.auth
mcopy -i "$ENROLL_IMG" -o "$DB_AUTH" ::/EFI/PhoenixGuard/keys/db.auth

ok "Enrollment ESP (no sudo) at $ENROLL_IMG"
