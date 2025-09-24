#!/usr/bin/env bash
set -euo pipefail

# One-command writer for ESP image → USB device (superfloppy).
# Usage:
#   USB_DEVICE=/dev/sdX USB_DEVICE_CONFIRM=I_UNDERSTAND bash scripts/usb-write-dd.sh
# Requires: out/esp/esp.img to exist.

cd "$(dirname "$0")/.."
source scripts/lib/common.sh

IMG=${ESP_IMG:-out/esp/esp.img}
[ -f "$IMG" ] || die "Missing $IMG; run 'just package-esp' or 'just iso-prep' first"

USB_DEVICE=${USB_DEVICE:-${USB1_DEV:-}}
[ -n "${USB_DEVICE}" ] || die "Set USB_DEVICE=/dev/sdX (or USB1_DEV) to the target device"

# Safety confirmation: allow either the long form or a short alias
CONFIRM=${USB_DEVICE_CONFIRM:-${CONFIRM:-}}
if [ "$CONFIRM" = "I_UNDERSTAND" ] || [ "$CONFIRM" = "1" ]; then
  :
else
  die "Set USB_DEVICE_CONFIRM=I_UNDERSTAND or CONFIRM=1 to proceed (this will WIPE ${USB_DEVICE})"
fi

ok "Target: ${USB_DEVICE}"
info "Listing removable devices:"
lsblk -d -o NAME,PATH,MODEL,SIZE,TRAN,RM,ROTA,TYPE | sed -n '1,200p'

# Refuse writing to an obvious root/system disk unless USB_FORCE=1
ROOT_DISK=$(findmnt -no SOURCE / | sed 's/[0-9]*$//' || true)
if [ -n "$ROOT_DISK" ]; then
  case "$USB_DEVICE" in
    "$ROOT_DISK"|${ROOT_DISK}[0-9]*)
      if [ "${USB_FORCE:-0}" != "1" ]; then
        die "Refusing to write to root disk ($ROOT_DISK). Set USB_FORCE=1 to override."
      fi
      warn "USB_FORCE=1 set; overriding root-disk protection"
      ;;
  esac
fi

# Unmount any mounted partitions or superfloppy mounts on the target device
info "Unmounting any existing mounts on ${USB_DEVICE}…"
mapfile -t MPS < <(lsblk -ln -o MOUNTPOINT ${USB_DEVICE} ${USB_DEVICE}* 2>/dev/null | awk 'length') || true
for mp in "${MPS[@]:-}"; do
  warn "umount ${mp}"
  sudo umount "$mp" || sudo umount -l "$mp" || true
done
sudo partprobe "${USB_DEVICE}" 2>/dev/null || true
sleep 1

# Write image
info "Writing ${IMG} → ${USB_DEVICE} (this will wipe the device)"
sudo dd if="$IMG" of="${USB_DEVICE}" bs=4M status=progress oflag=direct,sync conv=fsync
sync
ok "Write complete"

# Verify (best-effort): mount superfloppy and list essentials
MNT=/mnt/pgusb1
sudo mkdir -p "$MNT"
if sudo mount -o ro -t vfat "$USB_DEVICE" "$MNT" 2>/dev/null; then
  ok "Mounted ${USB_DEVICE} at ${MNT} (ro)"
  echo "Top-level:"; sudo ls -la "$MNT" | sed -n '1,200p'
  echo; echo "EFI/BOOT:"; sudo ls -lh "$MNT/EFI/BOOT" || true
  echo; echo "ISO:"; sudo ls -lh "$MNT/ISO" || true
  sudo umount "$MNT" || true
  rmdir "$MNT" 2>/dev/null || true
else
  warn "Could not mount ${USB_DEVICE} as superfloppy; this can be normal on some hosts."
fi

ok "USB write finished — select this USB in firmware boot menu"
