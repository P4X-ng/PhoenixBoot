#!/usr/bin/env bash
# Ensure kernel modules load in the correct order

MODULES_ORDER=(
    "efi_vars"      # EFI variable access
    "efivars"       # Modern EFI variables 
    "efivarfs"      # EFI variable filesystem
    "dm_mod"        # Device mapper base
    "dm_crypt"      # Encryption support
    "loop"          # Loop devices for ISOs
    "iso9660"       # ISO filesystem
    "vfat"          # FAT32 for ESP
)

echo "Loading modules in correct order..."
for mod in "${MODULES_ORDER[@]}"; do
    if ! lsmod | grep -q "^$mod "; then
        echo -n "  Loading $mod... "
        if modprobe "$mod" 2>/dev/null; then
            echo "✓"
        else
            echo "⚠ (not available)"
        fi
    else
        echo "  Module $mod already loaded ✓"
    fi
done
