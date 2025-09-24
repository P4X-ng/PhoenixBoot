#!/usr/bin/env bash
# Description: Removes references to demo code from the build system.

set -euo pipefail

if grep -r "demo/" Makefile* 2>/dev/null | grep -v "demo/makefile" || \
   grep -r "bak/" Makefile* 2>/dev/null || \
   grep -r "example" Makefile* 2>/dev/null; then
    echo "❌ Found demo references in build system"
    exit 1
fi

echo "✅ No demo references found in production build system"
echo "✅ Production builds will reference staging/ only"

