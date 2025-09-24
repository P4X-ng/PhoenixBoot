#!/usr/bin/env bash
set -euo pipefail
# Minimal dom0 audit scaffold for PhoenixGuard Xen remediation
# Produces a JSON report with ESP hashes, efibootmgr snapshot, and ACPI table hashes when possible.
# Safe by default: does not modify ESP or NVRAM. Write paths under /var/log.

# Config
REPORT_DIR=/var/log
REPORT_JSON="$REPORT_DIR/p4xos-bootkit-report.json"
ESP_MNT="${BOOT_DEV:-/boot/efi}"
TS=$(date -Is || date)

mkdir -p "$REPORT_DIR"

# Collect efibootmgr -v if available
EFIBOOT_TXT="$REPORT_DIR/p4xos-efibootmgr.txt"
if command -v efibootmgr >/dev/null 2>&1; then
  efibootmgr -v > "$EFIBOOT_TXT" 2>/dev/null || true
else
  echo "efibootmgr not present" > "$EFIBOOT_TXT"
fi

# Collect ESP hash listing
ESP_HASH_TXT="$REPORT_DIR/p4xos-esp-hashes.txt"
if [ -d "$ESP_MNT" ]; then
  # Hash only regular files to keep output compact
  find "$ESP_MNT" -type f -print0 2>/dev/null | xargs -0 -r sha256sum > "$ESP_HASH_TXT" 2>/dev/null || true
else
  echo "ESP mount not found: $ESP_MNT" > "$ESP_HASH_TXT"
fi

# ACPI table hashes (best-effort)
ACPI_DIR="$REPORT_DIR/p4xos-acpi"
mkdir -p "$ACPI_DIR"
ACPI_INFO="$ACPI_DIR/info.txt"
ACPI_HASH_TXT="$ACPI_DIR/acpi-hashes.txt"
if command -v acpidump >/dev/null 2>&1; then
  acpidump > "$ACPI_INFO" 2>/dev/null || true
  # Extract tables if acpixtract available, else fallback to hashing the dump
  if command -v acpixtract >/dev/null 2>&1; then
    acpidump -b -o "$ACPI_DIR/acpi.dat" >/dev/null 2>&1 || true
    acpixtract -a "$ACPI_DIR/acpi.dat" >/dev/null 2>&1 || true
    (cd "$ACPI_DIR" && ls *.dat 2>/dev/null | xargs -r -I{} sh -c 'sha256sum "$1" | sed "s| $1| ACPI:$1|"' _ {} ) > "$ACPI_HASH_TXT" 2>/dev/null || true
  else
    sha256sum "$ACPI_INFO" > "$ACPI_HASH_TXT" 2>/dev/null || true
  fi
else
  echo "acpidump not present" > "$ACPI_HASH_TXT"
fi

# SPI/flash status hooks (disabled by default)
# Uncomment with care; these may require root and platform support.
# CHIPSEC_LOG="$REPORT_DIR/p4xos-chipsec-spi.txt"
# if command -v chipsec_util >/dev/null 2>&1; then
#   chipsec_util spi info > "$CHIPSEC_LOG" 2>/dev/null || true
# fi

# Assemble JSON (without jq)
cat > "$REPORT_JSON" <<JSON
{
  "timestamp": "${TS}",
  "esp_mount": "${ESP_MNT}",
  "outputs": {
    "efibootmgr": "${EFIBOOT_TXT}",
    "esp_hashes": "${ESP_HASH_TXT}",
    "acpi_hashes": "${ACPI_HASH_TXT}"
  }
}
JSON

echo "[p4xos-audit] Wrote report: $REPORT_JSON"
echo "  efibootmgr snapshot: $EFIBOOT_TXT"
echo "  ESP hashes:         $ESP_HASH_TXT"
echo "  ACPI hashes:        $ACPI_HASH_TXT"
