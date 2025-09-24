#!/usr/bin/env bash
# Description: Prepares an ESP image that can boot an ISO via GRUB loopback.

set -euo pipefail

ISO_FROM_ARG=$1

if [ -z "${ISO_FROM_ARG}" ] && [ -z "${ISO_PATH:-}" ]; then
    echo "Usage: just iso-prep /path/to.iso (or) ISO_PATH=/path/to.iso just iso-prep"; exit 1
fi

ISO_PATH="${ISO_FROM_ARG:-${ISO_PATH}}" just --justfile Justfile package-esp-iso
just --justfile Justfile valid-esp-secure

echo "✅ ESP prepared at out/esp/esp.img (shim default)"
echo "To boot on real hardware: write the image to a small FAT32 partition on a USB device, set it active, and select it from firmware."

