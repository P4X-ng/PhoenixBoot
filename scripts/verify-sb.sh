#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib/common.sh

info "🔐 Secure Boot verification report"

# 1) Secure Boot state (firmware)
if command -v mokutil >/dev/null 2>&1; then
  SB_STATE=$(mokutil --sb-state 2>&1 || true)
  echo "SB: $SB_STATE"
else
  echo "SB: mokutil not installed (state unknown)"
fi

# 2) Kernel lockdown mode
if [ -f /sys/kernel/security/lockdown ]; then
  echo -n "Lockdown: "
  cat /sys/kernel/security/lockdown || true
else
  LKMSG=$(dmesg 2>/dev/null | grep -i 'Lockdown:' | tail -n1 || true)
  echo "Lockdown: ${LKMSG:-unknown}"
fi

# 3) Module signature enforcement
if [ -f /sys/module/module/parameters/sig_enforce ]; then
  echo -n "Module sig enforce: "
  cat /sys/module/module/parameters/sig_enforce || true
else
  if grep -q 'module.sig_enforce=1' /proc/cmdline 2>/dev/null; then
    echo "Module sig enforce: 1 (via cmdline)"
  else
    echo "Module sig enforce: unknown"
  fi
fi

# 4) Verify ESP signatures (if image exists)
IMG=out/esp/esp.img
TMPDIR=$(mktemp -d)
cleanup() { rm -rf "$TMPDIR" 2>/dev/null || true; }
trap cleanup EXIT

if [ -f "$IMG" ]; then
  echo "ESP: $IMG"
  have_sbverify=0
  if command -v sbverify >/dev/null 2>&1; then have_sbverify=1; fi

  extract_and_check() {
    local src="$1" name="$2"
    local dst="$TMPDIR/${name}"
    if mtype -i "$IMG" ::"$src" >/dev/null 2>&1; then
      mcopy -n -i "$IMG" ::"$src" "$dst" >/dev/null 2>&1 || true
      size=$(stat -c%s "$dst" 2>/dev/null || echo 0)
      echo "  - $src (size=${size})"
      if [ "$have_sbverify" -eq 1 ]; then
        echo "    signatures:"
        sbverify --list "$dst" || true
        if [ -f keys/db.crt ]; then
          if sbverify --cert keys/db.crt "$dst" >/dev/null 2>&1; then
            echo "    verify(db): OK"
          else
            echo "    verify(db): FAIL"
          fi
        fi
      else
        echo "    sbverify not installed; skipping signature introspection"
      fi
    else
      echo "  - $src: MISSING"
    fi
  }

  extract_and_check "/EFI/BOOT/BOOTX64.EFI" "BOOTX64.EFI"
  extract_and_check "/EFI/PhoenixGuard/BootX64.efi" "PG_BootX64.efi"
  extract_and_check "/EFI/PhoenixGuard/grubx64.efi" "grubx64.efi"

  # Allowed manifest presence
  if mtype -i "$IMG" ::/EFI/PhoenixGuard/Allowed.manifest.sha256 >/dev/null 2>&1; then
    echo "  - Allowed.manifest.sha256: PRESENT"
  else
    echo "  - Allowed.manifest.sha256: MISSING (optional)"
  fi
else
  echo "ESP: not found (run 'just package-esp' first)"
fi

ok "Secure Boot verification report complete"

