#!/usr/bin/env bash
set -euo pipefail

# Install PhoenixGuard Xen Snapshot Jump + recovery artifacts using flat EFI layout
# Places files at:
#   $ESP/EFI/xen.efi
#   $ESP/EFI/xen.cfg
#   $ESP/EFI/dom0-vmlinuz
#   $ESP/EFI/dom0-init.img
#   $ESP/EFI/PhoenixGuard/recovery/recovery.pkg (and optional recovery.sig)
#
# Usage (Ubuntu/Debian-like):
#   sudo ./scripts/install_phoenix.sh \
#     --esp /boot/efi \
#     --dom0-vmlinuz /boot/vmlinuz-<ver> \
#     --dom0-initrd /boot/initrd.img-<ver> \
#     [--uuid <DOM0-ROOT-UUID> | --dom0-root /dev/nvme0n1p2] \
#     [--configure-bootentry] [--set-bootnext] [--recovery <pkg> [--sig <sig>]]
#
# On failure, this script prints clear instructions.

ESP=""
DOM0_VMLINUZ=""
DOM0_INITRD=""
DOM0_UUID=${DOM0_UUID:-}
DOM0_ROOT=${DOM0_ROOT:-}
CONFIGURE_BOOTENTRY=false
SET_BOOTNEXT=false
RECOVERY_PKG=""
RECOVERY_SIG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --esp) ESP="$2"; shift 2;;
    --dom0-vmlinuz) DOM0_VMLINUZ="$2"; shift 2;;
    --dom0-initrd) DOM0_INITRD="$2"; shift 2;;
    --uuid) DOM0_UUID="$2"; shift 2;;
    --dom0-root) DOM0_ROOT="$2"; shift 2;;
    --configure-bootentry) CONFIGURE_BOOTENTRY=true; shift 1;;
    --set-bootnext) SET_BOOTNEXT=true; shift 1;;
    --recovery) RECOVERY_PKG="$2"; shift 2;;
    --sig) RECOVERY_SIG="$2"; shift 2;;
    -h|--help) SHOW_HELP=1; shift 1;;
    *) echo "Unknown arg: $1"; exit 1;;
  esac
done

if [[ "${SHOW_HELP:-0}" == 1 ]]; then
  sed -n '1,60p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
fi

# Basic validation
if [[ -z "$ESP" ]]; then
  echo "ERROR: --esp <mountpoint> is required (e.g. /boot/efi)"
  exit 1
fi
if [[ ! -d "$ESP/EFI" ]]; then
  echo "ERROR: $ESP does not look like a mounted ESP (missing $ESP/EFI)"
  echo "Hint: Ensure your EFI System Partition is mounted. On Ubuntu, this is usually /boot/efi."
  exit 1
fi
if [[ -z "$DOM0_VMLINUZ" || -z "$DOM0_INITRD" ]]; then
  echo "ERROR: --dom0-vmlinuz and --dom0-initrd are required"
  echo "Example: --dom0-vmlinuz /boot/vmlinuz-$(uname -r) --dom0-initrd /boot/initrd.img-$(uname -r)"
  exit 1
fi
if [[ ! -f "$DOM0_VMLINUZ" ]]; then
  echo "ERROR: dom0 kernel not found: $DOM0_VMLINUZ"
  exit 1
fi
if [[ ! -f "$DOM0_INITRD" ]]; then
  echo "ERROR: dom0 initramfs not found: $DOM0_INITRD"
  exit 1
fi

# Auto-detect dom0 root UUID if not provided
if [[ -z "$DOM0_UUID" ]]; then
  if [[ -n "$DOM0_ROOT" ]]; then
    DOM0_UUID=$(blkid -s UUID -o value "$DOM0_ROOT" || true)
  else
    ROOT_SRC=$(findmnt -n -o SOURCE / || true)
    if [[ -n "$ROOT_SRC" ]]; then
      DOM0_UUID=$(blkid -s UUID -o value "$ROOT_SRC" || true)
    fi
  fi
  if [[ -n "$DOM0_UUID" ]]; then
    echo "Auto-detected dom0 root UUID: $DOM0_UUID"
  else
    echo "WARNING: Could not auto-detect dom0 root UUID; xen.cfg will contain a placeholder. Use --uuid or --dom0-root to set it."
  fi
fi

# Ensure xen.efi present or copy from system locations
mkdir -p "$ESP/EFI" "$ESP/EFI/PhoenixGuard/recovery"
XEN_SRC=$(ls /usr/lib/xen-*/boot/xen.efi 2>/dev/null | head -n1 || true)
if [[ -n "$XEN_SRC" ]]; then
  cp -f "$XEN_SRC" "$ESP/EFI/xen.efi"
  echo "Staged xen.efi -> $ESP/EFI/xen.efi"
