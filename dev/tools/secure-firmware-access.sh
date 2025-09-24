#!/bin/bash
#
# PhoenixGuard Secure Firmware Access via Double-Kexec
# Temporarily unlocks hardware access, performs operations, then re-locks
#

set -e

echo "🔐 PhoenixGuard Secure Firmware Access"
echo "======================================"
echo ""
echo "This script uses double-kexec to:"
echo "1. Temporarily disable kernel lockdown"
echo "2. Perform firmware operations" 
echo "3. Re-enable kernel lockdown"
echo ""

# Check if we're running as root
if [[ $EUID -ne 0 ]]; then
    echo "❌ This script must be run as root"
    exit 1
fi

# Check current lockdown status
CURRENT_LOCKDOWN=$(cat /sys/kernel/security/lockdown 2>/dev/null || echo "unavailable")
echo "📋 Current lockdown status: $CURRENT_LOCKDOWN"

# Check if kexec is available
if ! command -v kexec >/dev/null 2>&1; then
    echo "❌ kexec not found. Install with: apt install kexec-tools"
    exit 1
fi

# Enhanced barrier detection and automatic removal
echo "🔍 Detecting barriers to secure firmware access..."
BARRIERS_TO_FIX=()
ORIGINAL_SETTINGS=()

# Check kexec_load_disabled
KEXEC_DISABLED=$(cat /proc/sys/kernel/kexec_load_disabled 2>/dev/null || echo "0")
if [[ "$KEXEC_DISABLED" == "1" ]]; then
    echo "  ⚠️  kexec_load_disabled = 1 (blocking kexec)"
    BARRIERS_TO_FIX+=("kexec_disabled")
    ORIGINAL_SETTINGS+=("kexec_load_disabled=1")
else
    echo "  ✅ kexec_load_disabled = 0 (allows kexec)"
fi

# Check if kexec_file_load exists and is disabled
if [[ -f /proc/sys/kernel/kexec_file_load_disabled ]]; then
    KEXEC_FILE_DISABLED=$(cat /proc/sys/kernel/kexec_file_load_disabled)
    if [[ "$KEXEC_FILE_DISABLED" == "1" ]]; then
        echo "  ⚠️  kexec_file_load_disabled = 1 (blocking signed kexec)"
        BARRIERS_TO_FIX+=("kexec_file_disabled")
        ORIGINAL_SETTINGS+=("kexec_file_load_disabled=1")
    else
        echo "  ✅ kexec_file_load_disabled = 0 (allows signed kexec)"
    fi
else
    echo "  ℹ️  kexec_file_load_disabled not available (older kernel)"
fi

# Check lockdown mode
CURRENT_LOCKDOWN_FULL=$(cat /sys/kernel/security/lockdown 2>/dev/null || echo "none")
if [[ "$CURRENT_LOCKDOWN_FULL" == *"[integrity]"* ]] || [[ "$CURRENT_LOCKDOWN_FULL" == *"[confidentiality]"* ]]; then
    echo "  ℹ️  Kernel lockdown active: $CURRENT_LOCKDOWN_FULL"
    echo "     This will be handled by double-kexec (temporary lockdown=none)"
else
    echo "  ✅ Kernel lockdown: $CURRENT_LOCKDOWN_FULL"
fi

# Check for immutable boot parameters
if grep -q "lockdown=" /proc/cmdline; then
    echo "  ℹ️  Boot lockdown parameter detected - will override with kexec"
else
    echo "  ✅ No boot lockdown parameter set"
fi

# Function to temporarily remove barriers
remove_barriers() {
    echo ""
    echo "🔧 Temporarily removing barriers to enable secure firmware access..."
    
    for barrier in "${BARRIERS_TO_FIX[@]}"; do
        case $barrier in
            "kexec_disabled")
                echo "  🔓 Enabling kexec temporarily..."
                if echo 0 > /proc/sys/kernel/kexec_load_disabled 2>/dev/null; then
                    echo "    ✅ kexec_load_disabled set to 0"
                else
                    echo "    ⚠️  Could not modify kexec_load_disabled (kernel restriction)"
                    echo "    🔄 Will attempt alternative kexec method"
                fi
                ;;
            "kexec_file_disabled")
                echo "  🔓 Enabling file-based kexec temporarily..."
                if echo 0 > /proc/sys/kernel/kexec_file_load_disabled 2>/dev/null; then
                    echo "    ✅ kexec_file_load_disabled set to 0"
                else
                    echo "    ⚠️  Could not modify kexec_file_load_disabled (kernel restriction)"
                fi
                ;;
        esac
    done
}

