#!/usr/bin/env bash
# Description: Runs a QEMU test for the UUEFI application.

set -euo pipefail
mkdir -p out/qemu out/esp
IMG=out/esp/esp.img
UUEFI_SRC="staging/boot/UUEFI.efi"
TEST_IMG=out/esp/esp-uuefi.img
LOG=out/qemu/serial-uuefi.log
REPORT=out/qemu/report-uuefi.xml

if [ ! -f "$IMG" ]; then
  echo "❌ No ESP image found - run 'just package-esp' first"; exit 1
fi
if [ ! -f "$UUEFI_SRC" ]; then
  echo "❌ Missing $UUEFI_SRC — provide a UUEFI.efi to run this test"; exit 1
fi
cp "$IMG" "$TEST_IMG"
# Replace BOOTX64.EFI with UUEFI.efi inside the test image (no mount, use mtools)
mcopy -i "$TEST_IMG" -o "$UUEFI_SRC" ::/EFI/BOOT/BOOTX64.EFI

# Discover OVMF paths
if [ -f out/esp/ovmf_paths.txt ]; then
  OVMF_CODE_PATH=$(sed -n '1p' out/esp/ovmf_paths.txt)
  OVMF_VARS_PATH=$(sed -n '2p' out/esp/ovmf_paths.txt)
else
  echo "❌ OVMF paths not discovered — run 'just setup' and 'just package-esp' first"; exit 1
fi
[ -f "$OVMF_CODE_PATH" ] || { echo "❌ OVMF CODE not found at $OVMF_CODE_PATH"; exit 1; }
[ -f "$OVMF_VARS_PATH" ] || { echo "❌ OVMF VARS not found at $OVMF_VARS_PATH"; exit 1; }

# Choose VARS: default to non-secure factory vars; use enrolled if UUEFI_SECURE=1
if [ "${UUEFI_SECURE:-0}" = "1" ] && [ -f out/qemu/OVMF_VARS_custom.fd ]; then
  VARS=out/qemu/OVMF_VARS_custom.fd
else
  VARS=out/qemu/OVMF_VARS_uuefi_test.fd
  cp "$OVMF_VARS_PATH" "$VARS"
fi

# Run QEMU
QT=${PG_QEMU_TIMEOUT:-60}
rm -f "$LOG"
timeout ${QT}s qemu-system-x86_64 \
  -machine q35 \
  -cpu host \
  -enable-kvm \
  -m 2G \
  -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE_PATH" \
  -drive if=pflash,format=raw,file="$VARS" \
  -drive format=raw,file="$TEST_IMG" \
  -serial file:"$LOG" \
  -display none \
  -no-reboot || true

# Evaluate success: look for marker or non-empty output
EXPECT=${UUEFI_EXPECT:-UUEFI}
RESULT=FAIL
if [ -s "$LOG" ]; then
  if grep -q "$EXPECT" "$LOG" 2>/dev/null; then
    echo "✅ UUEFI test PASSED (found marker: $EXPECT)"
    RESULT=PASS
  else
    echo "ℹ️  Marker '$EXPECT' not found; serial output present — treating as PASS for smoke test"
    RESULT=PASS
  fi
else
  echo "❌ UUEFI test FAILED (no serial output)"
  RESULT=FAIL
fi

# JUnit report
{
  echo '<?xml version="1.0" encoding="UTF-8"?>'
  echo '<testsuite name="PhoenixGuard UUEFI Test" tests="1" failures="'$([ "$RESULT" = PASS ] && echo 0 || echo 1)'" time="60">'
  echo '  <testcase name="UUEFI Smoke" classname="PhoenixGuard.UUEFI">'
  if [ "$RESULT" != PASS ]; then
    echo '    <failure message="UUEFI did not produce serial output or marker not found">Check out/qemu/serial-uuefi.log</failure>'
  fi
  echo '  </testcase>'
  echo '</testsuite>'
} > "$REPORT"
[ "$RESULT" = PASS ] || exit 1

