#!/usr/bin/env bash
# Description: Manages kernel modules (load, unload, status).

set -euo pipefail

ACTION=$1
MOD_RAW=$2

if [[ "$MOD_RAW" == name=* ]]; then
  MOD="${MOD_RAW#name=}"
else
  MOD="$MOD_RAW"
fi

if [ -z "$MOD" ]; then
  echo "Usage: $0 <load|unload|status> <module_name>"; exit 1;
fi

case "$ACTION" in
    load)
        echo "🔧 Loading kernel module: $MOD"
        sudo depmod -a "$(uname -r)"
        if sudo modprobe -v "$MOD"; then
            echo "✅ Loaded: $MOD"
            modinfo "$MOD" | grep -E '^(filename|sig_id|signer|sig_hashalgo):' || true
            lsmod | grep -E "^${MOD}\\\b" || true
        else
            echo "❌ Failed to load module: $MOD"; exit 1
        fi
        ;;
    unload)
        echo "🧹 Unloading kernel module: $MOD"
        if sudo modprobe -r "$MOD"; then
            echo "✅ Unloaded: $MOD"
        else
            echo "❌ Failed to unload module: $MOD"; exit 1
        fi
        ;;
    status)
        echo "🔎 Kernel module status: $MOD"
        if lsmod | grep -E "^${MOD}\\\b" >/dev/null; then
            echo "State: LOADED"
        else
            echo "State: NOT LOADED"
        fi
        echo "--- modinfo ---"
        modinfo "$MOD" 2>/dev/null | sed -n '1,120p' || echo "(modinfo not available for $MOD)"
        echo "--- signature ---"
        modinfo "$MOD" 2>/dev/null | grep -E '^(sig_id|signer|sig_key|sig_hashalgo):' || true
        ;;
    *)
        echo "Invalid action: $ACTION. Use load, unload, or status."
        exit 1
        ;;
esac

