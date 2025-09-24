#!/usr/bin/env bash
set -euo pipefail

# Stage a clean GRUB (or shim+grub) and a minimal grub.cfg on the ESP for Clean GRUB Boot.
# Usage:
#   sudo ./scripts/install_clean_grub_boot.sh --esp /boot/efi \
#     [--shim /usr/lib/shim/shimx64.efi.signed] \
#     --grub-efi /usr/lib/grub/x86_64-efi/grubx64.efi \
#     --root-uuid <UUID> [--vmlinuz /boot/vmlinuz-<ver>] [--initrd /boot/initrd.img-<ver>]
# Notes:
# - On Secure Boot, prefer shimx64.efi.signed; grubx64.efi must be trusted (MOK/vendor key).
# - If you don’t provide vmlinuz/initrd, the grub.cfg entry can boot the installed OS by UUID.

ESP=
SHIM=
GRUB_EFI=
ROOT_UUID=
VMLINUZ=
INITRD=

while [[ $# -gt 0 ]]; do
  case "$1" in
    --esp) ESP="$2"; shift 2;;
    --shim) SHIM="$2"; shift 2;;
    --grub-efi) GRUB_EFI="$2"; shift 2;;
    --root-uuid) ROOT_UUID="$2"; shift 2;;
    --vmlinuz) VMLINUZ="$2"; shift 2;;
    --initrd) INITRD="$2"; shift 2;;
    *) echo "Unknown arg: $1"; exit 1;;
  esac
done

if [[ -z "$ESP" || -z "$ROOT_UUID" ]]; then
  echo "Required: --esp /boot/efi and --root-uuid <UUID>"
  exit 1
fi

mkdir -p "$ESP/EFI/PhoenixGuard"

# Copy shim/grub
if [[ -n "$SHIM" ]]; then
  cp "$SHIM" "$ESP/EFI/PhoenixGuard/shimx64.efi"
fi
if [[ -n "$GRUB_EFI" ]]; then
  cp "$GRUB_EFI" "$ESP/EFI/PhoenixGuard/grubx64.efi"
else
  # If not provided, attempt a common default path
  if [[ -f /usr/lib/grub/x86_64-efi/grubx64.efi ]]; then
    cp /usr/lib/grub/x86_64-efi/grubx64.efi "$ESP/EFI/PhoenixGuard/grubx64.efi"
  fi
fi

# Optionally copy kernel/initrd to ESP
if [[ -n "$VMLINUZ" ]]; then cp "$VMLINUZ" "$ESP/EFI/PhoenixGuard/vmlinuz"; fi
if [[ -n "$INITRD" ]]; then cp "$INITRD" "$ESP/EFI/PhoenixGuard/initrd.img"; fi

# Write grub.cfg
CFG_DIR="$ESP/EFI/PhoenixGuard"
CFG_TMP=$(mktemp)
sed "s/<ROOT-UUID>/$ROOT_UUID/g" \
  resources/grub/esp/EFI/PhoenixGuard/grub.cfg \
  > "$CFG_TMP"
mv "$CFG_TMP" "$CFG_DIR/grub.cfg"

echo "Installed Clean GRUB Boot assets to $ESP/EFI/PhoenixGuard"
echo "Add a firmware boot entry to shimx64.efi (if present) or grubx64.efi, or use NuclearBoot’s Clean GRUB Boot option."

