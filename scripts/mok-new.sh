#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Generate a new PhoenixGuard Module Owner Key (PGMOK)
# Usage: mok-new.sh [NAME] [CN]
#   NAME: basename for output files (default: PGMOK)
#   CN:   certificate subject Common Name (default: PhoenixGuard Module Key)

NAME=${1:-PGMOK}
CN=${2:-PhoenixGuard Module Key}
OUT_DIR="out/keys/mok"
mkdir -p "$OUT_DIR"

KEY="$OUT_DIR/$NAME.key"
CRT="$OUT_DIR/$NAME.crt"
DER="$OUT_DIR/$NAME.der"
PEM="$OUT_DIR/$NAME.pem"

# Create RSA-4096 key and a self-signed X.509 cert (10y)
openssl genrsa -out "$KEY" 4096
openssl req -new -x509 -key "$KEY" -sha256 -subj "/CN=$CN" -days 3650 -out "$CRT"
chmod 600 "$KEY"

# Also produce DER and combined PEM if useful
openssl x509 -in "$CRT" -outform DER -out "$DER"
cat "$KEY" "$CRT" > "$PEM"
chmod 600 "$PEM"

# Show details
openssl x509 -in "$CRT" -noout -subject -issuer -dates -fingerprint -sha1

echo "Created: $KEY"
echo "Created: $CRT"
echo "Created: $DER"
echo "Created: $PEM"