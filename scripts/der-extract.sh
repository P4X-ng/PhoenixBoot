#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Usage: der-extract.sh <infile.der|.p12|.pfx|.cer|.crt|.pem> <out_dir> <name>
# Produces: <out_dir>/<name>.crt (PEM cert), <out_dir>/<name>.key (PEM key, if available), <out_dir>/<name>.der (DER cert)

IN=${1:-}
OUT_DIR=${2:-out/keys}
NAME=${3:-PGMOK}

if [ -z "$IN" ] || [ ! -f "$IN" ]; then
  echo "Usage: $0 <infile> [out_dir] [name]"; exit 1
fi
mkdir -p "$OUT_DIR"
CERT_PEM="$OUT_DIR/$NAME.crt"
KEY_PEM="$OUT_DIR/$NAME.key"
CERT_DER="$OUT_DIR/$NAME.der"

ext="${IN##*.}"
case "$ext" in
  der|cer)
    # Assume X.509 cert in DER
    openssl x509 -inform DER -in "$IN" -out "$CERT_PEM"
    ;;
  crt|pem)
    # Assume PEM X.509 cert (and maybe key if it's a combined file)
    # Extract cert in PEM form
    openssl x509 -in "$IN" -out "$CERT_PEM"
    # Try extracting a key if present (will fail harmlessly if not)
    if openssl pkey -in "$IN" -out "$KEY_PEM" 2>/dev/null; then
      chmod 600 "$KEY_PEM"
    fi
    ;;
  p12|pfx)
    # PKCS#12 bundle: prompt for import password; output unencrypted key
    openssl pkcs12 -in "$IN" -nokeys -out "$CERT_PEM"
    openssl pkcs12 -in "$IN" -nocerts -nodes -out "$KEY_PEM"
    chmod 600 "$KEY_PEM"
    ;;
  *)
    echo "Unknown input type: $IN"; exit 1
    ;;
 esac

# Always also produce DER cert
openssl x509 -in "$CERT_PEM" -outform DER -out "$CERT_DER"

# Print fingerprints
echo "--- Certificate ---"
openssl x509 -in "$CERT_PEM" -noout -subject -issuer -dates -fingerprint -sha1

if [ -f "$KEY_PEM" ]; then
  echo "--- Key present ---"
fi

echo "Wrote: $CERT_PEM"
echo "Wrote: $CERT_DER"
[ -f "$KEY_PEM" ] && echo "Wrote: $KEY_PEM" || true
