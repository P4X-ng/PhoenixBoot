#!/bin/bash

# PhoenixGuard CloudBoot VM Test
echo "🚀 Starting PhoenixGuard Test VM..."

VM_DIR="$(dirname "$0")"
cd "$VM_DIR"

# VM configuration
VM_NAME="PhoenixGuard-Test"
MEMORY="2048"
DISK="test-vm.qcow2"
ISO="ubuntu-24.04.1-live-server-amd64.iso"

# UEFI firmware paths
OVMF_CODE="/usr/share/OVMF/OVMF_CODE_4M.fd"
OVMF_VARS="OVMF_VARS_test.fd"

# Alternative OVMF paths for different distros
if [ ! -f "$OVMF_CODE" ]; then
    OVMF_CODE="/usr/share/ovmf/x64/OVMF_CODE.fd"
fi

echo "💻 VM Configuration:"
echo "   Name: $VM_NAME"
echo "   Memory: ${MEMORY}MB"
echo "   Disk: $DISK"
echo "   ISO: $ISO"
echo "   UEFI Code: $OVMF_CODE"
echo "   UEFI Vars: $OVMF_VARS"
echo ""

# Check if ISO exists
if [ -f "$ISO" ]; then
    ISO_OPTION="-cdrom $ISO"
    echo "📀 ISO found - will boot from ISO"
else
    ISO_OPTION=""
    echo "🌐 No ISO - will attempt network boot"
fi

# Start VM with UEFI support
qemu-system-x86_64 \
    -name "$VM_NAME" \
    -machine type=q35,accel=kvm:tcg \
    -m "$MEMORY" \
    -smp cpus=2 \
    -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
    -drive if=pflash,format=raw,file="$OVMF_VARS" \
    -drive file="$DISK",format=qcow2,if=virtio \
    $ISO_OPTION \
    -netdev user,id=net0,hostfwd=tcp::8080-:80,hostfwd=tcp::8443-:443 \
    -device virtio-net,netdev=net0 \
    -vga virtio \
    -display gtk,grab-on-hover=on \
    -boot order=cdn \
    -enable-kvm \
    "$@"
