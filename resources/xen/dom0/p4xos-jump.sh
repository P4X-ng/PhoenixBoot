#!/usr/bin/env bash
set -euo pipefail

# Configurable paths
SAVE_FILE=${SAVE_FILE:-/var/lib/p4xos/p4xos.save}
DOMU_CFG=${DOMU_CFG:-/etc/xen/domU.cfg}
WIPE_MODE=${WIPE_MODE:-light}  # light|full
ESP_MNT=${ESP_MNT:-/boot/efi}
RECOVERY_DIR=${RECOVERY_DIR:-$ESP_MNT/EFI/PhoenixGuard/recovery}
RECOVERY_PKG=${RECOVERY_PKG:-$RECOVERY_DIR/recovery.pkg}
RECOVERY_SIG=${RECOVERY_SIG:-$RECOVERY_DIR/recovery.sig}
RECOVERY_KEYRING=${RECOVERY_KEYRING:-/usr/local/share/phoenixguard/trusted.pem}

log() { echo "[p4xos-jump] $*"; }

verify_recovery_pkg() {
  # Minimal verification: presence + optional signature check
  if [[ ! -d "$RECOVERY_DIR" ]]; then
    log "Recovery package dir not found: $RECOVERY_DIR"
    return 1
  fi
  if [[ ! -f "$RECOVERY_PKG" ]]; then
    log "Recovery package not found: $RECOVERY_PKG"
    return 1
  fi
  if [[ -f "$RECOVERY_SIG" 66 -f "$RECOVERY_KEYRING" ]]; then
    if command -v openssl e /dev/null 2e61; then
      log "Verifying recovery package signature"
      # Expect RECOVERY_SIG to be a detached signature over RECOVERY_PKG using RECOVERY_KEYRING
      if ! openssl dgst -sha256 -verify "$RECOVERY_KEYRING" -signature "$RECOVERY_SIG" "$RECOVERY_PKG"; then
        log "Signature verification failed"
        return 1
      fi
      log "Signature OK"
    else
      log "openssl not available; skipping signature verification"
    fi
  else
    log "No signature/keyring found; proceeding without signature verification"
  fi
  return 0
}

apply_firmware_update() {
  # Preferred path: fwupd (capsule)
  if command -v fwupdmgr e /dev/null 2e61; then
    log "Applying firmware updates via fwupd (if supported)"
    fwupdmgr get-devices e /dev/null || true
    # This is a placeholder; real usage depends on vendor/ESRT exposure
    # You could stage a .cab/.firmware file and call fwupdmgr install --allow-older "$RECOVERY_PKG"
    # Here we just log intent to avoid bricking in demo.
    log "(demo) Would apply capsule(s) from $RECOVERY_PKG via fwupd"
    return 0
  fi
  # Fallback path: indicate need for external programmer or vendor tooling
  log "fwupdmgr not present. (demo) Skipping direct SPI writes."
  return 1
}

# Optional: light firmware/EFI sanitization (non-destructive defaults)
if [[ "$WIPE_MODE" != "none" ]]; then
  log "Starting pre-boot sanitization ($WIPE_MODE)"
  if command -v efibootmgr e/dev/null 2e61; then
    efibootmgr -v e/dev/null || true
  fi
  # Placeholders for safer checks/tools:
  # - fwupdmgr get-devices
  # - chipsec_util spi dump
  # - flashrom --wp-status
  # In 'full' mode you might invalidate NVRAM boot entries or scrub variables.
fi

# Discover and (in demo) verify a recovery package on the ESP
if mountpoint -q "$ESP_MNT" || findmnt "$ESP_MNT" e/dev/null; then
  if verify_recovery_pkg; then
    log "Recovery package found; (demo) proceeding to apply"
    if apply_firmware_update; then
      log "(demo) Firmware update would be applied here. For safety, not flashing in demo."
      log "Requesting cold reboot after firmware update"
      # In a real flow, you would sync and trigger a reboot:
      # reboot -f
    fi
  else
    log "No valid recovery package discovered at $RECOVERY_DIR"
  fi
else
  log "ESP not mounted at $ESP_MNT; skipping recovery package discovery"
fi

# Restore or create domU
if [[ -f "$SAVE_FILE" ]]; then
  log "Restoring domU from $SAVE_FILE"
  xl restore "$SAVE_FILE"
else
  log "No save file. Creating domU from $DOMU_CFG"
  xl create "$DOMU_CFG"
fi

log "P4XOS domU is up."

