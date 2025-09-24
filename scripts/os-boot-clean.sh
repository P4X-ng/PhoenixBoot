#!/usr/bin/env bash
# Description: Cleans stale UEFI boot entries.

set -euo pipefail

echo "🔎 Current UEFI boot entries:"
sudo efibootmgr -v || { echo "❌ efibootmgr failed"; exit 1; }

if [ -n "${OS_BOOT_RM:-}" ]; then
    IFS=',' read -r -a IDS <<<"${OS_BOOT_RM}"
    for id in "${IDS[@]}"; do
        id_trim=$(echo "$id" | sed 's/^Boot//; s/^0*//')
        printf '\n🗑️  Removing Boot%04X\n' "0x$id_trim"
        sudo efibootmgr -b $(printf '%04X' "0x$id_trim") -B || true
    done
fi

if [ -n "${OS_BOOT_ORDER:-}" ]; then
    echo "🔧 Setting BootOrder=${OS_BOOT_ORDER}"
    sudo efibootmgr -o ${OS_BOOT_ORDER}
fi

if [ -n "${OS_BOOT_NEXT:-}" ]; then
    echo "⏭️  Setting BootNext=${OS_BOOT_NEXT}"
    sudo efibootmgr -n ${OS_BOOT_NEXT}
fi

echo "✅ Done. Re-run to verify: sudo efibootmgr -v"

