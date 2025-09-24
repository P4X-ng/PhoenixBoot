#!/bin/bash
#
# PhoenixGuard Flashrom Access Fix Script
# Addresses I/O privileges issues for firmware recovery operations
#

set -e

echo "🔧 PhoenixGuard Flashrom Access Fix"
echo "==================================="

# Check if we're running as root
if [[ $EUID -ne 0 ]]; then
    echo "❌ This script must be run as root"
    exit 1
fi

# Check current lockdown status
echo "🔍 Checking kernel lockdown status..."
if [ -f /sys/kernel/security/lockdown ]; then
    LOCKDOWN_STATUS=$(cat /sys/kernel/security/lockdown)
    echo "Current lockdown: $LOCKDOWN_STATUS"
    
    if [[ "$LOCKDOWN_STATUS" == *"[integrity]"* ]] || [[ "$LOCKDOWN_STATUS" == *"[confidentiality]"* ]]; then
        echo "⚠️  Kernel lockdown is preventing hardware access."
        echo "   This is typically caused by Secure Boot being enabled."
        echo ""
        echo "Solutions available:"
        echo "1. Temporary: Reboot with lockdown=none kernel parameter"
        echo "2. Permanent: Modify GRUB configuration"
        echo "3. Alternative: Use SPI programmer with external hardware"
        echo ""
        
        # Check if the system supports SPI programmers
        echo "🔍 Checking for alternative SPI access methods..."
        
        # Check for USB-based SPI programmers
        if lsusb | grep -q "Dediprog\|CH341\|FT2232\|Bus Pirate"; then
            echo "✅ External SPI programmer detected"
            echo "   You can use flashrom with external programmer instead"
        fi
        
        # Check for internal SPI via GPIO
        if [ -d /sys/class/gpio ]; then
            echo "✅ GPIO interface available for bit-bang SPI"
        fi
        
        # Offer to create a GRUB configuration fix
        echo ""
        read -p "Do you want to add lockdown=none to GRUB configuration? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "🔧 Modifying GRUB configuration..."
            
            # Backup current GRUB config
            cp /etc/default/grub /etc/default/grub.backup
            
            # Check if lockdown=none is already present
            if ! grep -q "lockdown=none" /etc/default/grub; then
                # Add lockdown=none to GRUB_CMDLINE_LINUX_DEFAULT
                sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="lockdown=none /' /etc/default/grub
                
                echo "✅ Added lockdown=none to GRUB configuration"
                echo "🔄 Updating GRUB..."
                update-grub
                
                echo ""
                echo "⚠️  IMPORTANT: You need to reboot for changes to take effect"
                echo "   After reboot, flashrom will have hardware access"
                echo ""
                echo "   To revert: restore /etc/default/grub.backup and run update-grub"
                
                read -p "Do you want to reboot now? (y/N): " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    echo "🔄 Rebooting system..."
                    reboot
                fi
            else
                echo "ℹ️  lockdown=none already present in GRUB configuration"
            fi
        fi
        
        exit 1
    fi
fi

# Test flashrom access
echo ""
echo "🧪 Testing flashrom access..."
if timeout 10 flashrom -p internal > /tmp/flashrom_test.log 2>&1; then
    echo "✅ Flashrom has hardware access"
    echo "🔍 Detected flash chips:"
    grep -i "found\|detected" /tmp/flashrom_test.log | head -5
else
    RETURN_CODE=$?
    echo "❌ Flashrom access test failed (exit code: $RETURN_CODE)"
    echo "📋 Error details:"
    cat /tmp/flashrom_test.log
    
    # Check for other common issues
    if grep -q "No EEPROM/flash device found" /tmp/flashrom_test.log; then
        echo ""
        echo "ℹ️  This might be normal - some systems don't have accessible SPI flash"
        echo "   via internal programmer. Consider using external programmer."
    fi
fi

# Clean up
rm -f /tmp/flashrom_test.log

echo ""
echo "🔧 Fix script completed"
