#!/usr/bin/env bash
set -euo pipefail

# Minimal remediation: attempt to apply fwupd capsules (if provided),
# otherwise log and exit. Uses /etc/phoenixguard/kvm-snapshot.conf for capsule list.

CFG=/etc/phoenixguard/kvm-snapshot.conf
[[ -f "$CFG" ]] || { echo "Missing config: $CFG"; exit 1; }
# shellcheck disable=SC1090
source "$CFG"

log() { echo "[pg-remediate] $*"; }

if [[ -n "${FIRMWARE_CAPSULES:-}" ]]; then
  if command -v fwupdmgr >/dev/null 2>&1; then
    for cap in $FIRMWARE_CAPSULES; do
      if [[ -f "$cap" ]]; then
        log "Applying capsule: $cap"
        fwupdmgr install --allow-reinstall "$cap" || log "fwupdmgr failed for $cap"
      else
        log "Capsule not found: $cap"
      fi
    done
    log "Capsule application complete. A reboot may be required to finish updates."
  else
    log "fwupdmgr not installed; cannot apply capsules."
  fi
else
  log "No FIRMWARE_CAPSULES specified in config; nothing to do."
fi

log "Remediation done."
