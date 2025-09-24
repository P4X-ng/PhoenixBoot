#!/usr/bin/env bash
# Description: Installs UUEFI and sets it as the one-time boot entry.

set -euo pipefail

ENV_FILE=out/uuefi/efiboot.env
if [ ! -f "$ENV_FILE" ]; then
  echo "❌ Missing $ENV_FILE; run 'just uuefi-install' first"; exit 1
fi

source "$ENV_FILE"
if [ -z "${EFI_DISK:-}" ] || [ -z "${EFI_PART:-}" ]; then
  echo "❌ Could not auto-detect EFI_DISK/EFI_PART; please set them explicitly"
  exit 1
fi

APP=UUEFI EFI_DISK="$EFI_DISK" EFI_PART="$EFI_PART" bash scripts/uuefi-apply.sh

echo "[OK] UUEFI one-shot BootNext set; reboot to test"

