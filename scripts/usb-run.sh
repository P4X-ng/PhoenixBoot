#!/usr/bin/env bash
# Description: Creates a bootable USB drive with the production ESP.

set -euo pipefail

[ -n "${USB1_DEV:-}" ] || { echo "❌ USB1_DEV=/dev/sdX is required"; exit 1; }

just build build

# Prefer non-sudo packaging where possible
if just build --list 2>/dev/null | grep -q 'package-esp-nosudo'; then
    just build package-esp-nosudo || just build package-esp
else
    just build package-esp
fi

# Normalize ESP for Secure Boot
just validate valid-esp-secure || echo "ℹ️ Skipping ESP secure normalization"
just validate verify-esp-robust

# Write to USB
bash scripts/usb-prepare.sh

# Sanitize USB
USB_FORCE=1 just usb sanitize || echo "ℹ️ Skipping USB sanitization"

echo "✅ USB prepared on ${USB1_DEV} — select it in firmware boot menu"

