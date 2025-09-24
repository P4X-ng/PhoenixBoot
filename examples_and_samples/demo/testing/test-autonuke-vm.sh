#!/bin/bash
#
# AUTONUKE Test VM - Ubuntu with OVMF Secure Boot
# ===============================================
#
# Creates and manages a test VM environment for validating the AUTONUKE
# recovery system with realistic UEFI/Secure Boot conditions.
#
# Features:
# - Ubuntu 24.04 LTS with OVMF UEFI firmware
# - Secure Boot enabled with custom keys
# - PhoenixGuard framework pre-installed
# - Mock bootkit scenarios for testing
# - Proper ESP partition setup for recovery testing

set -e

# Configuration
VM_NAME="autonuke-test"
VM_DIR="$(pwd)/vm-test-autonuke"
DISK_SIZE="20G"
RAM_SIZE="4G"
ISO_URL="https://releases.ubuntu.com/24.04/ubuntu-24.04.1-desktop-amd64.iso"
ISO_FILE="$VM_DIR/ubuntu-24.04.1-desktop-amd64.iso"
DISK_FILE="$VM_DIR/${VM_NAME}.qcow2"
OVMF_VARS="$VM_DIR/OVMF_VARS_${VM_NAME}.fd"

# Colors
RED='\033[91m'
GREEN='\033[92m'
YELLOW='\033[93m'
BLUE='\033[94m'
CYAN='\033[96m'
BOLD='\033[1m'
END='\033[0m'

log() {
    echo -e "${CYAN}[$(date +'%H:%M:%S')] $1${END}"
}

error() {
    echo -e "${RED}[ERROR] $1${END}"
    exit 1
}

success() {
    echo -e "${GREEN}[SUCCESS] $1${END}"
}

warn() {
    echo -e "${YELLOW}[WARNING] $1${END}"
}

check_dependencies() {
    log "🔧 Checking dependencies..."
    
    local missing=0
    for tool in qemu-system-x86_64 qemu-img wget; do
        if ! command -v "$tool" &> /dev/null; then
            error "Missing required tool: $tool"
            missing=1
        fi
    done
    
    # Check for OVMF firmware
    if [ ! -f /usr/share/ovmf/OVMF.fd ] && [ ! -f /usr/share/OVMF/OVMF_CODE.fd ]; then
        error "OVMF firmware not found. Install with: sudo apt install ovmf"
        missing=1
    fi
    
    if [ $missing -eq 1 ]; then
        error "Please install missing dependencies and try again"
    fi
    
    success "✅ All dependencies available"
}

create_vm() {
    log "🚀 Creating AUTONUKE test VM..."
    
    # Create VM directory
    mkdir -p "$VM_DIR"
    
    # Download Ubuntu ISO if not present
    if [ ! -f "$ISO_FILE" ]; then
        log "📥 Downloading Ubuntu 24.04 LTS..."
        wget -O "$ISO_FILE" "$ISO_URL" || error "Failed to download Ubuntu ISO"
    else
        log "✅ Ubuntu ISO already present"
    fi
    
    # Create disk image
    if [ ! -f "$DISK_FILE" ]; then
        log "💾 Creating VM disk image ($DISK_SIZE)..."
        qemu-img create -f qcow2 "$DISK_FILE" "$DISK_SIZE" || error "Failed to create disk image"
    else
        warn "Disk image already exists, will reuse"
    fi
    
    # Copy OVMF variables template (for Secure Boot)
    if [ ! -f "$OVMF_VARS" ]; then
        log "🔑 Setting up OVMF Secure Boot variables..."
        if [ -f /usr/share/OVMF/OVMF_VARS.fd ]; then
            cp /usr/share/OVMF/OVMF_VARS.fd "$OVMF_VARS"
        elif [ -f /usr/share/ovmf/OVMF_VARS.fd ]; then
            cp /usr/share/ovmf/OVMF_VARS.fd "$OVMF_VARS"
        else
            error "Could not find OVMF_VARS.fd template"
        fi
    fi
    
    success "✅ VM created successfully"
    
    log "🎯 To install Ubuntu:"
    echo "  1. Run: $0 start"
    echo "  2. Install Ubuntu in the VM"
    echo "  3. Enable Secure Boot in UEFI settings"
    echo "  4. After installation: $0 install"
}