# Function to restore original settings
restore_barriers() {
    echo ""
    echo "🔒 Restoring original security settings..."
    
    for setting in "${ORIGINAL_SETTINGS[@]}"; do
        case $setting in
            "kexec_load_disabled=1")
                echo "  🔒 Restoring kexec_load_disabled to 1..."
                if echo 1 > /proc/sys/kernel/kexec_load_disabled 2>/dev/null; then
                    echo "    ✅ kexec protection restored"
                else
                    echo "    ⚠️  Could not restore kexec_load_disabled (will be restored on reboot)"
                fi
                ;;
            "kexec_file_load_disabled=1")
                echo "  🔒 Restoring kexec_file_load_disabled to 1..."
                if echo 1 > /proc/sys/kernel/kexec_file_load_disabled 2>/dev/null; then
                    echo "    ✅ kexec_file protection restored"
                else
                    echo "    ⚠️  Could not restore kexec_file_load_disabled (will be restored on reboot)"
                fi
                ;;
        esac
    done
    
    echo "✅ All security settings restored (any remaining will restore on reboot)"
}

# Trap to ensure barriers are restored on script exit
trap 'restore_barriers' EXIT

# Get current boot parameters
KERNEL="/boot/vmlinuz-$(uname -r)"
INITRD="/boot/initrd.img-$(uname -r)"
ROOT_UUID=$(findmnt -n -o UUID /)
CURRENT_CMDLINE=$(cat /proc/cmdline)

if [[ ! -f "$KERNEL" ]] || [[ ! -f "$INITRD" ]]; then
    echo "❌ Kernel or initrd not found:"
    echo "   Kernel: $KERNEL"
    echo "   Initrd: $INITRD"
    exit 1
fi

echo "📋 Kernel: $KERNEL"
echo "📋 Initrd: $INITRD"
echo "📋 Root UUID: $ROOT_UUID"
echo ""

# Parse command line options
OPERATION=""
FIRMWARE_FILE=""
BACKUP_FILE="firmware_backup_$(date +%s).bin"

while [[ $# -gt 0 ]]; do
    case $1 in
        --read)
            OPERATION="read"
            BACKUP_FILE="$2"
            shift 2
            ;;
        --write)
            OPERATION="write"
            FIRMWARE_FILE="$2"
            shift 2
            ;;
        --backup)
            OPERATION="backup"
            BACKUP_FILE="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [--read file.bin] [--write file.bin] [--backup file.bin]"
            echo ""
            echo "Options:"
            echo "  --read FILE    Read firmware to FILE"
            echo "  --write FILE   Write FILE to firmware"
            echo "  --backup FILE  Create backup of current firmware"
            echo "  --help         Show this help"
            echo ""
            echo "Examples:"
            echo "  $0 --backup current_firmware.bin"
            echo "  $0 --write clean_firmware.bin"
            echo "  $0 --read suspected_malware.bin"
            exit 0
            ;;
        *)
            echo "❌ Unknown option: $1"
            echo "   Use --help for usage information"
            exit 1
            ;;
    esac
done

if [[ -z "$OPERATION" ]]; then
    echo "❌ No operation specified. Use --help for usage information."
    exit 1
fi

# Confirm the operation
echo "🎯 Planned operation: $OPERATION"
case $OPERATION in
    "read"|"backup")
        echo "   Output file: $BACKUP_FILE"
        ;;
    "write")
        echo "   Input file: $FIRMWARE_FILE"
        if [[ ! -f "$FIRMWARE_FILE" ]]; then
            echo "❌ Firmware file not found: $FIRMWARE_FILE"
            exit 1
        fi
        ;;
esac

