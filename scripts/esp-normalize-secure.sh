#!/usr/bin/env bash
set -euo pipefail

# Normalize ESP so BOOTX64.EFI is shimx64.efi and mmx64.efi is present.
# Adds robust progress logging and timeouts to avoid appearing stuck.
# Logs to: out/logs/esp-normalize-secure.log

cd "$(dirname "$0")/.."
source scripts/lib/common.sh

IMG=${IMG:-out/esp/esp.img}
[ -f "$IMG" ] || die "Missing $IMG; run 'just package-esp' or 'just iso-prep' first"

# Logging setup
LOG_DIR=out/logs
ensure_dir "$LOG_DIR"
LOG_FILE="$LOG_DIR/esp-normalize-secure.log"
# Append both stdout/stderr to log while preserving console output
exec > >(tee -a "$LOG_FILE") 2>&1

info "🔧 Normalizing ESP for Secure Boot: $IMG"

# Timeouts (seconds) for mtools operations to avoid hangs
MTOOLS_TIMEOUT=${PG_MTOOLS_TIMEOUT:-30}

# Locate shim and MokManager
SHIM=""; MM=""
CAND_SHIM=(
  "/usr/lib/shim/shimx64.efi.signed"
  "/usr/lib/shim/shimx64.efi"
  "/boot/efi/EFI/ubuntu/shimx64.efi"
  "/usr/lib/efi/shimx64.efi"
)
CAND_MM=(
  "/usr/lib/shim/mmx64.efi.signed"
  "/usr/lib/shim/mmx64.efi"
  "/usr/lib/shim/MokManager.efi.signed"
  "/usr/lib/shim/MokManager.efi"
  "/boot/efi/EFI/ubuntu/mmx64.efi"
  "/usr/lib/efi/mmx64.efi"
)
for c in "${CAND_SHIM[@]}"; do [ -f "$c" ] && SHIM="$c" && break || true; done
for c in "${CAND_MM[@]}";   do [ -f "$c" ] && MM="$c"   && break || true; done
[ -n "$SHIM" ] || die "Could not find shimx64.efi on host"

info "Using shim: $SHIM"
[ -n "$MM" ] && info "Using MokManager/mmx64: $MM" || warn "MokManager not found; continuing without it"

# Helper: try mtools, on failure fall back to loop mount operations
fallback_loop_copy() {
  warn "Falling back to loop mount method"
  local mnt=out/esp/mnt.$$;
  ensure_dir "$mnt"
  if mountpoint -q "$mnt"; then sudo umount "$mnt" || true; fi
  sudo mount -o loop,rw "$IMG" "$mnt" || die "Failed to mount $IMG"
  sudo mkdir -p "$mnt/EFI/BOOT"
  sudo install -D -m0644 "$SHIM" "$mnt/EFI/BOOT/BOOTX64.EFI"
  if [ -n "$MM" ]; then
    sudo install -D -m0644 "$MM" "$mnt/EFI/BOOT/mmx64.efi" || true
  fi
  sudo rm -rf "$mnt/EFI/ubuntu" 2>/dev/null || true
  sync || true
  sudo umount "$mnt" || true
  rmdir "$mnt" 2>/dev/null || true
}

# Ensure EFI/BOOT exists in image (avoid interactive prompts by checking first)
info "Ensuring directory structure via mtools..."
if ! timeout "$MTOOLS_TIMEOUT"s mdir -i "$IMG" ::/EFI >/dev/null 2>&1; then
  info "Creating ::/EFI"
  if ! timeout "$MTOOLS_TIMEOUT"s mmd -i "$IMG" ::/EFI 2>/dev/null; then fallback_loop_copy; ok "ESP normalized for Secure Boot (shim default)"; info "Log: $LOG_FILE"; exit 0; fi
else
  info "Directory ::/EFI exists; skipping"
fi
if ! timeout "$MTOOLS_TIMEOUT"s mdir -i "$IMG" ::/EFI/BOOT >/dev/null 2>&1; then
  info "Creating ::/EFI/BOOT"
  if ! timeout "$MTOOLS_TIMEOUT"s mmd -i "$IMG" ::/EFI/BOOT 2>/dev/null; then fallback_loop_copy; ok "ESP normalized for Secure Boot (shim default)"; info "Log: $LOG_FILE"; exit 0; fi
else
  info "Directory ::/EFI/BOOT exists; skipping"
fi

# Copy shim as BOOTX64.EFI (with progress markers)
info "Copying shim to EFI/BOOT/BOOTX64.EFI via mtools..."
if ! timeout "$MTOOLS_TIMEOUT"s mcopy -i "$IMG" -o "$SHIM" ::/EFI/BOOT/BOOTX64.EFI; then fallback_loop_copy; ok "ESP normalized for Secure Boot (shim default)"; info "Log: $LOG_FILE"; exit 0; fi
ok "BOOTX64.EFI updated"

# Copy mmx64/MokManager if available
if [ -n "$MM" ]; then
  info "Copying MokManager to EFI/BOOT/mmx64.efi via mtools..."
  ( timeout "$MTOOLS_TIMEOUT"s mcopy -i "$IMG" -o "$MM" ::/EFI/BOOT/mmx64.efi ) || warn "mcopy mmx64 → EFI/BOOT failed (continuing)"
fi

# Remove confusing vendor trees inside the image (best-effort)
info "Removing EFI/ubuntu tree from ESP via mtools (if present) ..."
if timeout "$MTOOLS_TIMEOUT"s mdir -i "$IMG" ::/EFI/ubuntu >/dev/null 2>&1; then
  ( timeout "$MTOOLS_TIMEOUT"s mrd -i "$IMG" ::/EFI/ubuntu ) || true
else
  info "No EFI/ubuntu directory present"
fi

ok "ESP normalized for Secure Boot (shim default)"
info "Log: $LOG_FILE"

