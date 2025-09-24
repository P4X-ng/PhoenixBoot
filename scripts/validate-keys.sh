#!/usr/bin/env bash
# Description: Validates the presence of Secure Boot AUTH blobs.

set -euo pipefail

SRC_DIR=""
if [ -f out/securevars/PK.auth ] && [ -f out/securevars/KEK.auth ] && [ -f out/securevars/db.auth ]; then
    SRC_DIR="out/securevars"
elif [ -f secureboot_certs/PK.auth ] && [ -f secureboot_certs/KEK.auth ] && [ -f secureboot_certs/db.auth ]; then
    SRC_DIR="secureboot_certs"
else
    echo "❌ Missing PK/KEK/db AUTH blobs. Generate with 'just make-auth' or provide in secureboot_certs/"
    exit 1
fi

echo "✅ AUTH blobs found in $SRC_DIR"
ls -l "$SRC_DIR"/{PK,KEK,db}.auth 2>/dev/null || true

