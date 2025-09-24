#!/usr/bin/env bash
# Description: Runs the main QEMU boot test.

set -euo pipefail
mkdir -p out/qemu

if [ ! -f out/esp/esp.img ]; then
    echo "❌ No ESP image found - run 'just package-esp' first"
    exit 1
fi

# Get discovered OVMF paths from ESP packaging stage
if [ ! -f out/esp/ovmf_paths.txt ]; then
    echo "❌ OVMF paths not found - run 'just package-esp' first"
    exit 1
fi

OVMF_CODE_PATH=$(sed -n '1p' out/esp/ovmf_paths.txt)
OVMF_VARS_PATH=$(sed -n '2p' out/esp/ovmf_paths.txt)

if [ ! -f "$OVMF_CODE_PATH" ] || [ ! -f "$OVMF_VARS_PATH" ]; then
    echo "❌ OVMF files not found at discovered paths:"
    echo "   CODE: $OVMF_CODE_PATH"
    echo "   VARS: $OVMF_VARS_PATH"
    exit 1
fi

echo "🚀 Using OVMF: $OVMF_CODE_PATH"

# Copy OVMF vars (writable) - use discovered paths
cp "$OVMF_VARS_PATH" out/qemu/OVMF_VARS_test.fd

# Launch QEMU with ESP and capture serial output using discovered paths
QT=${PG_QEMU_TIMEOUT:-60}
timeout ${QT}s qemu-system-x86_64 \
    -machine q35 \
    -cpu host \
    -enable-kvm \
    -m 2G \
    -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE_PATH" \
    -drive if=pflash,format=raw,file=out/qemu/OVMF_VARS_test.fd \
    -drive format=raw,file=out/esp/esp.img \
    -serial file:out/qemu/serial.log \
    -display none \
    -no-reboot || true

# Check for success marker in serial output
if grep -q "PhoenixGuard" out/qemu/serial.log; then
    TEST_RESULT="PASS"
    echo "✅ QEMU boot test PASSED"
else
    TEST_RESULT="FAIL"
    echo "❌ QEMU boot test FAILED"
fi

# Generate JUnit-style report
{
    echo '<?xml version="1.0" encoding="UTF-8"?>';
    echo '<testsuite name="PhoenixGuard QEMU Boot Test" tests="1" failures="'$([[ $TEST_RESULT == "FAIL" ]] && echo "1" || echo "0")'" time="60">';
    echo '  <testcase name="Production Boot Test" classname="PhoenixGuard.Boot">';
    [[ $TEST_RESULT == "FAIL" ]] && echo '    <failure message="Boot test failed">No PhoenixGuard marker found in serial output</failure>' || true;
    echo '  </testcase>';
    echo '</testsuite>';
} > out/qemu/report.xml

[ "$TEST_RESULT" == "PASS" ] || exit 1

