#!/usr/bin/env bash
# Description: Moves production-ready code to the staging/ directory.

set -euo pipefail

# Move core UEFI application files
[ -f NuclearBootEdk2.c ] && mv NuclearBootEdk2.c staging/src/
[ -f NuclearBootEdk2.inf ] && mv NuclearBootEdk2.inf staging/src/
[ -f NuclearBootEdk2.efi ] && mv NuclearBootEdk2.efi staging/boot/
[ -f KeyEnrollEdk2.c ] && mv KeyEnrollEdk2.c staging/src/
[ -f KeyEnrollEdk2.inf ] && mv KeyEnrollEdk2.inf staging/src/
[ -f KeyEnrollEdk2.efi ] && mv KeyEnrollEdk2.efi staging/boot/

# Move build script to staging tools
[ -f build-nuclear-boot-edk2.sh ] && mv build-nuclear-boot-edk2.sh staging/tools/

# Move production headers
[ -f PhoenixGuardDemo.h ] && mv PhoenixGuardDemo.h staging/include/ 2>/dev/null || true

echo "✅ Production code moved to staging/"

