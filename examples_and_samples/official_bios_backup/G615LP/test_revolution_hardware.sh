#!/bin/bash
# PhoenixGuard Revolution Hardware Test
# Test CH341A with tyrannical BIOS first, then deploy the Universal BIOS revolution!

echo "🔥 PhoenixGuard Revolution Hardware Test"
echo "========================================"
echo ""
echo "📋 Test Plan:"
echo "   1. 🏭 Flash tyrannical ASUS G615LP.325 BIOS (test hardware works)" 
echo "   2. ✅ Verify system boots with official BIOS"
echo "   3. 🚀 Deploy Universal BIOS revolution!"
echo "   4. 🎯 Verify Universal BIOS liberation works"
echo ""

# Safety checks
if [ ! -f "G615LP_official_v325.bin" ]; then
    echo "❌ Missing tyrannical BIOS backup: G615LP_official_v325.bin"
    exit 1
fi

if ! lsusb | grep -q "1a86:5512"; then
    echo "❌ CH341A programmer not detected!"
    echo "   Connect your CH341A and try again."
    exit 1
fi

UNIVERSAL_BIOS="../../universal_bios_database/G615LP/G615LP_universal_config.json"
if [ ! -f "$UNIVERSAL_BIOS" ]; then
    echo "❌ Universal BIOS config not found: $UNIVERSAL_BIOS"
    exit 1
fi

echo "✅ All prerequisites ready!"
echo ""

# Prompt for revolution test
echo "🚨 REVOLUTION HARDWARE TEST"
echo "   This will test your CH341A setup by flashing firmware."
echo "   Target laptop MUST be powered off, battery removed!"
echo ""
read -p "Ready to test the revolution hardware? [y/N]: " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Revolution test cancelled."
    exit 0
fi

echo ""
echo "🏭 Phase 1: Testing hardware with tyrannical BIOS..."
echo "   This verifies your CH341A + SOP8 clip setup works"
echo ""

# Test with official BIOS first
echo "📡 Flashing official ASUS G615LP.325 (tyrannical version)..."
echo "flashrom --programmer=ch341a_spi --write G615LP_official_v325.bin"
echo ""
echo "⚠️  Run this command manually when ready:"
echo "   flashrom --programmer=ch341a_spi --write G615LP_official_v325.bin"
echo ""
echo "🎯 After successful flash:"
echo "   1. Remove CH341A clip"
echo "   2. Power on target laptop"  
echo "   3. Verify BIOS version shows 325"
echo "   4. Return here for Universal BIOS deployment!"
echo ""
echo "🔥 The revolution is protected by proper backups!"

