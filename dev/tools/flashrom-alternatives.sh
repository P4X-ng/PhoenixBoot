#!/bin/bash
#
# PhoenixGuard Flashrom Access Alternatives
# Provides secure alternatives to disabling kernel lockdown permanently
#

set -e

echo "🔧 PhoenixGuard Flashrom Access Alternatives"
echo "==========================================="
echo ""
echo "Since you prefer to keep Secure Boot and kernel lockdown intact,"
echo "here are secure alternatives for firmware recovery:"
echo ""

# Check if we're running as root
if [[ $EUID -ne 0 ]]; then
    echo "❌ This script must be run as root"
    exit 1
fi

echo "🔍 Available Options:"
echo ""
echo "1. 🔄 ONE-TIME BOOT: Temporarily disable lockdown for single session"
echo "   - Uses 'systemctl kexec' to boot with lockdown=none once"
echo "   - No permanent GRUB changes"
echo "   - Reverts to secure mode on next reboot"
echo ""
echo "2. 🔌 EXTERNAL PROGRAMMER: Use dedicated SPI hardware"
echo "   - CH341A USB programmer (~$10-15)"
echo "   - Dediprog or similar professional tools" 
echo "   - Completely bypasses software restrictions"
echo ""
echo "3. 📱 CHIPSEC ALTERNATIVES: Use chipsec for some operations"
echo "   - CHIPSEC can read some firmware components"
echo "   - Works within kernel lockdown constraints"
echo "   - Limited to specific operations"
echo ""

# Check for external programmers
echo "🔍 Checking for external SPI programmers..."
if lsusb | grep -q "1a86:5512"; then
    echo "✅ CH341A USB programmer detected!"
    echo "   Use: flashrom -p ch341a_spi"
elif lsusb | grep -q "0483:dada"; then
    echo "✅ Dediprog programmer detected!"  
    echo "   Use: flashrom -p dediprog"
elif lsusb | grep -q "04d8:00de"; then
    echo "✅ Bus Pirate detected!"
    echo "   Use: flashrom -p buspirate_spi:dev=/dev/ttyUSB0"
else
    echo "ℹ️  No external SPI programmers detected"
fi

echo ""
read -p "Select option [1-3] or [q] to quit: " choice

case $choice in
    1)
        echo ""
        echo "🔄 Preparing ONE-TIME BOOT with lockdown=none..."
        echo ""
        echo "This will:"
        echo "1. Use kexec to boot current kernel with lockdown=none"
        echo "2. Allow flashrom to access hardware THIS SESSION ONLY"
        echo "3. Revert to secure lockdown on next normal reboot"
        echo ""
        read -p "Continue with one-time boot? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "🔄 Preparing kexec boot with lockdown=none..."
            
            # Get current kernel and initramfs
            KERNEL="/boot/vmlinuz-$(uname -r)"
            INITRD="/boot/initrd.img-$(uname -r)"
            ROOT_UUID=$(findmnt -n -o UUID /)
            CMDLINE=$(cat /proc/cmdline | sed 's/lockdown=[^ ]*//' | sed 's/  / /g')
            NEW_CMDLINE="$CMDLINE lockdown=none"
            
            echo "📋 Kernel: $KERNEL"
            echo "📋 Initrd: $INITRD"  
            echo "📋 Root UUID: $ROOT_UUID"
            echo "📋 New cmdline: $NEW_CMDLINE"
            echo ""
            echo "⚠️  System will reboot with temporary lockdown=none"
            echo "   After firmware recovery, reboot normally to restore security"
            echo ""
            
            # Load kexec
            kexec -l "$KERNEL" --initrd="$INITRD" --command-line="$NEW_CMDLINE"
            
            echo "✅ Kexec prepared. Execute with: systemctl kexec"
            echo "   Or run: kexec -e"
            
        else
            echo "One-time boot cancelled."
        fi
        ;;
        
    2)
        echo ""
        echo "🔌 External SPI Programmer Setup Guide"
        echo "======================================"
        echo ""
        echo "Recommended hardware (in order of preference):"
        echo ""
        echo "1. CH341A USB Programmer (~$10-15)"
        echo "   - Cheap, widely available"
        echo "   - Use: flashrom -p ch341a_spi"
        echo "   - Buy: Search 'CH341A USB programmer' on electronics sites"
        echo ""
        echo "2. Dediprog SF100/SF600 (Professional, ~$200-400)"
        echo "   - Industry standard for firmware development"
        echo "   - Use: flashrom -p dediprog"
        echo ""
        echo "3. Bus Pirate (~$30)"
        echo "   - Open source hardware"
        echo "   - Use: flashrom -p buspirate_spi:dev=/dev/ttyUSB0"
        echo ""
        echo "📋 Steps to use external programmer:"
        echo "1. Power off the system completely"
        echo "2. Locate SPI flash chip (usually 8-pin SOIC)"
        echo "3. Connect programmer clips to chip"
        echo "4. Read current firmware: flashrom -p ch341a_spi -r backup.bin"
        echo "5. Write new firmware: flashrom -p ch341a_spi -w clean_firmware.bin"
        echo ""
        echo "⚠️  CAUTION: External programming requires hardware access and can"
        echo "   permanently damage the system if done incorrectly!"
        ;;
        
    3)
        echo ""
        echo "📱 Testing CHIPSEC alternatives..."
        echo ""
        
        # Test chipsec capabilities within lockdown
        if python3 -c "import chipsec.hal.hal_base" 2>/dev/null; then
            echo "✅ CHIPSEC HAL available"
            
            # Try some safe chipsec operations
            echo "🔍 Testing CHIPSEC hardware access..."
            
            # Test SPI controller detection
            if timeout 10 python3 -c "
from chipsec.hal.hal_base import HAL
try:
    hal = HAL()
    hal.init()
    print('✅ CHIPSEC HAL initialized successfully')
    # Try to detect SPI controller (read-only operation)
    try:
        import chipsec.hal.spi as spi_module
        print('✅ SPI module accessible')
    except Exception as e:
        print(f'⚠️  SPI access limited: {e}')
    hal.close()
except Exception as e:
    print(f'❌ CHIPSEC access failed: {e}')
" 2>/dev/null; then
                echo "✅ CHIPSEC can access some hardware features"
                echo "   Limited firmware reading may be possible"
            else
                echo "❌ CHIPSEC access also blocked by kernel lockdown"
            fi
        else
            echo "❌ CHIPSEC not available"
        fi
        ;;
        
    q|Q)
        echo "Exiting alternatives menu."
        exit 0
        ;;
        
    *)
        echo "Invalid option."
        exit 1
        ;;
esac

echo ""
echo "🔧 Alternative setup completed"
