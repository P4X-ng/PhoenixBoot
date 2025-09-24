#!/bin/bash
# hardware-recovery.sh - BOOTKIT-PROOF Hardware-Level Firmware Recovery
# This bypasses potentially compromised BIOS utilities and works directly with SPI flash hardware

set -e

echo "⚡ PhoenixGuard BOOTKIT-PROOF Hardware-Level Firmware Recovery"
echo "🚨 EXTREME DANGER: This will directly manipulate SPI flash hardware!"
echo "   This bypasses ASUS EZ Flash and ALL software that bootkits could compromise."
echo "   If this fails, you may need a hardware programmer to recover!"
echo
echo "Required tools: flashrom, chipsec, dmidecode"
echo "Install with: sudo apt install flashrom dmidecode && pip install chipsec"
echo

# Parse arguments
FIRMWARE_IMAGE=""
VERIFY_ONLY=""
VERBOSE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --firmware)
            FIRMWARE_IMAGE="$2"
            shift 2
            ;;
        --verify-only)
            VERIFY_ONLY="1"
            shift
            ;;
        -v|--verbose)
            VERBOSE="1"
            shift
            ;;
        -h|--help)
            echo "Usage: $0 --firmware <firmware.bin> [--verify-only] [-v|--verbose]"
            echo "       $0 --help"
            echo
            echo "Options:"
            echo "  --firmware <file>    Clean firmware image to restore (required)"
            echo "  --verify-only        Only verify hardware access, don't write"
            echo "  -v, --verbose        Enable verbose output"
            echo "  -h, --help          Show this help message"
            exit 0
            ;;
        *)
            echo "ERROR: Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

if [ -z "$FIRMWARE_IMAGE" ]; then
    echo "ERROR: --firmware argument is required"
    echo
    echo "Usage examples:"
    echo "  sudo $0 --firmware drivers/G615LPAS.325 --verify-only"
    echo "  sudo $0 --firmware drivers/G615LPAS.325 -v"
    exit 1
fi

# Confirm the operation
echo "Usage examples:"
echo "  make hardware-recovery              # Interactive verification + recovery"
echo "  sudo python3 scripts/hardware_firmware_recovery.py drivers/G615LPAS.325 --verify-only"
echo "  sudo python3 scripts/hardware_firmware_recovery.py drivers/G615LPAS.325 -v"
echo

read -p "Continue with hardware recovery? [y/N]: " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Hardware recovery cancelled."
    exit 0
fi

echo
echo "🔧 Starting BOOTKIT-PROOF hardware recovery..."

# Check if firmware image exists
if [ -f "$FIRMWARE_IMAGE" ]; then
    ARGS="$FIRMWARE_IMAGE"
    [ -n "$VERBOSE" ] && ARGS="$ARGS -v"
    [ -n "$VERIFY_ONLY" ] && ARGS="$ARGS --verify-only"
    
    sudo python3 scripts/hardware_firmware_recovery.py $ARGS --output hardware_recovery_results.json
else
    echo "ERROR: Clean firmware image not found at $FIRMWARE_IMAGE"
    echo "       This must be your EXACT hardware's clean firmware dump."
    echo "       Do NOT use firmware from different models/versions!"
    exit 1
fi
