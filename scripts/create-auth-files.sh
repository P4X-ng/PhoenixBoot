#!/usr/bin/env bash
# Description: Creates ESL and AUTH files for Secure Boot variables.

set -euo pipefail

# PK self-signed
cert-to-efi-sig-list -g $(uuidgen) keys/PK.cer out/securevars/PK.esl
sign-efi-sig-list -k keys/PK.key -c keys/PK.crt PK out/securevars/PK.esl out/securevars/PK.auth

# KEK signed by PK
cert-to-efi-sig-list -g $(uuidgen) keys/KEK.cer out/securevars/KEK.esl
sign-efi-sig-list -k keys/PK.key -c keys/PK.crt KEK out/securevars/KEK.esl out/securevars/KEK.auth

# db signed by KEK
cert-to-efi-sig-list -g $(uuidgen) keys/db.cer out/securevars/db.esl
sign-efi-sig-list -k keys/KEK.key -c keys/KEK.crt db out/securevars/db.esl out/securevars/db.auth

echo "✅ AUTH blobs in out/securevars"

