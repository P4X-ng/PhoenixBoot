#!/usr/bin/env bash
set -euo pipefail

# Validate latest progressive planfile under plans/
# Checks for core fields without external tools.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PLANS_DIR="$ROOT_DIR/plans"

latest_plan() {
  ls -1 "$PLANS_DIR"/phoenix_progressive_*.json 2>/dev/null | tail -n1
}

PLAN="$(latest_plan || true)"
if [ -z "${PLAN:-}" ]; then
  echo "No progressive planfile found in $PLANS_DIR" >&2
  exit 1
fi

echo "Validating planfile: $PLAN"

# Minimal JSON field checks using python (venv if available)
if [ -x "/home/punk/.venv/bin/python3" ]; then PY="/home/punk/.venv/bin/python3"; else PY="python3"; fi

"$PY" - "$PLAN" <<'PY'
import sys, json
p=sys.argv[1]
with open(p) as f:
    d=json.load(f)
# Required top-level fields
for k in ("tool","run","levels","outputs"):
    if k not in d:
        print(f"Missing field: {k}")
        sys.exit(2)
# Required tool fields
for k in ("name","version"):
    if k not in d["tool"]:
        print(f"Missing tool field: {k}")
        sys.exit(3)
# Run fields
for k in ("run_id","created_utc","dry_run"):
    if k not in d["run"]:
        print(f"Missing run field: {k}")
        sys.exit(4)
# Levels array sanity
if not isinstance(d["levels"], list):
    print("levels must be a list")
    sys.exit(5)
print("OK")
PY
