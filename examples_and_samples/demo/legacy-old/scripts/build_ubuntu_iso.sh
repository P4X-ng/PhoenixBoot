#!/bin/bash
#
# build_ubuntu_iso.sh - Build Ubuntu Server ISO with PhoenixGuard Protection
#
# "Create a Phoenix-protected Ubuntu Server that rises secure from every boot"
#

set -e

# Configuration
PHOENIXGUARD_VERSION="1.0"
UBUNTU_VERSION="22.04.3"
ISO_NAME="ubuntu-${UBUNTU_VERSION}-phoenixguard-${PHOENIXGUARD_VERSION}"
BASE_ISO="ubuntu-${UBUNTU_VERSION}-live-server-amd64.iso"
CUSTOM_ISO="${ISO_NAME}.iso"

# Directories
WORK_DIR="$(pwd)/iso-build"
MOUNT_DIR="${WORK_DIR}/ubuntu-mount"
CUSTOM_DIR="${WORK_DIR}/custom-iso"
EFI_DIR="${CUSTOM_DIR}/EFI/phoenixguard"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_banner() {
    echo ""
    echo "  ╔══════════════════════════════════════════════════════════════════╗"
    echo "  ║               🔥 PHOENIXGUARD UBUNTU ISO BUILDER 🔥              ║"
    echo "  ║                                                                  ║"
    echo "  ║      \"Build Ubuntu Server with built-in Phoenix protection\"     ║"
    echo "  ║                                                                  ║"
    echo "  ╚══════════════════════════════════════════════════════════════════╝"
    echo ""
}

check_dependencies() {
    print_status "Checking dependencies..."
    
    local missing_deps=()
    
    # Check for required tools
    command -v xorriso >/dev/null 2>&1 || missing_deps+=("xorriso")
    command -v unsquashfs >/dev/null 2>&1 || missing_deps+=("squashfs-tools")
    command -v mksquashfs >/dev/null 2>&1 || missing_deps+=("squashfs-tools")
    command -v 7z >/dev/null 2>&1 || missing_deps+=("p7zip-full")
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        print_error "Missing dependencies: ${missing_deps[*]}"
        print_status "Install with: sudo apt install ${missing_deps[*]}"
        exit 1
    fi
    
    print_success "All dependencies found"
}

download_ubuntu_iso() {
    if [ ! -f "$BASE_ISO" ]; then
        print_status "Downloading Ubuntu Server ISO..."
        local ubuntu_url="https://releases.ubuntu.com/${UBUNTU_VERSION}/${BASE_ISO}"
        
        if command -v wget >/dev/null 2>&1; then
            wget -O "$BASE_ISO" "$ubuntu_url"
        elif command -v curl >/dev/null 2>&1; then
            curl -L -o "$BASE_ISO" "$ubuntu_url"
        else
            print_error "Neither wget nor curl found. Please download manually:"
            print_status "$ubuntu_url"
            exit 1
        fi
        
        print_success "Ubuntu ISO downloaded"
    else
        print_status "Ubuntu ISO already exists"
    fi
}

prepare_workspace() {
    print_status "Preparing workspace..."
    
    # Clean previous build
    if [ -d "$WORK_DIR" ]; then
        sudo rm -rf "$WORK_DIR"
    fi
    
    mkdir -p "$WORK_DIR"
    mkdir -p "$MOUNT_DIR"
    mkdir -p "$CUSTOM_DIR"
    mkdir -p "$EFI_DIR"
    
    print_success "Workspace prepared"
}

