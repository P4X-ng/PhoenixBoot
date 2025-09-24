#!/usr/bin/env bash
# Description: Sanitizes a USB drive by removing stray vendor trees and .pfs files.

set -euo pipefail

[ -n "${USB1_DEV:-}" ] || { echo "❌ USB1_DEV=/dev/sdX is required"; exit 1; }

if [ "${USB_FORCE:-0}" != "1" ]; then
    echo "ℹ️  Dry-run. Set USB_FORCE=1 to perform changes."
fi

PART=$(lsblk -ln -o NAME,FSTYPE,LABEL,PATH "${USB1_DEV}" | awk '$2~/(vfat|fat32)/ || tolower($3) ~ /efi/ {print $4; exit}')
[ -n "${PART:-}" ] || { echo "❌ Could not find FAT32/EFI partition on ${USB1_DEV}"; exit 1; }

MNT=$(mktemp -d)
sudo mount "${PART}" "${MNT}"
trap 'sudo umount "${MNT}"; rmdir "${MNT}"' EXIT

echo "🔧 Sanitizing ${PART} mounted at ${MNT}"
find "${MNT}" -maxdepth 2 -type f -name '*.pfs' -print

if [ "${USB_FORCE:-0}" = "1" ]; then
    find "${MNT}" -maxdepth 2 -type f -name '*.pfs' -delete || true
    # Remove EFI/ubuntu if present to avoid confusion
    sudo rm -rf "${MNT}/EFI/ubuntu" 2>/dev/null || true
fi

echo "✅ USB sanitize complete"

