#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Find the best existing enrolled MOK to reuse for signing if possible.
# - Tries to match out/keys/PGMOK.* or other known certs to mokutil --list-enrolled
# - If a match is found, emits exports users can source and returns 0
# - Otherwise returns non-zero

CERT_GLOBES=(
  "out/keys/mok/*.crt"
  "out/keys/mok/*.pem"
  "out/keys/*.crt"
  "out/keys/*.pem"
  "build/keys/*.crt"
  "secureboot_certs/*.crt"
  "/var/lib/shim-signed/mok/*"
  "/boot/efi/EFI/PhoenixGuard/*"
  "/boot/efi/EFI/Boot/*"
)

match_enrolled() {
  local f="$1"
  local sha1=""
  case "${f##*.}" in
    der|cer) sha1=$(openssl x509 -inform DER -in "$f" -noout -fingerprint -sha1 2>/dev/null | sed 's/^SHA1 Fingerprint=//' | tr '[:lower:]' '[:upper:]');;
    crt|pem) sha1=$(openssl x509 -in "$f" -noout -fingerprint -sha1 2>/dev/null | sed 's/^SHA1 Fingerprint=//' | tr '[:lower:]' '[:upper:]');;
    *) return 1;;
  esac
  [ -n "$sha1" ] || return 1
  sudo mokutil --list-enrolled 2>/dev/null | grep -q "$sha1"
}

found=0
for g in "${CERT_GLOBES[@]}"; do
  for f in $g; do
    [ -f "$f" ] || continue
    if match_enrolled "$f"; then
      # Try to locate a matching key next to it
      base="${f%.*}"
      for k in "$base.key" "${base%%.crt}.key"; do
        if [ -f "$k" ]; then
          echo "export KMOD_CERT=$f"
          echo "export KMOD_KEY=$k"
          found=1
          break
        fi
      done
      if [ "$found" = "1" ]; then break; fi
    fi
  done
  [ "$found" = "1" ] && break
done

if [ "$found" != "1" ]; then
  exit 1
fi
