#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# List enrolled MOKs and match against local certificates in common places.
# Prints matching fingerprints and paths to avoid unnecessary reboots.

search_local_certs() {
  # Search canonical project locations first, then system locations.
  local dirs=(
    "out/keys/mok"
    "out/keys/secure_boot"
    "build/keys"
    "secureboot_certs"
    "/var/lib/shim-signed/mok"
    "/boot/efi/EFI/PhoenixGuard"
    "/boot/efi/EFI/Boot"
  )
  for d in "${dirs[@]}"; do
    [ -d "$d" ] || continue
    find "$d" -type f \( -name '*.crt' -o -name '*.pem' -o -name '*.cer' -o -name '*.der' \) 2>/dev/null
  done
  # Optional deep scan across root FS if explicitly requested
  if [ "${DEEP_SCAN:-0}" = "1" ]; then
    find / -xdev -type f \( -name '*.crt' -o -name '*.pem' -o -name '*.cer' -o -name '*.der' \) 2>/dev/null || true
  fi
}

list_enrolled_sha1() {
    sudo mokutil --list-enrolled 2>/dev/null | grep SHA1 | awk '{print $3}'    
  # sudo mokutil --list-enrolled 2>/dev/null | awk -F'=' '/SHA1 Fingerprint/ {gsub(/\r/,""); print $2}' | tr '[:lower:]' '[:upper:]'
}

match_cert() {
  local f="$1"
  local sha1=""
  case "${f##*.}" in
    der|cer)
      sha1=$(openssl x509 -inform DER -in "$f" -noout -fingerprint -sha1 2>/dev/null | sed 's/^SHA1 Fingerprint=//' | tr '[:lower:]' '[:upper:]') ;;
    crt|pem)
      sha1=$(openssl x509 -in "$f" -noout -fingerprint -sha1 2>/dev/null | sed 's/^SHA1 Fingerprint=//' | tr '[:lower:]' '[:upper:]') ;;
  esac
  [ -n "$sha1" ] && echo "$sha1 $f"
}

ENROLLED=$(list_enrolled_sha1 || true)
if [ -z "$ENROLLED" ]; then
  echo "No MOKs listed by mokutil or not accessible." >&2
fi

echo "--- Enrolled MOKs (SHA1) ---"
echo "$ENROLLED"
echo ""

echo "--- Matching local certificates ---"
FOUND=0
while IFS= read -r cert; do
  [ -n "$cert" ] || continue
  line=$(match_cert "$cert" || true)
  [ -n "$line" ] || continue
  sha1_local=${line%% *}
  if echo "$ENROLLED" | grep -q "$sha1_local"; then
    echo "MATCH: $sha1_local  =>  $cert"
    FOUND=1
  fi
done < <(search_local_certs)

if [ "$FOUND" = "0" ]; then
  echo "No local certs matched enrolled MOKs."
fi