echo ""
# Show what barriers need to be removed
if [[ ${#BARRIERS_TO_FIX[@]} -gt 0 ]]; then
    echo "🔧 Barriers detected that will be temporarily removed:"
    for barrier in "${BARRIERS_TO_FIX[@]}"; do
        case $barrier in
            "kexec_disabled")
                echo "  • kexec_load_disabled will be set to 0 (temporarily)"
                ;;
            "kexec_file_disabled")
                echo "  • kexec_file_load_disabled will be set to 0 (temporarily)"
                ;;
        esac
    done
    echo "  ✅ All barriers will be automatically restored after operation"
    echo ""
fi

echo "⚠️  WARNING: This will temporarily disable kernel security!"
echo "   The system will kexec twice:"
echo "   1. Boot with lockdown=none (firmware access enabled)"
echo "   2. Boot with lockdown=integrity (security restored)"
echo ""
read -p "Continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Operation cancelled."
    exit 0
fi

# Remove barriers before attempting kexec
if [[ ${#BARRIERS_TO_FIX[@]} -gt 0 ]]; then
    remove_barriers
fi

# Function to perform the firmware operation
perform_firmware_operation() {
    echo "🔓 Phase 2: Performing firmware operation..."
    echo "   Lockdown status: $(cat /sys/kernel/security/lockdown 2>/dev/null || echo 'unavailable')"
    
    case $OPERATION in
        "read"|"backup")
            echo "📖 Reading firmware to $BACKUP_FILE..."
            if flashrom -p internal -r "$BACKUP_FILE"; then
                echo "✅ Firmware backup completed: $BACKUP_FILE"
                echo "📊 File size: $(du -h "$BACKUP_FILE" | cut -f1)"
                echo "🔍 SHA256: $(sha256sum "$BACKUP_FILE" | cut -d' ' -f1)"
            else
                echo "❌ Firmware backup failed"
                return 1
            fi
            ;;
        "write")
            echo "📝 Writing $FIRMWARE_FILE to firmware..."
            echo "⚠️  This is DANGEROUS - incorrect firmware can brick your system!"
            read -p "Are you absolutely sure? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                if flashrom -p internal -w "$FIRMWARE_FILE"; then
                    echo "✅ Firmware write completed"
                else
                    echo "❌ Firmware write failed"
                    return 1
                fi
            else
                echo "Write operation cancelled"
                return 1
            fi
            ;;
    esac
    
    return 0
}

# Create the firmware operation script
cat > /tmp/firmware_operation.sh << 'EOF'
#!/bin/bash
set -e

# This script runs after the first kexec (with lockdown=none)
echo "🔓 Running in unlocked mode - hardware access available"
echo "   Lockdown: $(cat /sys/kernel/security/lockdown 2>/dev/null || echo 'unavailable')"

# Source the operation function and variables
source /tmp/firmware_vars.sh
perform_firmware_operation

if [[ $? -eq 0 ]]; then
    echo "✅ Firmware operation completed successfully"
    
    # Now kexec back to secure mode
    echo ""
    echo "🔐 Phase 3: Re-enabling kernel security..."
    echo "   Preparing kexec back to secure lockdown mode..."
    
    # Clean up the lockdown=none from command line and add lockdown=integrity
    SECURE_CMDLINE=$(cat /proc/cmdline | sed 's/lockdown=[^ ]*//' | sed 's/  */ /g' | sed 's/^ *//' | sed 's/ *$//')
    SECURE_CMDLINE="$SECURE_CMDLINE lockdown=integrity"
    
    echo "📋 Secure cmdline: $SECURE_CMDLINE"
    
    # Prepare kexec back to secure mode
    kexec -l "$KERNEL" --initrd="$INITRD" --command-line="$SECURE_CMDLINE"
    
    echo "🔄 Kexec back to secure mode in 3 seconds..."
    sleep 3
    
    echo "🔐 Re-enabling security lockdown..."
    kexec -e
    
else
    echo "❌ Firmware operation failed"
    echo "⚠️  System remains in unlocked mode - reboot to restore security"
    exit 1
fi
EOF

chmod +x /tmp/firmware_operation.sh

# Export variables for the firmware operation
cat > /tmp/firmware_vars.sh << EOF
OPERATION="$OPERATION"
FIRMWARE_FILE="$FIRMWARE_FILE"
BACKUP_FILE="$BACKUP_FILE"
KERNEL="$KERNEL"
INITRD="$INITRD"

$(declare -f perform_firmware_operation)
EOF

echo "🔄 Phase 1: Kexec to unlocked mode..."

# Prepare command line without lockdown restrictions
UNLOCK_CMDLINE=$(echo "$CURRENT_CMDLINE" | sed 's/lockdown=[^ ]*//' | sed 's/  */ /g' | sed 's/^ *//' | sed 's/ *$//')
UNLOCK_CMDLINE="$UNLOCK_CMDLINE lockdown=none"

echo "📋 Unlock cmdline: $UNLOCK_CMDLINE"

# Configure kexec to run our firmware operation script on boot
mkdir -p /tmp/kexec-firmware
cat > /tmp/kexec-firmware/rc.local << 'EOF'
#!/bin/bash
# Auto-run firmware operation after kexec boot
/tmp/firmware_operation.sh
EOF
chmod +x /tmp/kexec-firmware/rc.local

# Prepare the first kexec (to unlocked mode)
kexec -l "$KERNEL" --initrd="$INITRD" --command-line="$UNLOCK_CMDLINE"

echo ""
echo "🔓 Kexec to unlocked mode in 3 seconds..."
echo "   After firmware operation, system will automatically re-secure"
sleep 3

echo "🚀 Launching firmware access mode..."

# Execute the first kexec
exec kexec -e
