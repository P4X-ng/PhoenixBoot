#!/usr/bin/env bash
# Description: Moves all demo code and artifacts to the demo/ directory.

set -euo pipefail

# Create demo subdirectories
mkdir -p demo/{qemu,testing,legacy,makefile}

# Move demo Makefile and related files
[ -f Makefile.demo ] && mv Makefile.demo demo/makefile/

# Move bak/ directory (contains demos)
[ -d bak ] && mv bak demo/legacy/

# Move examples
[ -d examples ] && mv examples demo/

# Move legacy directory
[ -d legacy ] && mv legacy demo/legacy-old

# Move test-related demo scripts
[ -d scripts ] && {
    mkdir -p demo/testing
    for script in scripts/test-* scripts/demo-* scripts/*demo*; do
        [ -f "$script" ] && mv "$script" demo/testing/ 2>/dev/null || true
    done
}

# Create demo README
printf '%s\n' \
    '# PhoenixGuard Demo Content' \
    '' \
    '⚠️  **This directory contains demonstration and testing content only.**' \
    '' \
    'Demo content is **excluded** from production builds and tests. This includes:' \
    '- QEMU testing scenarios' \
    '- Development prototypes' \
    '- Legacy code examples' \
    '- Interactive demonstrations' \
    '' \
    'For production builds, see the main Justfile targets.' \
    > demo/README.md

echo "✅ Demo code moved to demo/"

