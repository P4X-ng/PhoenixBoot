#!/bin/bash

# PhoenixGuard CloudBoot VM Test Setup
# This script creates a VM environment to test the HTTPS-only boot system

set -e

echo "🔥 PhoenixGuard CloudBoot VM Test Setup 🔥"
echo "==========================================="

# Create test directory
TEST_DIR="$HOME/Desktop/edk2-bootkit-defense/PhoenixGuard/vm-test"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"

echo "📁 Creating VM test environment in: $TEST_DIR"

# Create a minimal disk image
echo "💾 Creating VM disk image..."
qemu-img create -f qcow2 test-vm.qcow2 1G

# Download a minimal Ubuntu ISO for testing (if not exists)
ISO_URL="https://releases.ubuntu.com/24.04/ubuntu-24.04.1-live-server-amd64.iso"
ISO_FILE="ubuntu-24.04.1-live-server-amd64.iso"

if [ ! -f "$ISO_FILE" ]; then
    echo "⬇️  Downloading Ubuntu 24.04 LTS Server ISO..."
    echo "Note: This is a large download (~2GB). Press Ctrl+C to cancel if needed."
    sleep 3
    wget -O "$ISO_FILE" "$ISO_URL" || {
        echo "❌ Download failed. You can manually download from:"
        echo "   $ISO_URL"
        echo "   and place it in: $TEST_DIR/$ISO_FILE"
        echo ""
        echo "Or we can test with network boot only (PXE)."
        read -p "Continue without ISO? (y/n): " -n 1 -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
        echo ""
    }
fi

# Create UEFI variables file
echo "🔧 Setting up UEFI environment..."
cp /usr/share/OVMF/OVMF_VARS.fd OVMF_VARS_test.fd 2>/dev/null || {
    # Alternative location
    cp /usr/share/ovmf/OVMF.fd OVMF_VARS_test.fd 2>/dev/null || {
        echo "⚠️  Could not find OVMF variables file. Creating empty one."
        touch OVMF_VARS_test.fd
    }
}

# Create VM startup script
cat > start-test-vm.sh << 'EOF'
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
EOF

chmod +x start-test-vm.sh

# Create network boot test script
cat > test-network-boot.sh << 'EOF'
#!/bin/bash

# PhoenixGuard Network Boot Test
echo "🌐 Starting PhoenixGuard Network Boot Test..."

VM_DIR="$(dirname "$0")"
cd "$VM_DIR"

# Start a simple HTTP server for testing
echo "🚀 Starting test HTTP server on port 8000..."

# Create test boot files
mkdir -p boot-server/api/v1/boot/ubuntu/latest

# Create dummy kernel and initrd for testing
echo "Test kernel content" > boot-server/api/v1/boot/ubuntu/latest/kernel
echo "Test initrd content" > boot-server/api/v1/boot/ubuntu/latest/initrd

# Create index page
cat > boot-server/index.html << 'BOOTEOF'
<!DOCTYPE html>
<html>
<head>
    <title>PhoenixGuard CloudBoot Test Server</title>
</head>
<body>
    <h1>🔥 PhoenixGuard CloudBoot Test Server 🔥</h1>
    <p>This is a test server for PhoenixGuard HTTPS-only boot.</p>
    <h2>Available Endpoints:</h2>
    <ul>
        <li><a href="/api/v1/boot/ubuntu/latest/kernel">Ubuntu Latest Kernel</a></li>
        <li><a href="/api/v1/boot/ubuntu/latest/initrd">Ubuntu Latest InitRD</a></li>
    </ul>
    <p><strong>Note:</strong> This is a test server. In production, use HTTPS with proper certificates.</p>
</body>
</html>
BOOTEOF

# Start Python HTTP server in background
cd boot-server
echo "📡 Starting HTTP server at http://localhost:8000"
python3 -m http.server 8000 &
SERVER_PID=$!
cd ..

echo "🌐 Test server started (PID: $SERVER_PID)"
echo "📡 You can test endpoints:"
echo "   http://localhost:8000/api/v1/boot/ubuntu/latest/kernel"
echo "   http://localhost:8000/api/v1/boot/ubuntu/latest/initrd"
echo ""
echo "Press Ctrl+C to stop the server"

# Keep server running
trap "echo '🛑 Stopping server...'; kill $SERVER_PID 2>/dev/null; exit 0" INT TERM

wait $SERVER_PID
EOF

chmod +x test-network-boot.sh

echo ""
echo "✅ VM Test Environment Setup Complete!"
echo ""
echo "📋 Available test scripts:"
echo "   ./start-test-vm.sh       - Start VM with UEFI support"
echo "   ./test-network-boot.sh   - Test network boot server"
echo ""
echo "🔥 Test Scenarios:"
echo "1. Standard VM boot with Ubuntu ISO"
echo "2. Network boot testing with local HTTP server"
echo "3. UEFI firmware behavior analysis"
echo "4. PhoenixGuard integration testing"
echo ""
echo "🚀 To start testing:"
echo "   cd $TEST_DIR"
echo "   ./start-test-vm.sh"
echo ""
echo "🌐 To test network boot:"
echo "   cd $TEST_DIR"
echo "   ./test-network-boot.sh    # In one terminal"
echo "   ./start-test-vm.sh        # In another terminal"
echo ""

cd "$TEST_DIR"
ls -la