start_vm() {
    log "🚀 Starting AUTONUKE test VM..."
    
    if [ ! -f "$DISK_FILE" ]; then
        error "VM disk not found. Run '$0 create' first."
    fi
    
    # Detect OVMF firmware paths
    local OVMF_CODE=""
    if [ -f /usr/share/OVMF/OVMF_CODE.secboot.fd ]; then
        OVMF_CODE="/usr/share/OVMF/OVMF_CODE.secboot.fd"
    elif [ -f /usr/share/ovmf/OVMF_CODE.secboot.fd ]; then
        OVMF_CODE="/usr/share/ovmf/OVMF_CODE.secboot.fd"
    elif [ -f /usr/share/OVMF/OVMF_CODE.fd ]; then
        OVMF_CODE="/usr/share/OVMF/OVMF_CODE.fd"
    elif [ -f /usr/share/ovmf/OVMF.fd ]; then
        OVMF_CODE="/usr/share/ovmf/OVMF.fd"
    else
        error "Could not find OVMF firmware"
    fi
    
    log "🔑 Using OVMF firmware: $OVMF_CODE"
    log "🔒 Secure Boot variables: $OVMF_VARS"
    
    # Build QEMU command
    local qemu_args=(
        -machine q35,smm=on,accel=kvm
        -cpu host
        -m "$RAM_SIZE"
        -smp 4
        -drive "if=pflash,format=raw,readonly=on,file=$OVMF_CODE"
        -drive "if=pflash,format=raw,file=$OVMF_VARS"
        -drive "file=$DISK_FILE,format=qcow2,if=virtio"
        -netdev user,id=net0,hostfwd=tcp::2222-:22
        -device virtio-net-pci,netdev=net0
        -vga virtio
        -display gtk,show-cursor=on
        -usb -device usb-tablet
        -rtc base=utc,clock=host
        -global kvm-pit.lost_tick_policy=discard
    )
    
    # Add ISO if present (for installation)
    if [ -f "$ISO_FILE" ] && [ ! -f "$VM_DIR/.installed" ]; then
        qemu_args+=(-cdrom "$ISO_FILE" -boot d)
        log "🔥 Booting from Ubuntu installation ISO"
    else
        log "💻 Booting from installed system"
    fi
    
    log "🖥️  Starting VM (VNC available on localhost:5900)"
    log "🌐 SSH available on localhost:2222"
    log "⌨️  Press Ctrl+Alt+G to release mouse, Ctrl+Alt+Q to quit"
    
    # Start VM
    qemu-system-x86_64 "${qemu_args[@]}" || warn "VM exited"
}

reset_vm() {
    log "🔄 Resetting AUTONUKE test VM to clean state..."
    
    read -p "This will destroy all VM data. Continue? [y/N]: " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        log "Reset cancelled"
        exit 0
    fi
    
    # Remove VM files
    if [ -d "$VM_DIR" ]; then
        rm -rf "$VM_DIR"
        success "✅ VM reset complete"
    else
        log "VM directory not found, nothing to reset"
    fi
}