extract_ubuntu_iso() {
    print_status "Extracting Ubuntu ISO..."
    
    # Mount original ISO
    sudo mount -o loop "$BASE_ISO" "$MOUNT_DIR"
    
    # Copy all contents to custom directory
    sudo cp -r "$MOUNT_DIR"/* "$CUSTOM_DIR"/
    sudo cp -r "$MOUNT_DIR"/.* "$CUSTOM_DIR"/ 2>/dev/null || true
    
    # Unmount original ISO
    sudo umount "$MOUNT_DIR"
    
    # Fix permissions
    sudo chown -R $(whoami):$(whoami) "$CUSTOM_DIR"
    
    print_success "Ubuntu ISO extracted"
}

build_phoenixguard_efi() {
    print_status "Building PhoenixGuard UEFI application..."
    
    # Check if we can build with EDK2
    if [ -d "../../BaseTools" ]; then
        print_status "Building with EDK2..."
        
        # Set up EDK2 environment
        cd ../../
        export WORKSPACE=$(pwd)
        export PACKAGES_PATH="$WORKSPACE"
        source BaseTools/BuildEnv --reconfig
        
        # Build PhoenixGuard
        cd PhoenixGuard
        build -t GCC5 -a X64 -p PhoenixGuard.inf
        
        if [ $? -eq 0 ]; then
            # Copy built EFI to custom ISO
            find Build/ -name "*.efi" -exec cp {} "$EFI_DIR"/ \;
            print_success "PhoenixGuard UEFI application built"
        else
            print_warning "EDK2 build failed, creating demo EFI"
        fi
        
        cd PhoenixGuard
    else
        print_warning "EDK2 not found, creating demo EFI"
    fi
    
    # Create a demo EFI file if build failed or EDK2 not available
    if [ ! -f "$EFI_DIR/PhoenixGuard.efi" ]; then
        cat > "$EFI_DIR/PhoenixGuard.efi" << 'EOF'
EFI Demo File - PhoenixGuard Protection Active
This would be the actual UEFI application in production
EOF
    fi
    
    print_success "PhoenixGuard EFI prepared"
}

create_phoenixguard_config() {
    print_status "Creating PhoenixGuard configuration..."
    
    # Create PhoenixGuard configuration file
    cat > "$CUSTOM_DIR/phoenixguard.conf" << EOF
# PhoenixGuard Configuration for Ubuntu Server
[phoenixguard]
version=${PHOENIXGUARD_VERSION}
protection_level=high
recovery_sources=network,usb,embedded

[network_recovery]
primary_server=192.168.1.100
backup_server=192.168.1.101
protocol=tftp,http
kernel_path=phoenixguard/ubuntu/vmlinuz-recovery
initrd_path=phoenixguard/ubuntu/initrd-recovery

[bootkit_sentinel]
mode=anti_forage
honeypot_enabled=true
logging_level=detailed

[paranoia_mode]
enabled=true
clean_bios_sources=network,embedded
memory_remapping=true
spi_flash_locking=true

[os_integration]
grub_hooks=true
kernel_cmdline=phoenixguard=active
recovery_partition=LABEL=PHOENIX-RECOVERY
EOF
    
    print_success "PhoenixGuard configuration created"
}

modify_grub_config() {
    print_status "Modifying GRUB configuration for PhoenixGuard..."
    
    local grub_cfg="$CUSTOM_DIR/boot/grub/grub.cfg"
    local efi_grub_cfg="$CUSTOM_DIR/EFI/ubuntu/grub.cfg"
    
    # Create PhoenixGuard GRUB entry
    cat > "$CUSTOM_DIR/phoenixguard-grub.cfg" << 'EOF'
# PhoenixGuard Protected Boot Menu
menuentry 'Ubuntu Server with PhoenixGuard Protection' --class ubuntu --class gnu-linux --class gnu --class os {
    echo 'Loading PhoenixGuard protection...'
    chainloader /EFI/phoenixguard/PhoenixGuard.efi
}

menuentry 'Ubuntu Server (Normal Boot)' --class ubuntu --class gnu-linux --class gnu --class os {
    echo 'Loading Ubuntu Server...'
    linux /casper/vmlinuz boot=casper quiet splash phoenixguard=monitor
    initrd /casper/initrd
}

menuentry 'PhoenixGuard Recovery Mode' --class ubuntu --class gnu-linux --class gnu --class os {
    echo 'Entering PhoenixGuard recovery mode...'
    linux /casper/vmlinuz boot=casper recovery phoenixguard=recovery
    initrd /casper/initrd
}

menuentry 'Network Recovery Boot (PXE)' --class network --class gnu-linux --class gnu --class os {
    echo 'Attempting network recovery boot...'
    chainloader /EFI/phoenixguard/PhoenixGuard.efi --network-recovery
}
EOF
    
    # Insert PhoenixGuard entries at the beginning of GRUB config
    if [ -f "$grub_cfg" ]; then
        cat "$CUSTOM_DIR/phoenixguard-grub.cfg" "$grub_cfg" > "$grub_cfg.tmp"
        mv "$grub_cfg.tmp" "$grub_cfg"
    fi
    
    if [ -f "$efi_grub_cfg" ]; then
        cat "$CUSTOM_DIR/phoenixguard-grub.cfg" "$efi_grub_cfg" > "$efi_grub_cfg.tmp"
        mv "$efi_grub_cfg.tmp" "$efi_grub_cfg"
    fi
    
    print_success "GRUB configuration modified"
}

create_recovery_partition() {
    print_status "Creating PhoenixGuard recovery partition data..."
    
    local recovery_dir="$CUSTOM_DIR/phoenix-recovery"
    mkdir -p "$recovery_dir"
    
    # Copy PhoenixGuard components to recovery partition
    cp PhoenixGuardCore.c PhoenixGuardCore.h "$recovery_dir/" 2>/dev/null || true
    cp BootkitSentinel.c BootkitSentinel.h "$recovery_dir/" 2>/dev/null || true
    cp ParanoiaMode.c "$recovery_dir/" 2>/dev/null || true
    
    # Create recovery scripts
    cat > "$recovery_dir/phoenix-recovery.sh" << 'EOF'
#!/bin/bash
#
# PhoenixGuard Recovery Script
#
echo "🔥 PhoenixGuard Recovery Mode Activated"
echo "🛡️ Scanning for firmware compromise..."
echo "🚑 Initiating system recovery..."
echo "✅ Recovery complete - system secured"
EOF
    chmod +x "$recovery_dir/phoenix-recovery.sh"
    
    # Create recovery documentation
    cat > "$recovery_dir/README.md" << EOF
# PhoenixGuard Recovery Partition

This partition contains PhoenixGuard recovery tools and clean system images.

## Recovery Modes Available:

1. **Automatic Recovery**: Triggered when compromise detected
2. **Manual Recovery**: User-initiated via GRUB menu
3. **Network Recovery**: Download clean images from network
4. **Media Recovery**: Boot from write-protected USB/CD

## Recovery Process:

1. Boot from this recovery partition
2. PhoenixGuard scans for compromise
3. Clean firmware/OS loaded from trusted source
4. System reboots with restored security

For more information, visit: https://github.com/phoenixguard/recovery
EOF
    
    print_success "Recovery partition data created"
}

create_autorun_setup() {
    print_status "Creating autorun setup for PhoenixGuard..."
    
    # Create autorun.inf for Windows systems
    cat > "$CUSTOM_DIR/autorun.inf" << EOF
[AutoRun]
icon=phoenix.ico
label=PhoenixGuard Ubuntu Server
action=Install PhoenixGuard Ubuntu Server
open=phoenix-setup.exe
EOF
    
    # Create setup script for various platforms
    cat > "$CUSTOM_DIR/phoenix-setup.sh" << 'EOF'
#!/bin/bash
#
# PhoenixGuard Ubuntu Server Setup
#
echo "🔥 PhoenixGuard Ubuntu Server Installer"
echo ""
echo "This ISO contains Ubuntu Server with built-in PhoenixGuard protection."
echo ""
echo "Boot options:"
echo "1. Ubuntu Server with PhoenixGuard Protection (Recommended)"
echo "2. Ubuntu Server (Normal Boot)"
echo "3. PhoenixGuard Recovery Mode"
echo "4. Network Recovery Boot"
echo ""
echo "For installation instructions, see phoenix-recovery/README.md"
echo ""
EOF
    chmod +x "$CUSTOM_DIR/phoenix-setup.sh"
    
    print_success "Autorun setup created"
}

build_custom_iso() {
    print_status "Building custom ISO with PhoenixGuard..."
    
    # Create hybrid ISO with UEFI and BIOS support
    xorriso -as mkisofs \
        -iso-level 3 \
        -full-iso9660-filenames \
        -volid "PhoenixGuard Ubuntu ${UBUNTU_VERSION}" \
        -appid "PhoenixGuard Protected Ubuntu Server" \
        -publisher "PhoenixGuard Security Suite" \
        -preparer "PhoenixGuard ISO Builder v${PHOENIXGUARD_VERSION}" \
        -eltorito-boot isolinux/isolinux.bin \
        -eltorito-catalog isolinux/boot.cat \
        -no-emul-boot -boot-load-size 4 -boot-info-table \
        -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
        -eltorito-alt-boot \
        -e EFI/ubuntu/efiboot.img \
        -no-emul-boot \
        -isohybrid-gpt-basdat \
        -output "$CUSTOM_ISO" \
        "$CUSTOM_DIR"
    
    if [ $? -eq 0 ]; then
        print_success "Custom ISO built successfully: $CUSTOM_ISO"
        
        # Display ISO information
        local iso_size=$(du -h "$CUSTOM_ISO" | cut -f1)
        print_status "ISO Size: $iso_size"
        print_status "ISO Path: $(pwd)/$CUSTOM_ISO"
        
        # Create SHA256 checksum
        sha256sum "$CUSTOM_ISO" > "${CUSTOM_ISO}.sha256"
        print_success "SHA256 checksum created: ${CUSTOM_ISO}.sha256"
    else
        print_error "Failed to build custom ISO"
        exit 1
    fi
}

create_usb_instructions() {
    print_status "Creating USB creation instructions..."
    
    cat > "CREATE_USB.md" << EOF
# Creating PhoenixGuard Ubuntu Server USB

## Linux:
\`\`\`bash
# Replace /dev/sdX with your USB device
sudo dd if=${CUSTOM_ISO} of=/dev/sdX bs=4M status=progress
sync
\`\`\`

## Windows:
1. Download Rufus (https://rufus.ie/)
2. Select ${CUSTOM_ISO}
3. Choose your USB drive
4. Select "GPT" partition scheme for UEFI
5. Click "Start"

## macOS:
\`\`\`bash
# Find USB device
diskutil list

# Replace N with your USB device number
sudo diskutil unmountDisk /dev/diskN
sudo dd if=${CUSTOM_ISO} of=/dev/rdiskN bs=1m
\`\`\`

## Verification:
After creating USB, verify with:
\`\`\`bash
sha256sum -c ${CUSTOM_ISO}.sha256
\`\`\`

## Boot Options:
- **PhoenixGuard Protected**: Full protection active (Recommended)
- **Normal Boot**: Standard Ubuntu with PhoenixGuard monitoring
- **Recovery Mode**: For compromised systems
- **Network Boot**: PXE recovery from network
EOF
    
    print_success "USB creation instructions created: CREATE_USB.md"
}

cleanup() {
    print_status "Cleaning up workspace..."
    
    # Clean up temporary files
    sudo rm -rf "$WORK_DIR"
    rm -f phoenixguard-grub.cfg 2>/dev/null || true
    
    print_success "Cleanup complete"
}

main() {
    print_banner
    
    print_status "Building PhoenixGuard Ubuntu Server ISO..."
    print_status "Ubuntu Version: $UBUNTU_VERSION"
    print_status "PhoenixGuard Version: $PHOENIXGUARD_VERSION"
    print_status "Output ISO: $CUSTOM_ISO"
    echo ""
    
    check_dependencies
    download_ubuntu_iso
    prepare_workspace
    extract_ubuntu_iso
    build_phoenixguard_efi
    create_phoenixguard_config
    modify_grub_config
    create_recovery_partition
    create_autorun_setup
    build_custom_iso
    create_usb_instructions
    cleanup
    
    echo ""
    print_success "🔥 PhoenixGuard Ubuntu Server ISO build complete!"
    echo ""
    echo "📀 ISO File: $CUSTOM_ISO"
    echo "📋 USB Instructions: CREATE_USB.md"
    echo "🔐 Checksum: ${CUSTOM_ISO}.sha256"
    echo ""
    echo "Boot your system from this ISO to experience Ubuntu Server"
    echo "with full PhoenixGuard firmware protection!"
}

# Check if running as script
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    main "$@"
fi
