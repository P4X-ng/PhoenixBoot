#!/usr/bin/env bash
# Description: Displays the current MOK and Secure Boot status, and syncs metadata if available.

set -euo pipefail

VENV_PY=${VENV_BIN:-/home/punk/.venv/bin}/python

echo "🔐 MOK and Secure Boot Status"
echo "============================="

echo

echo "--- Secure Boot State ---"
sudo mokutil --sb-state || true
echo

# Canonical cert info if present
if [ -n "${MOK_CERT_PEM:-}" ] && [ -f "${MOK_CERT_PEM}" ]; then
  echo "--- Canonical MOK certificate ---"
  echo "Path: ${MOK_CERT_PEM}"
  OPENSSL_OUT=$(openssl x509 -in "${MOK_CERT_PEM}" -noout -subject -issuer -dates || true)
  echo "$OPENSSL_OUT"
  SHA1_FP=$(openssl x509 -in "${MOK_CERT_PEM}" -noout -fingerprint -sha1 | sed 's/^SHA1 Fingerprint=//')
  SHA256_FP=$(openssl x509 -in "${MOK_CERT_PEM}" -noout -fingerprint -sha256 | sed 's/^SHA256 Fingerprint=//')
  echo "SHA1:   $SHA1_FP"
  echo "SHA256: $SHA256_FP"
fi

echo

echo "--- Enrolled MOKs ---"
LIST_ENROLLED=$(sudo mokutil --list-enrolled 2>/dev/null || true)
echo "$LIST_ENROLLED"
echo

# Determine if canonical cert is enrolled
ENROLLED_MATCH=0
if [ -n "${SHA1_FP:-}" ]; then
  if printf "%s\n" "$LIST_ENROLLED" | tr '[:lower:]' '[:upper:]' | grep -q "$(echo "$SHA1_FP" | tr '[:lower:]' '[:upper:]')"; then
    ENROLLED_MATCH=1
  fi
fi

# Pending changes
echo "--- Pending MOK Changes ---"
PENDING=$(sudo mokutil --list-new 2>/dev/null || true)
if [ -n "$PENDING" ]; then
    echo "$PENDING"
else
    echo "No pending MOK changes"
fi

echo

# Sync metadata if present
if [ -n "${MOK_CERT_PEM:-}" ] && [ -f "${MOK_CERT_PEM}" ]; then
  NAME_BASE=$(basename "$MOK_CERT_PEM")
  NAME_NOEXT="${NAME_BASE%.*}"
  META_PATH="out/keys/mok/${NAME_NOEXT}.meta.json"
  if [ -f "$META_PATH" ]; then
    NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    ENR="$ENROLLED_MATCH"
    "$VENV_PY" - "$META_PATH" "$NOW" "$ENR" <<'PY'
import json, sys
meta_path = sys.argv[1]
now = sys.argv[2]
enrolled = sys.argv[3] == '1'
try:
    with open(meta_path, 'r') as f:
        data = json.load(f)
except Exception:
    data = {}
if enrolled:
    data['pending'] = False
    data['enrolled_at_utc'] = now
else:
    data.setdefault('pending', True)
with open(meta_path, 'w') as f:
    json.dump(data, f, indent=2, sort_keys=True)
print(f"Updated metadata: {meta_path} (pending={data.get('pending')})")
PY
  fi
fi
