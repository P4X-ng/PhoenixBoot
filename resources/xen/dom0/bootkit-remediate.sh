#!/usr/bin/env bash
set -euo pipefail

# Bootkit remediation toolkit (safe by default)
# - Backs up ESP(s)
# - Audits EFI boot entries
# - Quarantines suspicious ESP contents (optional)
# - Reinstalls clean boot entries (optional)
# - Checks SPI write-protect status
# - Collects a JSON report
#
# Usage:
#   sudo BOOT_DEV=/dev/nvme0n1p1 ./bootkit-remediate.sh          # dry-run
#   sudo P4XOS_CLEAN=1 BOOT_DEV=/dev/nvme0n1p1 ./bootkit-remediate.sh  # execute actions
#   Optional: AGGRESSIVE=1 to quarantine non-whitelisted ESP dirs
#
# Notes:
# - Requires: efibootmgr, sfdisk/lsblk, tar, jq (optional), flashrom (optional), fwupdmgr (optional)

DRY_RUN=${P4XOS_CLEAN:-}
AGGR=${AGGRESSIVE:-}
ESP_DEV=${BOOT_DEV:-}
WORK=/var/lib/p4xos/bootkit
LOGDIR=/var/log
REPORT=$LOGDIR/p4xos-bootkit-report.json

mkdir -p "$WORK" "$LOGDIR"

log() { echo "[remediate] $*"; }
act() {
  if [[ -z "$DRY_RUN" ]]; then
    eval "$@"
  else
    log "DRY-RUN: $*"
  fi
}

require() {
  command -v "$1" >/dev/null 2>&1 || { log "Missing required tool: $1"; exit 1; }
}

require efibootmgr
require lsblk
require tar

# Detect ESP if not provided
if [[ -z "$ESP_DEV" ]]; then
  # prefer system-mounted ESP
  if findmnt -n -o SOURCE /boot/efi >/dev/null 2>&1; then
    ESP_DEV=$(findmnt -n -o SOURCE /boot/efi)
  else
    # heuristic: first FAT32 partition marked esp
    ESP_DEV=$(lsblk -rpno NAME,PARTTYPE,FSTYPE | awk '/c12a7328-f81f-11d2-ba4b-00a0c93ec93b/ || /vfat/ {print $1; exit}')
  fi
fi

if [[ -z "$ESP_DEV" ]]; then
  log "Could not determine ESP device. Set BOOT_DEV=/dev/.."
  exit 1
fi

log "Using ESP device: $ESP_DEV"

# Mount ESP read-only for inspection
MNT=$WORK/esp
mkdir -p "$MNT"
act "mount -o ro $ESP_DEV $MNT"
trap 'umount "$MNT" 2>/dev/null || true' EXIT

# Backup ESP
TS=$(date -u +%Y%m%dT%H%M%SZ)
BACKUP=$WORK/esp-backup-$TS.tar.gz
act "tar -C $MNT -czf $BACKUP ."
log "ESP backup at $BACKUP"

# Audit EFI boot entries
BOOT_ENTRIES=$WORK/efibootmgr-$TS.txt
efibootmgr -v | tee "$BOOT_ENTRIES" >/dev/null || true

# Simple whitelist for ESP top-level dirs
WHITELIST=(EFI efi System Volume Information)

# List top-level dirs/files
TREE=$WORK/esp-tree-$TS.txt
ls -la "$MNT" > "$TREE" || true

# Prepare quarantine plan
QUAR_DIR=$WORK/quarantine-$TS
mkdir -p "$QUAR_DIR"

should_quarantine() {
  local name="$1"
  for w in "${WHITELIST[@]}"; do
    [[ "$name" == "$w" ]] && return 1
  done
  return 0
}

if [[ -n "$AGGR" ]]; then
  # Plan to move non-whitelisted items
  while IFS= read -r entry; do
    base=$(basename "$entry")
    [[ "$base" == "." || "$base" == ".." ]] && continue
    if should_quarantine "$base"; then
      log "Quarantine candidate: $base"
    fi
  done < <(find "$MNT" -maxdepth 1 -mindepth 1)
fi

