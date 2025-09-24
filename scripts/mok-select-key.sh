#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Interactive or env-driven selection of a MOK cert+key for module signing.
# Usage:
#   Non-interactive (preferred): set KMOD_CERT/KMOD_KEY, then run this to verify
#   Interactive: run with no env; pick an enrolled cert that has a matching key
# Output:
#   Prints `export KMOD_CERT=...` and `export KMOD_KEY=...` on stdout

MOK_DIR="out/keys/mok"
LEGACY_DIR="out/keys"

list_pairs() {
  # Yield lines: CERT_PATH|KEY_PATH|ENROLLED(Y/N)|SHA1
  scan_dir() {
    local d="$1"
    [ -d "$d" ] || return 0
    find "$d" -maxdepth 2 -type f \( -name '*.crt' -o -name '*.pem' -o -name '*.cer' -o -name '*.der' \) | while read -r cert; do
      local base="${cert%.*}"
      local key=""
      for k in "$base.key" "${base%%.crt}.key"; do
        [ -f "$k" ] && { key="$k"; break; }
      done
      [ -n "$key" ] || continue
      local fp
      case "${cert##*.}" in
        der|cer) fp=$(openssl x509 -inform DER -in "$cert" -noout -fingerprint -sha1 2>/dev/null | sed 's/^SHA1 Fingerprint=//' | tr '[:lower:]' '[:upper:]');;
        crt|pem) fp=$(openssl x509 -in "$cert" -noout -fingerprint -sha1 2>/dev/null | sed 's/^SHA1 Fingerprint=//' | tr '[:lower:]' '[:upper:]');;
        *) fp="";;
      esac
      [ -n "$fp" ] || continue
      if sudo mokutil --list-enrolled 2>/dev/null | tr '[:lower:]' '[:upper:]' | grep -q "$fp"; then
        echo "$cert|$key|Y|$fp"
      else
        echo "$cert|$key|N|$fp"
      fi
    done
  }
  scan_dir "$MOK_DIR"
  scan_dir "$LEGACY_DIR"
}

# If env is already set and valid, just echo exports and exit 0
if [ -n "${KMOD_CERT:-}" ] && [ -n "${KMOD_KEY:-}" ] && [ -f "$KMOD_CERT" ] && [ -f "$KMOD_KEY" ]; then
  echo "export KMOD_CERT=$KMOD_CERT"
  echo "export KMOD_KEY=$KMOD_KEY"
  exit 0
fi

# Build a list
mapfile -t ITEMS < <(list_pairs)
if [ "${#ITEMS[@]}" -eq 0 ]; then
  echo "No MOK cert+key pairs found under $MOK_DIR or $LEGACY_DIR" >&2
  exit 1
fi

# Prefer the first enrolled pair if non-interactive
for line in "${ITEMS[@]}"; do
  IFS='|' read -r cert key enrolled fp <<<"$line"
  if [ "$enrolled" = "Y" ]; then
    echo "export KMOD_CERT=$cert"
    echo "export KMOD_KEY=$key"
    exit 0
  fi
done

# If none enrolled, fall back to first pair and warn
IFS='|' read -r cert key enrolled fp <<<"${ITEMS[0]}"
echo "Warning: selected cert is not enrolled (SHA1=$fp). Kernel may reject signed modules." >&2
echo "export KMOD_CERT=$cert"
echo "export KMOD_KEY=$key"
