#!/usr/bin/env bash
# Description: Verifies the MOK certificate details.

set -euo pipefail

MOK_CERT_PEM=$1
MOK_CERT_DER=$2

echo "🔍 MOK Certificate Verification"
echo "=============================="
echo

if [ ! -f "$MOK_CERT_PEM" ]; then
    echo "❌ MOK PEM certificate not found: $MOK_CERT_PEM"
    exit 1
fi

echo "--- PEM Certificate Details ---"
echo "File: $MOK_CERT_PEM"
openssl x509 -in "$MOK_CERT_PEM" -noout -subject -issuer -dates -fingerprint -sha1
echo

if [ -f "$MOK_CERT_DER" ]; then
    echo "--- DER Certificate Details ---"
    echo "File: $MOK_CERT_DER"
    openssl x509 -inform DER -in "$MOK_CERT_DER" -noout -subject -issuer -dates -fingerprint -sha1
    echo
    
    # Verify PEM/DER consistency
    PEM_SHA1=$(openssl x509 -in "$MOK_CERT_PEM" -noout -fingerprint -sha1 | sed 's/^SHA1 Fingerprint=//')
    DER_SHA1=$(openssl x509 -inform DER -in "$MOK_CERT_DER" -noout -fingerprint -sha1 | sed 's/^SHA1 Fingerprint=//')
    
    if [ "$PEM_SHA1" = "$DER_SHA1" ]; then
        echo "✅ PEM and DER certificates match (SHA1: $PEM_SHA1)"
    else
        echo "❌ PEM and DER certificates differ!"
        echo "   PEM SHA1: $PEM_SHA1"
        echo "   DER SHA1: $DER_SHA1"
    fi
else
    echo "ℹ️  DER certificate not present at: $MOK_CERT_DER"
fi
echo