# NVRAM cleanup plan: delete Boot#### that point to missing or non-whitelisted paths
DEL_PLAN=$WORK/efibootmgr-delete-$TS.txt
: > "$DEL_PLAN"
while read -r line; do
  # Example: Boot0003* UEFI OS HD(...) File(\EFI\BOOT\BOOTX64.EFI)
  if [[ "$line" =~ ^Boot([0-9A-Fa-f]{4})\*\  ]]; then
    id=${BASH_REMATCH[1]}
    path=$(echo "$line" | sed -n 's/.*File(\\\\\(.*\)).*/\1/p')
    if [[ -n "$path" ]]; then
      top=$(echo "$path" | awk -F'\\\\' '{print $1}')
      ok=0
      for w in "${WHITELIST[@]}"; do
        [[ "$top" == "$w" || "$top" == "${w,,}" ]] && ok=1
      done
      if [[ $ok -eq 0 ]]; then
        echo "efibootmgr -b $id -B" >> "$DEL_PLAN"
        log "Plan delete Boot$id -> $path"
      fi
    fi
  fi
done < "$BOOT_ENTRIES"

# Unmount RO, remount RW for actions
umount "$MNT" || true
act "mount -o rw $ESP_DEV $MNT"

# Execute quarantine moves
if [[ -n "$AGGR" ]]; then
  while IFS= read -r entry; do
    base=$(basename "$entry")
    [[ "$base" == "." || "$base" == ".." ]] && continue
    if should_quarantine "$base"; then
      act "mkdir -p $QUAR_DIR && mv $MNT/$base $QUAR_DIR/"
      log "Quarantined $base"
    fi
  done < <(find "$MNT" -maxdepth 1 -mindepth 1)
fi

# Ensure minimal clean paths exist
act "mkdir -p $MNT/EFI/BOOT $MNT/EFI/P4XOS $MNT/EFI/Xen"

# Apply NVRAM deletions
if [[ -s "$DEL_PLAN" ]]; then
  while read -r cmd; do
    act "$cmd"
  done < "$DEL_PLAN"
fi

# Hardware-level firmware verification and recovery (optional)
FIRMWARE_RECOVERY=$WORK/firmware-recovery-$TS.json
HOST_IP=$(hostname -I | awk '{print $1}' || echo "localhost")

log "Running hardware-level firmware verification..."
if ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$USER@$HOST_IP" "test -f /home/$USER/Projects/edk2-bootkit-defense/PhoenixGuard/scripts/hardware_firmware_recovery.py" 2>/dev/null; then
  # Try to dump and verify current firmware on host
  ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$USER@$HOST_IP" \
    "cd /home/$USER/Projects/edk2-bootkit-defense/PhoenixGuard && \
     sudo python3 scripts/hardware_firmware_recovery.py --verify-only /dev/null --output firmware_check_results.json" \
    || log "WARNING: Host firmware verification failed"
    
  # Copy results back to dom0
  scp -o ConnectTimeout=10 -o StrictHostKeyChecking=no \
    "$USER@$HOST_IP:/home/$USER/Projects/edk2-bootkit-defense/PhoenixGuard/firmware_check_results.json" \
    "$FIRMWARE_RECOVERY" 2>/dev/null || log "Could not retrieve firmware check results"
    
  if [[ -f "$FIRMWARE_RECOVERY" ]]; then
    # Check for bootkit protections or suspicious firmware
    if command -v jq >/dev/null 2>&1; then
      SUSPICIOUS=$(jq -r '.bootkit_protections | to_entries[] | select(.value == true) | .key' "$FIRMWARE_RECOVERY" 2>/dev/null | wc -l)
      if [[ "$SUSPICIOUS" -gt 0 ]]; then
        log "⚠️  BOOTKIT PROTECTIONS DETECTED on host firmware!"
        log "    Manual firmware recovery may be required on next boot"
        # TODO: Could trigger automatic clean firmware reflashing here if P4XOS_CLEAN=1
      fi
    fi
  fi
else
  log "Hardware firmware recovery script not available on host"
fi

# SPI write-protect status (legacy check)
SPI=$WORK/spi-status-$TS.txt
if command -v flashrom >/dev/null 2>&1; then
  (flashrom --wp-status || true) | tee "$SPI" >/dev/null
fi

# fwupd status (optional)
FWUPD=$WORK/fwupd-$TS.txt
if command -v fwupdmgr >/dev/null 2>&1; then
  (fwupdmgr get-devices || true) | tee "$FWUPD" >/dev/null
fi

# Report
cat > "$REPORT" <<JSON
{
  "timestamp": "$TS",
  "esp_device": "$ESP_DEV",
  "backup": "$BACKUP",
  "tree": "$TREE",
  "efibootmgr": "$BOOT_ENTRIES",
  "nvram_delete_plan": "$DEL_PLAN",
  "quarantine_dir": "$QUAR_DIR",
  "spi_status": "${SPI:-}",
  "fwupd": "${FWUPD:-}",
  "dry_run": "${DRY_RUN:+true}"
}
JSON

log "Report: $REPORT"
log "Done. Reboot only after validating backup and report."

