#!/usr/bin/env bash
set -euo pipefail

# Install xen.efi/xen.cfg and dom0 kernel+initramfs to an ESP using a flat layout at /EFI
# Usage: sudo ./scripts/install_xen_snapshot_jump.sh --esp /boot/efi --dom0-vmlinuz /path/vmlinuz --dom0-initrd /path/initrd.img [--uuid <DOM0-ROOT-UUID>] [--dom0-root <dev>]
# Optional (advanced):
#   --install-fallback                 # also install a removable-path fallback at \\EFI\\BOOT
#   --fallback-mode shim-grub|xen-copy # select fallback type (default: shim-grub)
#   --configure-bootentry              # create/update a NVRAM Boot#### entry for \\EFI\\xen.efi
#   --set-bootnext                     # set BootNext to the created/updated entry (use with care)

ESP=
DOM0_VMLINUZ=
DOM0_INITRD=
DOM0_UUID=${DOM0_UUID:-}
DOM0_ROOT=${DOM0_ROOT:-}
INSTALL_FALLBACK=false
FALLBACK_MODE=${FALLBACK_MODE:-shim-grub}
CONFIGURE_BOOTENTRY=false
SET_BOOTNEXT=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --esp) ESP="$2"; shift 2;;
    --dom0-vmlinuz) DOM0_VMLINUZ="$2"; shift 2;;
    --dom0-initrd) DOM0_INITRD="$2"; shift 2;;
    --uuid) DOM0_UUID="$2"; shift 2;;
    --dom0-root) DOM0_ROOT="$2"; shift 2;;
    --install-fallback) INSTALL_FALLBACK=true; shift 1;;
    --fallback-mode) FALLBACK_MODE="$2"; shift 2;;
    --configure-bootentry) CONFIGURE_BOOTENTRY=true; shift 1;;
    --set-bootnext) SET_BOOTNEXT=true; shift 1;;
    *) echo "Unknown arg: $1"; exit 1;;
  esac
done

if [[ -z "$ESP" || -z "$DOM0_VMLINUZ" || -z "$DOM0_INITRD" ]]; then
  echo "Required: --esp, --dom0-vmlinuz, --dom0-initrd"
  exit 1
fi

# Try to auto-detect dom0 root UUID if not provided
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

mkdir -p "$ESP/EFI"

# xen.efi is provided by xen-hypervisor packages. Copy if present in common locations.
XEN_EFI_SRC="/usr/lib/xen-*/boot/xen.efi"
if compgen -G "$XEN_EFI_SRC" > /dev/null; then
  cp "$(ls $XEN_EFI_SRC | head -n1)" "$ESP/EFI/xen.efi"
else
  echo "WARNING: xen.efi not found automatically. Please copy xen.efi to $ESP/EFI/xen.efi manually."
fi

# Stage dom0 kernel/initramfs at EFI root with simple names
cp "$DOM0_VMLINUZ" "$ESP/EFI/dom0-vmlinuz"
cp "$DOM0_INITRD" "$ESP/EFI/dom0-init.img"

# Write xen.cfg at EFI root
CFG_PATH="$ESP/EFI/xen.cfg"
CFG_TMP=$(mktemp)
cat > "$CFG_TMP" <<EOF
title Xen Snapshot Jump
kernel EFI\\dom0-vmlinuz console=hvc0 earlyprintk=xen root=UUID=${DOM0_UUID:-<DOM0-ROOT-UUID>} ro quiet loglvl=all guest_loglvl=all
module EFI\\dom0-init.img
EOF
mv "$CFG_TMP" "$CFG_PATH"

# Optional: install removable-path fallback at \\EFI\\BOOT
if [[ "$INSTALL_FALLBACK" == true ]]; then
  BOOT_DIR="$ESP/EFI/BOOT"
  mkdir -p "$BOOT_DIR"
  case "$FALLBACK_MODE" in
    shim-grub)
      SHIM_PATH="/usr/lib/shim/shimx64.efi.signed"
      GRUB_SIGNED="/usr/lib/grub/x86_64-efi-signed/grubx64.efi.signed"
      if [[ -f "$SHIM_PATH" && -f "$GRUB_SIGNED" ]]; then
        cp "$SHIM_PATH" "$BOOT_DIR/BOOTX64.EFI"
        cp "$GRUB_SIGNED" "$BOOT_DIR/grubx64.efi"
        # Minimal grub.cfg to chainload xen.efi
        cat > "$BOOT_DIR/grub.cfg" <<'GRUBCFG'
search --no-floppy --file --set=esp /EFI/xen.efi
chainloader ($esp)/EFI/xen.efi
boot
GRUBCFG
        echo "Installed Secure Boot-friendly removable fallback (shim+grub) at $BOOT_DIR"
      else
        echo "WARNING: Signed shim/grub not found. Skipping shim-grub fallback."
      fi
      ;;
    xen-copy)
      # Copy xen.efi as BOOTX64.EFI (only works if xen.efi is signed or Secure Boot is off)
      if [[ -f "$ESP/EFI/xen.efi" ]]; then
        cp "$ESP/EFI/xen.efi" "$BOOT_DIR/BOOTX64.EFI"
        echo "Installed BOOTX64.EFI as direct xen.efi copy at $BOOT_DIR (ensure signature policy allows it)."
      else
        echo "WARNING: xen.efi not present; cannot create xen-copy fallback."
      fi
      ;;
    *)
      echo "Unknown --fallback-mode '$FALLBACK_MODE' (expected shim-grub|xen-copy)";;
  esac
fi

# Optional: configure NVRAM boot entry
if [[ "$CONFIGURE_BOOTENTRY" == true ]]; then
  if command -v efibootmgr >/dev/null 2>&1; then
    # Attempt to find disk and partition from ESP path
    ESP_DEV=$(findmnt -n -o SOURCE "$ESP" || true)
    if [[ -n "$ESP_DEV" ]]; then
      DISK=$(lsblk -no PKNAME "$ESP_DEV" 2>/dev/null | head -n1)
      PARTNUM=$(lsblk -no PARTNUM "$ESP_DEV" 2>/dev/null | head -n1)
      if [[ -n "$DISK" && -n "$PARTNUM" ]]; then
        DISK_PATH="/dev/$DISK"
        # Create/update entry named "PhoenixGuard Xen"
        BOOTNUM=$(efibootmgr | awk -F'*' '/PhoenixGuard Xen/{print $1}' | sed 's/Boot//;s/\s*$//')
        if [[ -n "$BOOTNUM" ]]; then
          efibootmgr -b "$BOOTNUM" -B || true
        fi
        efibootmgr -c -d "$DISK_PATH" -p "$PARTNUM" -L "PhoenixGuard Xen" -l "\\EFI\\xen.efi" || true
        if [[ "$SET_BOOTNEXT" == true ]]; then
          NEWNUM=$(efibootmgr | awk -F'*' '/PhoenixGuard Xen/{print $1}' | sed 's/Boot//;s/\s*$//')
          if [[ -n "$NEWNUM" ]]; then
            efibootmgr -n "$NEWNUM" || true
          fi
        fi
        echo "Configured NVRAM boot entry for \\EFI\\xen.efi"
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

echo "Installed Xen Snapshot Jump assets to $ESP"
echo "Next: ensure xen.efi exists and add a firmware boot entry for \\EFI\\xen.efi if needed."

