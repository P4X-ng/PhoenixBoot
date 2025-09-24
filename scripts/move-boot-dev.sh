#!/usr/bin/env bash
# Description: Moves hardware boot development code to the dev/ directory.

set -euo pipefail

# Move hardware-specific scripts
[ -d scripts ] && {
    mkdir -p dev/tools
    for script in scripts/hardware*.py scripts/*flashrom* scripts/*firmware* scripts/fix-*; do
        [ -f "$script" ] && mv "$script" dev/tools/ 2>/dev/null || true
    done
}

# Move hardware database and scraped data
[ -d hardware_database ] && mv hardware_database dev/
[ -d scraped_hardware ] && mv scraped_hardware dev/

echo "✅ Hardware boot development code moved to dev/"

