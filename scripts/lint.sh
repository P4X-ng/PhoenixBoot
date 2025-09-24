#!/usr/bin/env bash
# Description: Lints C and Python source files.

set -euo pipefail

# Lint C sources in staging and dev (exclude demo)
find staging dev wip -name '*.c' -o -name '*.h' 2>/dev/null | while read -r file; do
    echo "Linting $file" >> out/lint/c_lint.log
    # Use basic syntax checking since we may not have full linters
    gcc -fsyntax-only "$file" 2>> out/lint/c_lint.log || true
done

# Lint Python sources
find staging dev wip scripts -name '*.py' 2>/dev/null | while read -r file; do
    echo "Linting $file" >> out/lint/python_lint.log
    python3 -m py_compile "$file" 2>> out/lint/python_lint.log || true
done

echo "✅ Static analysis complete - see out/lint/"