else
  echo "ERROR: xen.efi not found in /usr/lib/xen-*/boot/."
  echo "Install the Xen hypervisor: sudo apt install xen-hypervisor-amd64"
  echo "Then re-run: sudo $0 --esp $ESP --dom0-vmlinuz $DOM0_VMLINUZ --dom0-initrd $DOM0_INITRD [--uuid <UUID>]"
  exit 1
fi

# Stage dom0 kernel/initramfs and xen.cfg
cp -f "$DOM0_VMLINUZ" "$ESP/EFI/dom0-vmlinuz"
cp -f "$DOM0_INITRD" "$ESP/EFI/dom0-init.img"
cat > "$ESP/EFI/xen.cfg" <<EOF
title Xen Snapshot Jump
kernel EFI\\dom0-vmlinuz console=hvc0 earlyprintk=xen root=UUID=${DOM0_UUID:-<DOM0-ROOT-UUID>} ro quiet loglvl=all guest_loglvl=all
module EFI\\dom0-init.img
EOF

echo "Wrote xen.cfg -> $ESP/EFI/xen.cfg"

# Stage recovery artifacts if provided
if [[ -n "$RECOVERY_PKG" ]]; then
  if [[ ! -f "$RECOVERY_PKG" ]]; then
    echo "ERROR: Recovery package not found: $RECOVERY_PKG"
    exit 1
  fi
  cp -f "$RECOVERY_PKG" "$ESP/EFI/PhoenixGuard/recovery/recovery.pkg"
  echo "Staged recovery package -> $ESP/EFI/PhoenixGuard/recovery/recovery.pkg"
  if [[ -n "$RECOVERY_SIG" ]]; then
    if [[ -f "$RECOVERY_SIG" ]]; then
      cp -f "$RECOVERY_SIG" "$ESP/EFI/PhoenixGuard/recovery/recovery.sig"
      echo "Staged recovery signature -> $ESP/EFI/PhoenixGuard/recovery/recovery.sig"
    else
      echo "WARNING: --sig provided but file not found: $RECOVERY_SIG"
    fi
  fi
fi

# Optionally create an NVRAM boot entry for \EFI\xen.efi
if [[ "$CONFIGURE_BOOTENTRY" == true ]]; then
  if command -v efibootmgr >/dev/null 2>&1; then
    ESP_DEV=$(findmnt -n -o SOURCE "$ESP" || true)
    if [[ -n "$ESP_DEV" ]]; then
      DISK=$(lsblk -no PKNAME "$ESP_DEV" 2>/dev/null | head -n1)
      PARTNUM=$(lsblk -no PARTNUM "$ESP_DEV" 2>/dev/null | head -n1)
      if [[ -n "$DISK" && -n "$PARTNUM" ]]; then
        DISK_PATH="/dev/$DISK"
        # Remove old entry if present
        BOOTNUM=$(efibootmgr | awk -F'*' '/PhoenixGuard Xen/{print $1}' | sed 's/Boot//;s/\s*$//')
        if [[ -n "$BOOTNUM" ]]; then efibootmgr -b "$BOOTNUM" -B || true; fi
        # Create new entry
        efibootmgr -c -d "$DISK_PATH" -p "$PARTNUM" -L "PhoenixGuard Xen" -l "\\EFI\\xen.efi" || true
        if [[ "$SET_BOOTNEXT" == true ]]; then
          NEWNUM=$(efibootmgr | awk -F'*' '/PhoenixGuard Xen/{print $1}' | sed 's/Boot//;s/\s*$//')
          if [[ -n "$NEWNUM" ]]; then efibootmgr -n "$NEWNUM" || true; fi
        fi
        echo "Configured NVRAM entry for \\EFI\\xen.efi"
      else
        echo "WARNING: Could not determine disk/partition for ESP at $ESP; skipping efibootmgr configuration."
      fi
    else
      echo "WARNING: Could not map $ESP to a block device; skipping efibootmgr configuration."
    fi
  else
    echo "WARNING: efibootmgr not installed; skipping NVRAM configuration."
  fi
fi

cat <<NOTE
✅ PhoenixGuard install complete at $ESP/EFI

What was installed:
  - xen.efi, xen.cfg, dom0-vmlinuz, dom0-init.img
  - Recovery dir: $ESP/EFI/PhoenixGuard/recovery/

Next steps (firmware):
  - Ensure firmware boot order includes the ESP entry for \\EFI\\xen.efi
  - Or re-run with --configure-bootentry [--set-bootnext]

If Secure Boot is ON and xen.efi isn't trusted:
  - Either enroll a key that signs xen.efi, or use shim+grub chainloading
  - Alternative: disable Secure Boot for testing (not recommended for production)
NOTE

