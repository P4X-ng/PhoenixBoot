#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib/common.sh

: "${USB1_DEV:?USB1_DEV is required, e.g. /dev/sdX}"
IMG=out/esp/esp.img
[ -f "$IMG" ] || die "Missing $IMG; run 'just package-esp' first"

# Logging
LOG_DIR=out/logs
ensure_dir "$LOG_DIR"
LOG_FILE="$LOG_DIR/usb-prepare.log"
exec > >(tee -a "$LOG_FILE") 2>&1
[ "${PG_DEBUG:-0}" = "1" ] && set -x || true

info "📀 Preparing secure USB on ${USB1_DEV} (partition ${USB1_DEV}1)"

# Cleanup function to avoid stuck mounts
cleanup() {
  for m in /mnt/esploop /mnt/pgusb1; do
    if mountpoint -q "$m" 2>/dev/null; then
      sudo umount "$m" || sudo umount -l "$m" || true
    fi
  done
  rmdir /mnt/esploop /mnt/pgusb1 2>/dev/null || true
}
trap cleanup EXIT

# Ensure mount points are clean
sudo mkdir -p /mnt/pgusb1 /mnt/esploop
if mountpoint -q /mnt/esploop; then sudo umount /mnt/esploop || sudo umount -l /mnt/esploop || true; fi
if mountpoint -q /mnt/pgusb1; then sudo umount /mnt/pgusb1 || sudo umount -l /mnt/pgusb1 || true; fi

# Mount image and USB
sudo mount -o loop,ro "$IMG" /mnt/esploop
sudo mount "${USB1_DEV}1" /mnt/pgusb1

# Ensure PhoenixGuard/BootX64.efi present on USB
sudo mkdir -p /mnt/pgusb1/EFI/PhoenixGuard
if [ ! -f /mnt/pgusb1/EFI/PhoenixGuard/BootX64.efi ]; then
  if [ -f /mnt/esploop/EFI/PhoenixGuard/BootX64.efi ]; then
    sudo install -D -m0644 /mnt/esploop/EFI/PhoenixGuard/BootX64.efi /mnt/pgusb1/EFI/PhoenixGuard/BootX64.efi
  elif [ -f /mnt/esploop/EFI/BOOT/BOOTX64.EFI ]; then
    sudo install -D -m0644 /mnt/esploop/EFI/BOOT/BOOTX64.EFI /mnt/pgusb1/EFI/PhoenixGuard/BootX64.efi
  else
    die "Could not find BootX64.efi in ESP image"
  fi
fi

# Optional ISO copy with progress
copy_with_progress() {
  local src="$1" dst="$2"
  if command -v rsync >/dev/null 2>&1; then
    rsync --info=progress2 "$src" "$dst"
  elif command -v pv >/dev/null 2>&1; then
    pv "$src" | sudo tee "$dst" >/dev/null
  else
    # Fallback: no progress, but still copy
    sudo install -D -m0644 "$src" "$dst"
  fi
}

if [ -n "${ISO_PATH:-}" ] && [ -f "${ISO_PATH}" ]; then
  ISO_BASENAME=$(basename "${ISO_PATH}")
  sudo mkdir -p /mnt/pgusb1/ISO
  if [ ! -f "/mnt/pgusb1/ISO/${ISO_BASENAME}" ]; then
    info "Copying ISO to USB with progress: ${ISO_BASENAME}"
    copy_with_progress "${ISO_PATH}" "/mnt/pgusb1/ISO/${ISO_BASENAME}"
  else
    info "ISO already present on USB: ${ISO_BASENAME}"
  fi
fi

# Unmount prior mounts before organizing to avoid double-mount errors
cleanup

# Continue to organization (script will mount as needed)
bash scripts/organize-usb1.sh

ok "Secure USB prepared on ${USB1_DEV}"

