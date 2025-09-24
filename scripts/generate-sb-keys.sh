#!/usr/bin/env bash
# Description: Generates Secure Boot keypairs (PK, KEK, db).

set -euo pipefail

# PK
[ -f keys/PK.key ] || openssl req -new -x509 -newkey rsa:4096 -nodes -sha256 -days 3650 \
    -subj "/CN=PhoenixGuard PK/O=PhoenixGuard/C=US" -keyout keys/PK.key -out keys/PK.crt
openssl x509 -in keys/PK.crt -outform DER -out keys/PK.cer
chmod 600 keys/PK.key || true

# KEK
[ -f keys/KEK.key ] || openssl req -new -x509 -newkey rsa:4096 -nodes -sha256 -days 3650 \
    -subj "/CN=PhoenixGuard KEK/O=PhoenixGuard/C=US" -keyout keys/KEK.key -out keys/KEK.crt
openssl x509 -in keys/KEK.crt -outform DER -out keys/KEK.cer
chmod 600 keys/KEK.key || true

# db
[ -f keys/db.key ] || openssl req -new -x509 -newkey rsa:4096 -nodes -sha256 -days 3650 \
    -subj "/CN=PhoenixGuard db/O=PhoenixGuard/C=US" -keyout keys/db.key -out keys/db.crt
openssl x509 -in keys/db.crt -outform DER -out keys/db.cer
chmod 600 keys/db.key || true

echo "✅ Keys and certs in ./keys"

