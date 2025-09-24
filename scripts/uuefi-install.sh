#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib/common.sh

info "🧩 Installing UUEFI.efi to system ESP"

# Config
EESP=${EESP:-/boot/efi}
UUEFI_SRC=${UUEFI_SRC:-staging/boot/UUEFI.efi}
OUT_DIR="out/uuefi"
ensure_dir "$OUT_DIR"

need_sudo() {
  if sudo -n true 2>/dev/null; then
    sudo -n "$@"
  else
    sudo -n "$@"
  fi
}

# Resolve source binary (fallback to BootX64.efi if UUEFI.efi missing)
if [ ! -f "$UUEFI_SRC" ]; then
  warn "UUEFI source not found at $UUEFI_SRC"
  if [ -f out/staging/BootX64.efi ]; then
    warn "Falling back to out/staging/BootX64.efi as UUEFI placeholder"
    UUEFI_SRC="out/staging/BootX64.efi"
  else
    die "No UUEFI.efi or out/staging/BootX64.efi present. Build or provide UUEFI.efi first."
  fi
fi

# Locate ESP mount
if ! mountpoint -q "$EESP" 2>/dev/null; then
  err "ESP not mounted at $EESP"
  echo "Tip: mount your EFI System Partition at $EESP or set EESP=/path/to/esp"
  exit 1
fi

ESP_DEV=$(findmnt -n -o SOURCE --target "$EESP" 2>/dev/null || true)
if [ -z "${ESP_DEV}" ]; then
  warn "Could not auto-detect ESP device from $EESP"
fi

# Determine disk and partition numbers for later BootNext setup
EFI_DISK=""
EFI_PART=""
if [ -n "$ESP_DEV" ]; then
  if [[ "$ESP_DEV" =~ ^/dev/nvme[0-9]+n[0-9]+p([0-9]+)$ ]]; then
    EFI_PART="${BASH_REMATCH[1]}"
    EFI_DISK="${ESP_DEV%p$EFI_PART}"
  elif [[ "$ESP_DEV" =~ ^/dev/[a-zA-Z]+([0-9]+)$ ]]; then
    EFI_PART="${BASH_REMATCH[1]}"
    EFI_DISK="${ESP_DEV%$EFI_PART}"
  fi
fi

# Destination path
DEST_DIR="$EESP/EFI/PhoenixGuard"
DEST_BIN="$DEST_DIR/UUEFI.efi"

# Ensure destination directory
if [ ! -d "$DEST_DIR" ]; then
  info "Creating $DEST_DIR"
  need_sudo mkdir -p "$DEST_DIR"
fi

# Sign if keys available (db key), else copy unsigned
SIGNED_TMP="$OUT_DIR/UUEFI.signed.efi"
SIGNED=0
if [ -f keys/db.key ] && [ -f keys/db.crt ] && command -v sbsign >/dev/null 2>&1; then
  info "Signing UUEFI with db key"
  sbsign --key keys/db.key --cert keys/db.crt --output "$SIGNED_TMP" "$UUEFI_SRC" || die "sbsign failed"
  if command -v sbverify >/dev/null 2>&1; then
    if sbverify --cert keys/db.crt "$SIGNED_TMP" >/dev/null 2>&1; then
      ok "Signature verified against db cert"
    else
      warn "Signature verification failed against db cert"
    fi
  fi
  SRC_TO_COPY="$SIGNED_TMP"
  SIGNED=1
else
  if [ ! -f keys/db.key ] || [ ! -f keys/db.crt ]; then
    warn "keys/db.key or keys/db.crt not found; installing unsigned UUEFI"
  elif ! command -v sbsign >/dev/null 2>&1; then
    warn "sbsign not installed; installing unsigned UUEFI"
  fi
  SRC_TO_COPY="$UUEFI_SRC"
fi

# Copy into ESP
info "Installing to $DEST_BIN"
need_sudo cp -f "$SRC_TO_COPY" "$DEST_BIN"
need_sudo chmod 0644 "$DEST_BIN" || true
ok "Installed $DEST_BIN"

# Persist detected EFI location for follow-up apply
ENV_FILE="$OUT_DIR/efiboot.env"
{
  echo "ESP_MOUNT=$EESP"
  [ -n "$EFI_DISK" ] && echo "EFI_DISK=$EFI_DISK"
  [ -n "$EFI_PART" ] && echo "EFI_PART=$EFI_PART"
} > "$ENV_FILE"
ok "Wrote $ENV_FILE"

if [ "$SIGNED" -eq 1 ]; then
  info "Ensure the db certificate used for signing is enrolled in firmware."
else
  warn "UUEFI installed unsigned; it will not boot with Secure Boot enabled unless shim/MOK path is used."
fi

info "Next: set one-shot BootNext to UUEFI using:"
if [ -n "$EFI_DISK" ] && [ -n "$EFI_PART" ]; then
  echo "  APP=UUEFI EFI_DISK=$EFI_DISK EFI_PART=$EFI_PART just uuefi-apply"
else
  echo "  APP=UUEFI EFI_DISK=/dev/sdX EFI_PART=1 just uuefi-apply"
fi

