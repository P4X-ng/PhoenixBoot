#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib/common.sh

info "🔐 UUEFI report (read-only)"

# SB state
if command -v mokutil >/dev/null 2>&1; then
  echo "SB: $(mokutil --sb-state 2>&1 || true)"
else
  echo "SB: mokutil not installed"
fi

# Boot manager info
if command -v efibootmgr >/dev/null 2>&1; then
  if efibootmgr -v >/dev/null 2>&1; then
    echo "\nBoot entries (efibootmgr -v):"
    efibootmgr -v || true
  else
    echo "\nBoot entries require privileges; showing with sudo -n if possible:"
    sudo -n efibootmgr -v || echo "(sudo not available non-interactively)"
  fi
else
  echo "efibootmgr not installed"
fi

# Kernel lockdown + module sig enforce
if [ -f /sys/kernel/security/lockdown ]; then
  echo -n "Lockdown: "; cat /sys/kernel/security/lockdown || true
fi
if [ -f /sys/module/module/parameters/sig_enforce ]; then
  echo -n "Module sig enforce: "; cat /sys/module/module/parameters/sig_enforce || true
fi

# Run hardware scraper non-interactively to create a profile
SCRAPER_DIR="nuclear-cd-build/iso/recovery/scripts"
SCRAPER_PY="$SCRAPER_DIR/universal_hardware_scraper.py"
if [ -f "$SCRAPER_PY" ]; then
  if [ -x "/home/punk/.venv/bin/python3" ]; then PY="/home/punk/.venv/bin/python3"; else PY="python3"; fi
  info "📋 Collecting UEFI variable summary and hardware profile via scraper"
  "$PY" - <<'PY'
import sys, json, os
from pathlib import Path
import importlib.util
root = Path(__file__).resolve().parent.parent
scraper_path = root / 'nuclear-cd-build' / 'iso' / 'recovery' / 'scripts' / 'universal_hardware_scraper.py'
spec = importlib.util.spec_from_file_location('uhs', str(scraper_path))
uhs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(uhs)
s = uhs.UniversalHardwareScraper()
profile = s.create_hardware_profile()
s.save_profile_locally(profile)
# Print concise summary for CLI
vars_total = profile.uefi_variables.get('total_count', 0)
cats = profile.uefi_variables.get('categories', {})
print('\nUEFI variables: total=', vars_total)
for k in ['boot','security','vendor_specific','performance','hardware','unknown']:
    if k in cats:
        print(f"  {k}: {cats[k]}")
print(f"\nHardware ID: {profile.hardware_id}")
print(f"Manufacturer/Model: {profile.manufacturer} / {profile.model}")
PY
else
  warn "Hardware scraper not found at $SCRAPER_PY; skipping profile collection"
fi

ok "UUEFI report complete"

