#!/usr/bin/env bash
set -euo pipefail

# PhoenixGuard Nuclear Boot Test Script
# =====================================

log() { echo "[nuclear-test] $*"; }

# Setup test environment
setup_test_env() {
    local test_dir="/tmp/phoenixguard-test-$$"
    
    log "🚀 Setting up test environment: $test_dir"
    
    mkdir -p "$test_dir/EFI/BOOT"
    mkdir -p "$test_dir/EFI/PhoenixGuard"
    
    # Copy our Nuclear Boot application
    cp NuclearBootEdk2.efi "$test_dir/EFI/BOOT/BOOTX64.EFI"  # Auto-boot
    cp NuclearBootEdk2.efi "$test_dir/EFI/PhoenixGuard/"
    
    # Copy GRUB for the 'G' option test
    if [[ -f /boot/efi/EFI/PhoenixGuard/grubx64.efi ]]; then
        cp /boot/efi/EFI/PhoenixGuard/grubx64.efi "$test_dir/EFI/PhoenixGuard/"
        log "✅ Copied GRUB for testing 'G' option"
    fi
    
    # Create a simple shell script that will auto-run
    cat > "$test_dir/startup.nsh" <<'EOF'
@echo off
echo PhoenixGuard Nuclear Boot Test Environment
echo ==========================================
echo.
echo Starting Nuclear Boot Application...
echo.
EFI\BOOT\BOOTX64.EFI
EOF
    
    echo "$test_dir"
}

# Launch QEMU test
launch_test() {
    local test_dir="$1"
    
    log "🔥 Launching QEMU with Nuclear Boot..."
    log "💡 In the QEMU window:"
    log "   - Should auto-boot to Nuclear Boot application"
    log "   - Press 'G' to test Clean GRUB path"  
    log "   - Press Enter to see the Nuclear Boot demo"
    log "   - Close window or Ctrl+Alt+Q to quit"
    
    # Create writable OVMF vars
    local vars_file="/tmp/OVMF_VARS_test_$$.fd"
    log "📋 Creating OVMF variables file..."
    cp /usr/share/OVMF/OVMF_VARS_4M.fd "$vars_file"
    
    echo
    read -p "Press Enter to launch QEMU test..."
    
    # Launch QEMU with better settings
    qemu-system-x86_64 \
        -machine type=q35 \
        -cpu host \
        -enable-kvm \
        -m 2048 \
        -smp 2 \
        -drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd \
        -drive if=pflash,format=raw,file="$vars_file" \
        -drive file=fat:rw:"$test_dir",format=raw,if=ide \
        -netdev user,id=net0 \
        -device rtl8139,netdev=net0 \
        -vga std \
        -display gtk,show-cursor=on \
        -name "PhoenixGuard Nuclear Boot Test" \
        -no-reboot
    
    # Cleanup
    rm -f "$vars_file"
    rm -rf "$test_dir"
    
    log "✅ Test completed"
}

# Manual UEFI shell instructions
show_manual_instructions() {
    cat <<'EOF'

📋 Manual UEFI Shell Instructions
=================================

If you get dropped into the UEFI shell, try these commands:

1. List available filesystems:
   map

2. Switch to the FAT filesystem (usually fs0:):
   fs0:

3. Navigate to our application:
   cd EFI\PhoenixGuard

4. Run Nuclear Boot:
   NuclearBootEdk2.efi

5. Or try the auto-boot version:
   cd \EFI\BOOT
   BOOTX64.EFI

Alternative - if you see multiple filesystem options:
   fs1:
   cd EFI\PhoenixGuard
   NuclearBootEdk2.efi

EOF
}

# Check dependencies
check_deps() {
    if ! command -v qemu-system-x86_64 >/dev/null; then
        log "❌ QEMU not found. Install with: sudo apt install qemu-system-x86"
        exit 1
    fi
    
    if [[ ! -f /usr/share/OVMF/OVMF_CODE_4M.fd ]]; then
        log "❌ OVMF not found. Install with: sudo apt install ovmf"
        exit 1
    fi
    
    if [[ ! -f NuclearBootEdk2.efi ]]; then
        log "❌ NuclearBootEdk2.efi not found. Build it first with:"
        log "   ./build-nuclear-boot-edk2.sh"
        exit 1
    fi
    
    log "✅ Dependencies check passed"
}

# Main execution
main() {
    log "🦀🔥 PhoenixGuard Nuclear Boot Test 🔥🦀"
    
    check_deps
    
    case "${1:-auto}" in
        auto|test)
            local test_dir
            test_dir=$(setup_test_env)
            launch_test "$test_dir"
            ;;
        manual|help)
            show_manual_instructions
            ;;
        *)
            log "Usage: $0 [auto|manual]"
            log "  auto   - Launch QEMU test (default)"
            log "  manual - Show manual UEFI shell instructions"
            ;;
    esac
}

main "$@"
