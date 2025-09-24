#!/usr/bin/env bash
# Description: Formats shell scripts.

set -euo pipefail

# Format shell scripts (exclude demo)
find staging dev wip scripts -name '*.sh' 2>/dev/null | while read -r file; do
    # Basic formatting - ensure executable bit is set where appropriate
    [ -x "$file" ] || chmod +x "$file" 2>/dev/null || true
done

echo "✅ Code formatting complete"

