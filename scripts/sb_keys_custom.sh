#!/usr/bin/env bash
set -euo pipefail
# Generate custom PK/KEK/db keys and ESL/AUTH bundles for Secure Boot testing
# Output directory is the first arg or defaults to ./sbkeys

OUT_DIR=${1:-sbkeys}
mkdir -p "$OUT_DIR"

PK_KEY="$OUT_DIR/pk.key"
PK_CRT="$OUT_DIR/pk.crt"
KEK_KEY="$OUT_DIR/kek.key"
KEK_CRT="$OUT_DIR/kek.crt"
DB_KEY="$OUT_DIR/db.key"
DB_CRT="$OUT_DIR/db.crt"

PK_ESL="$OUT_DIR/pk.esl"
KEK_ESL="$OUT_DIR/kek.esl"
DB_ESL="$OUT_DIR/db.esl"

PK_AUTH="$OUT_DIR/pk.auth"
KEK_AUTH="$OUT_DIR/kek.auth"
DB_AUTH="$OUT_DIR/db.auth"

# Create certs/keys
openssl req -new -x509 -newkey rsa:3072 -sha256 -days 3650 -nodes \
  -subj "/CN=PhoenixGuard PK/" -keyout "$PK_KEY" -out "$PK_CRT"
openssl req -new -x509 -newkey rsa:3072 -sha256 -days 3650 -nodes \
  -subj "/CN=PhoenixGuard KEK/" -keyout "$KEK_KEY" -out "$KEK_CRT"
openssl req -new -x509 -newkey rsa:3072 -sha256 -days 3650 -nodes \
  -subj "/CN=PhoenixGuard db/" -keyout "$DB_KEY" -out "$DB_CRT"

# ESLs if tools are present
if command -v cert-to-efi-sig-list >/dev/null 2>&1; then
  cert-to-efi-sig-list -g 00000000-0000-0000-0000-000000000000 "$PK_CRT" "$PK_ESL"
  cert-to-efi-sig-list -g 00000000-0000-0000-0000-000000000000 "$KEK_CRT" "$KEK_ESL"
  cert-to-efi-sig-list -g 00000000-0000-0000-0000-000000000000 "$DB_CRT" "$DB_ESL"
fi

# AUTHs if tools are present
if command -v sign-efi-sig-list >/dev/null 2>&1; then
  # PK signs itself
  sign-efi-sig-list -c "$PK_CRT" -k "$PK_KEY" PK "$PK_ESL" "$PK_AUTH"
  # KEK authorized by PK
  sign-efi-sig-list -c "$PK_CRT" -k "$PK_KEY" KEK "$KEK_ESL" "$KEK_AUTH"
  # db authorized by KEK
  sign-efi-sig-list -c "$KEK_CRT" -k "$KEK_KEY" db "$DB_ESL" "$DB_AUTH"
fi

echo "[sb-keys-custom] Generated keys in $OUT_DIR"
