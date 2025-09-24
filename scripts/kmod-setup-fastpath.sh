#!/usr/bin/env bash
set -euo pipefail
# Save caller's working directory to resolve relative paths correctly
ORIG_PWD=$(pwd)
cd "$(dirname "$0")/.."

# Configure utils/pfs_fastpath.ko to autoload and sign it if needed.
# Usage: kmod-setup-fastpath.sh [module_path]
# If module_path is not given, tries utils/pfs_fastpath.ko

# Resolve a path to absolute, with fallbacks
abspath() {
  local p="$1"
  if command -v realpath >/dev/null 2>&1; then
    realpath -m "$p"
  elif command -v readlink >/dev/null 2>&1; then
    readlink -f "$p"
  else
    python - "$p" <<'PY'
import os, sys
print(os.path.realpath(sys.argv[1]))
PY
  fi
}

ARG="${1:-}"
if [ -n "$ARG" ]; then
  if [[ "$ARG" = /* ]]; then
    MOD_PATH="$ARG"
  else
    MOD_PATH="$(abspath "$ORIG_PWD/$ARG")"
  fi
else
  MOD_PATH="utils/pfs_fastpath.ko"
fi
MOD_NAME=$(basename "$MOD_PATH" .ko)

if [ ! -f "$MOD_PATH" ]; then
  echo "Module not found: $MOD_PATH"; exit 1
fi

# Try to reuse an enrolled MOK if present (avoid eval on empty)
if exports=$(bash scripts/mok-pick-existing.sh 2>/dev/null); then
  eval "$exports"
  echo "Using enrolled MOK: ${KMOD_CERT:-unknown}"
else
  echo "No enrolled MOK match found; you may need to 'just secure mok-enroll-new' and reboot."
fi

# Try to auto-select a MOK if none provided
if [ -z "${KMOD_CERT:-}" ] || [ -z "${KMOD_KEY:-}" ]; then
  if exports=$(bash scripts/mok-select-key.sh 2>/dev/null); then
    eval "$exports"
    echo "Using MOK cert: ${KMOD_CERT}"
  fi
fi

# Sign the module (needs kernel headers installed)
PY=${VENV_BIN:-/home/punk/.venv/bin}/python
"$PY" utils/pgmodsign.py --cert-path "${KMOD_CERT:-out/keys/mok/PGMOK.crt}" --key-path "${KMOD_KEY:-out/keys/mok/PGMOK.key}" "$MOD_PATH" || true

# Install module into extra/ and depmod
REL=$(uname -r)
DST_DIR="/lib/modules/${REL}/extra"
sudo install -D -m 0644 "$MOD_PATH" "$DST_DIR/$MOD_NAME.ko"
sudo depmod -a "$REL"

# Configure autoload
bash scripts/kmod-autoload.sh "$MOD_NAME"

echo "Done. To load now: sudo modprobe $MOD_NAME"
