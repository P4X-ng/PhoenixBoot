#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# List MOK certs/keys and show enrollment status.
# Usage: mok-list-keys.sh
# Scans out/keys/mok (new layout) and legacy out/keys for compatibility.

MOK_DIR="out/keys/mok"
LEGACY_DIR="out/keys"

list_certs() {
  # Prefer new layout; include legacy as fallback
  if [ -d "$MOK_DIR" ]; then
    find "$MOK_DIR" -maxdepth 2 -type f \( -name '*.crt' -o -name '*.pem' -o -name '*.cer' -o -name '*.der' \)
  fi
  if [ -d "$LEGACY_DIR" ]; then
    find "$LEGACY_DIR" -maxdepth 1 -type f \( -name '*.crt' -o -name '*.pem' -o -name '*.cer' -o -name '*.der' \)
  fi
}

sha1_fp() {
  local f="$1"
  case "${f##*.}" in
    der|cer) openssl x509 -inform DER -in "$f" -noout -fingerprint -sha1 2>/dev/null | sed 's/^SHA1 Fingerprint=//' | tr '[:lower:]' '[:upper:]' ;;
    crt|pem) openssl x509 -in "$f" -noout -fingerprint -sha1 2>/dev/null | sed 's/^SHA1 Fingerprint=//' | tr '[:lower:]' '[:upper:]' ;;
    *) return 1 ;;
  esac
}

is_enrolled() {
  local fp="$1"
  sudo mokutil --list-enrolled 2>/dev/null | tr '[:lower:]' '[:upper:]' | grep -q "$fp"
}

has_key() {
  local cert="$1"
  local base="${cert%.*}"
  [ -f "$base.key" ] || [ -f "${base%%.crt}.key" ]
}

printf "%-4s %-9s %-9s %-42s %s\n" "#" "ENROLLED" "KEY" "FINGERPRINT(SHA1)" "CERT"
idx=0
while IFS= read -r cert; do
  [ -n "$cert" ] || continue
  fp=$(sha1_fp "$cert" || true)
  [ -n "$fp" ] || continue
  idx=$((idx+1))
  if is_enrolled "$fp"; then e="YES"; else e="no"; fi
  if has_key "$cert"; then k="YES"; else k="no"; fi
  sel=""
  if [ "${KMOD_CERT:-}" = "$cert" ]; then sel="*"; fi
  printf "%-4s %-9s %-9s %-42s %s%s\n" "$idx" "$e" "$k" "$fp" "$cert" "$sel"
  eval "CERT_$idx=\"$cert\""
done < <(list_certs 2>/dev/null)

if [ "$idx" = 0 ]; then
  echo "(No candidate MOK certificates found under $MOK_DIR or $LEGACY_DIR)"
  exit 0
fi

echo
if [ -n "${KMOD_CERT:-}" ]; then
  echo "Selected: KMOD_CERT=$KMOD_CERT"
  [ -n "${KMOD_KEY:-}" ] && echo "          KMOD_KEY=$KMOD_KEY" || true
fi
