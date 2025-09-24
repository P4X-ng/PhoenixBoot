#!/usr/bin/env bash
# Description: Enrolls Secure Boot keys into OVMF via QEMU without sudo.

set -euo pipefail
mkdir -p out/qemu

[ -f out/setup/ovmf_code_path ] || { echo "❌ Missing OVMF discovery; run 'just setup'"; exit 1; }
OVMF_CODE_PATH=$(cat out/setup/ovmf_code_path)
OVMF_VARS_PATH=$(cat out/setup/ovmf_vars_path)

cp "$OVMF_VARS_PATH" out/qemu/OVMF_VARS_enroll.fd

echo "🚀 Enrolling keys into OVMF using $OVMF_CODE_PATH (no sudo)"
QT=${PG_QEMU_TIMEOUT:-120}
timeout -k 5 ${QT}s qemu-system-x86_64 \
    -machine q35 -cpu host -enable-kvm -m 512 \
    -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE_PATH" \
    -drive if=pflash,format=raw,file=out/qemu/OVMF_VARS_enroll.fd \
    -drive format=raw,file=out/esp/enroll-esp.img \
    -serial file:out/qemu/enroll.log -display none -no-reboot || true

cp out/qemu/OVMF_VARS_enroll.fd out/qemu/OVMF_VARS_custom.fd
echo "✅ Persisted OVMF VARS at out/qemu/OVMF_VARS_custom.fd"

