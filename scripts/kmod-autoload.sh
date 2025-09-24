#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Configure a module to autoload at boot via systemd modules-load.d
# Usage: kmod-autoload.sh <module_name>

MOD=${1:-}
if [ -z "$MOD" ]; then
  echo "Usage: $0 <module_name>"; exit 1
fi

CONF="/etc/modules-load.d/phoenixguard.conf"
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

if [ -f "$CONF" ]; then
  sudo cp -a "$CONF" "$TMP"
else
  : > "$TMP"
fi

# Ensure the module name appears exactly once
if ! grep -qE "^${MOD}(\s|$)" "$TMP"; then
  echo "$MOD" >> "$TMP"
fi

sudo install -D -m 0644 "$TMP" "$CONF"
sudo depmod -a "$(uname -r)" || true

echo "Configured autoload for module: $MOD"
echo "File: $CONF"