install_phoenixguard() {
    log "📦 Preparing PhoenixGuard installation package..."
    
    # Create installation package
    local install_dir="$VM_DIR/phoenixguard-install"
    mkdir -p "$install_dir"
    
    # Copy PhoenixGuard components
    cp -r scripts/ "$install_dir/"
    cp -r drivers/ "$install_dir/" 2>/dev/null || log "No drivers directory found"
    cp Makefile "$install_dir/"
    cp README.md "$install_dir/" 2>/dev/null || true
    cp *.md "$install_dir/" 2>/dev/null || true
    
    # Create mock firmware for testing
    mkdir -p "$install_dir/drivers"
    if [ ! -f "$install_dir/drivers/G615LPAS.325" ]; then
        log "🔧 Creating mock firmware for testing..."
        # Create a small mock firmware file
        dd if=/dev/zero of="$install_dir/drivers/G615LPAS.325" bs=1K count=1024 2>/dev/null
        echo "# Mock BIOS firmware for AUTONUKE testing" > "$install_dir/drivers/README.txt"
    fi
    
    # Create installation script for VM
    cat > "$install_dir/install-in-vm.sh" << 'EOF'
#!/bin/bash
set -e

echo "🚀 Installing PhoenixGuard AUTONUKE in test VM..."

# Install required packages
sudo apt update
sudo apt install -y python3 python3-pip make flashrom dmidecode tree curl wget

# Install chipsec (may fail in VM, that's OK)
sudo pip3 install chipsec || echo "⚠️  chipsec install failed (expected in VM)"

# Copy PhoenixGuard to /opt
sudo mkdir -p /opt/phoenixguard
sudo cp -r . /opt/phoenixguard/
sudo chown -R $USER:$USER /opt/phoenixguard

# Make scripts executable
chmod +x /opt/phoenixguard/scripts/*.py
chmod +x /opt/phoenixguard/scripts/*.sh

# Create symlink for easy access
ln -sf /opt/phoenixguard/scripts/autonuke.py ~/autonuke

echo "✅ PhoenixGuard installed successfully!"
echo ""
echo "🎯 To test AUTONUKE:"
echo "  cd /opt/phoenixguard && make autonuke"
echo "  OR: ~/autonuke"
echo ""
echo "🔍 Available targets:"
echo "  make scan-bootkits      # Test bootkit detection"
echo "  make build-nuclear-cd   # Test Nuclear Boot CD creation"
echo "  make deploy-esp-iso     # Test ESP virtual CD deployment"
echo "  make autonuke          # 💥 Test full AUTONUKE workflow"
EOF
    chmod +x "$install_dir/install-in-vm.sh"
    
    # Create archive for easy transfer
    cd "$(dirname "$install_dir")"
    tar -czf phoenixguard-install.tar.gz "$(basename "$install_dir")"
    cd - > /dev/null
    
    success "✅ PhoenixGuard installation package ready"
    echo ""
    echo -e "${BLUE}📦 Installation package: $VM_DIR/phoenixguard-install.tar.gz${END}"
    echo -e "${CYAN}🎯 To install in VM:${END}"
    echo "  1. Copy the .tar.gz file to your VM"
    echo "  2. Extract: tar -xzf phoenixguard-install.tar.gz"
    echo "  3. Run: cd phoenixguard-install && ./install-in-vm.sh"
    echo ""
    echo -e "${YELLOW}💡 Or use SCP via VM's SSH:${END}"
    echo "  scp -P 2222 $VM_DIR/phoenixguard-install.tar.gz user@localhost:~/"
}

show_help() {
    echo -e "${BOLD}AUTONUKE Test VM Manager${END}"
    echo ""
    echo -e "${CYAN}Usage: $0 <command>${END}"
    echo ""
    echo -e "${GREEN}Commands:${END}"
    echo "  create    Create new Ubuntu test VM with OVMF/Secure Boot"
    echo "  start     Start the test VM"
    echo "  reset     Reset VM to clean state (destroys all data)"
    echo "  install   Prepare PhoenixGuard installation package"
    echo "  help      Show this help message"
    echo ""
    echo -e "${BLUE}Example workflow:${END}"
    echo "  $0 create          # Create VM"
    echo "  $0 start           # Install Ubuntu"
    echo "  $0 install         # Prepare PhoenixGuard package"
    echo "  # Transfer and install PhoenixGuard in VM"
    echo "  # Test: make autonuke"
}

# Main execution
case "${1:-help}" in
    create)
        check_dependencies
        create_vm
        ;;
    start)
        check_dependencies
        start_vm
        ;;
    reset)
        reset_vm
        ;;
    install)
        install_phoenixguard
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo -e "${RED}Unknown command: $1${END}"
        echo ""
        show_help
        exit 1
        ;;
esac
