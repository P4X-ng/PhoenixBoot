#!/usr/bin/env bash
# Description: Runs a strict Secure Boot test in QEMU, checking for specific markers.

set -euo pipefail
mkdir -p out/qemu

if [ ! -f out/esp/esp.img ]; then
    echo "❌ No ESP image found - run 'just package-esp' first"
    exit 1
fi
if [ ! -f out/qemu/OVMF_VARS_custom.fd ]; then
    echo "❌ Missing enrolled OVMF VARS (out/qemu/OVMF_VARS_custom.fd). Run 'just enroll-secureboot' first."
    exit 1
fi
[ -f out/setup/ovmf_code_path ] || { echo "❌ Missing OVMF discovery; run 'just setup'"; exit 1; }
OVMF_CODE_PATH=$(cat out/setup/ovmf_code_path)

echo "🚀 Using OVMF (secure): $OVMF_CODE_PATH"

QT=${PG_QEMU_TIMEOUT:-60}
timeout ${QT}s qemu-system-x86_64 \
    -machine q35 \
    -cpu host \
    -enable-kvm \
    -m 2G \
    -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE_PATH" \
    -drive if=pflash,format=raw,file=out/qemu/OVMF_VARS_custom.fd \
    -drive format=raw,file=out/esp/esp.img \
    -serial file:out/qemu/serial-secure-strict.log \
    -display none \
    -no-reboot || true

if grep -q "\[PG-SB=OK\]" out/qemu/serial-secure-strict.log && grep -q "\[PG-ATTEST=OK\]" out/qemu/serial-secure-strict.log; then
    TEST_RESULT="PASS"
    echo "✅ Secure boot strict test PASSED"
else
    TEST_RESULT="FAIL"
    echo "❌ Secure boot strict test FAILED"
fi

{
    echo '<?xml version="1.0" encoding="UTF-8"?>';
    echo '<testsuite name="PhoenixGuard Secure Boot Strict Test" tests="1" failures="'$([[ $TEST_RESULT == "FAIL" ]] && echo "1" || echo "0")'" time="60">';
    echo '  <testcase name="Secure Boot Strict" classname="PhoenixGuard.Secure">';
    [[ $TEST_RESULT == "FAIL" ]] && echo '    <failure message="Strict markers missing">Expected [PG-SB=OK] and [PG-ATTEST=OK]</failure>' || true;
    echo '  </testcase>';
    echo '</testsuite>';
} > out/qemu/report-secure-strict.xml

[ "$TEST_RESULT" == "PASS" ] || exit 1

