#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib/common.sh

info "🚀 Launching AutoNuke recovery orchestrator"
SCRIPT="nuclear-cd-build/iso/recovery/scripts/autonuke.py"

if [ ! -f "$SCRIPT" ]; then
  die "AutoNuke script not found at $SCRIPT"
fi

if [ -x "/home/punk/.venv/bin/python3" ]; then
  PY="/home/punk/.venv/bin/python3"
else
  PY="python3"
fi

exec "$PY" "$SCRIPT"

