#!/usr/bin/env bash
# Description: Runs all tests found in the staging/tests directory.

set -euo pipefail

if [ -d staging/tests ] && [ -n "$(find staging/tests -name '*.py' -o -name '*.sh' 2>/dev/null)" ]; then
    echo "Running staging tests..."
    source /home/punk/.venv/bin/activate
    find staging/tests -name '*.py' -exec python3 {} \;
    find staging/tests -name '*.sh' -exec bash {} \;
fi

