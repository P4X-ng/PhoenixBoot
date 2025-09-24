#!/usr/bin/env bash
set -euo pipefail

# Validate that the currently running OS matches expected root UUID/mounts
# and that EFI variables/boot entries align with a clean state.
# Usage: sudo EXPECT_UUID=<uuid> resources/xen/dom0/validate-clean-os.sh

UUID_EXPECT=${EXPECT_UUID:-}
REPORT=/var/log/p4xos-validate-clean-os.txt

log() { echo "[validate] $*" | tee -a "$REPORT"; }

: > "$REPORT"

if [[ -z "$UUID_EXPECT" ]]; then
  log "Set EXPECT_UUID=<uuid> to validate against."
  exit 1
fi

ROOT_SRC=$(findmnt -n -o SOURCE / || true)
ROOT_UUID=$(blkid -s UUID -o value "$ROOT_SRC" 2>/dev/null || true)
log "Root source: $ROOT_SRC"
log "Root UUID:   ${ROOT_UUID:-unknown}"

if [[ "$ROOT_UUID" != "$UUID_EXPECT" ]]; then
  log "MISMATCH: running root UUID does not match expected"
else
  log "OK: root UUID matches expected"
fi

log "Mounts:"
findmnt -t ext4,ext3,btrfs,xfs | tee -a "$REPORT" >/dev/null

log "EFI boot entries:"
efibootmgr -v | tee -a "$REPORT" >/dev/null || true

log "Done. Review $REPORT"

