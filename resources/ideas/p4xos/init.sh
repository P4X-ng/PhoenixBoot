#!/bin/sh
set -eu

# P4XOS init scaffold: verify manifest + image, optional dm-verity, mount RO, run Tegrity offline.
# Non-destructive. Requires: python3, openssl, sha256sum, (optional) veritysetup, losetup, mount.

usage() {
  echo "Usage: $0 --manifest M --signature S --pubkey K --image IMG [--esp ESP] [--verity]" 1>&2
}

MANIFEST=""
SIG=""
PUBKEY=""
IMAGE=""
ESP=""
DO_VERITY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --manifest) MANIFEST=$2; shift 2;;
    --signature) SIG=$2; shift 2;;
    --pubkey) PUBKEY=$2; shift 2;;
    --image) IMAGE=$2; shift 2;;
    --esp) ESP=$2; shift 2;;
    --verity) DO_VERITY=1; shift 1;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1" 1>&2; usage; exit 2;;
  esac
done

[ -n "$MANIFEST" ] && [ -n "$SIG" ] && [ -n "$PUBKEY" ] && [ -n "$IMAGE" ] || { usage; exit 2; }

# 1) Verify manifest signature and extract fields
SCRIPT_DIR=$(dirname "$0")
VERIFY_BIN="$SCRIPT_DIR/verify_manifest.py"
if [ ! -x "$VERIFY_BIN" ]; then
  echo "Error: verify_manifest.py not found or not executable at $VERIFY_BIN" 1>&2
  exit 2
fi

INFO_JSON=$(python3 "$VERIFY_BIN" --manifest "$MANIFEST" --signature "$SIG" --pubkey "$PUBKEY" --print)
IMG_EXPECT_SHA=$(printf '%s' "$INFO_JSON" | python3 -c 'import sys,json;print(json.load(sys.stdin)["sha256"])')
IMG_EXPECT_SIZE=$(printf '%s' "$INFO_JSON" | python3 -c 'import sys,json;print(json.load(sys.stdin)["size_bytes"])')
VERITY_ROOT=$(printf '%s' "$INFO_JSON" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("verity_roothash",""))')

# 2) Verify image hash and size
ACT_SIZE=$(stat -c '%s' "$IMAGE")
if [ "$IMG_EXPECT_SIZE" != "$ACT_SIZE" ]; then
  echo "Size mismatch: expected=$IMG_EXPECT_SIZE actual=$ACT_SIZE" 1>&2
  exit 3
fi
ACT_SHA=$(sha256sum "$IMAGE" | awk '{print $1}')
if [ "$IMG_EXPECT_SHA" != "$ACT_SHA" ]; then
  echo "SHA256 mismatch: expected=$IMG_EXPECT_SHA actual=$ACT_SHA" 1>&2
  exit 3
fi
echo "Image hash/size verified"

mkdir -p /mnt/newroot /mnt/esp

# 3) Optional: set up dm-verity
if [ "$DO_VERITY" -eq 1 ] && [ -n "$VERITY_ROOT" ]; then
  if ! command -v veritysetup >/dev/null 2>&1; then
    echo "veritysetup not available; proceeding without verity" 1>&2
  else
    LOOP=$(losetup -f --show "$IMAGE")
    veritysetup open "$LOOP" verity-root "$VERITY_ROOT" || { echo "veritysetup failed" 1>&2; exit 4; }
    mount -o ro /dev/mapper/verity-root /mnt/newroot || { echo "mount verity-root failed" 1>&2; exit 4; }
  fi
fi

# 4) If not using verity, mount image read-only via loop
if ! mountpoint -q /mnt/newroot; then
  LOOP=$(losetup -f --show -r "$IMAGE")
  mount -o ro "$LOOP" /mnt/newroot || { echo "mount loop failed" 1>&2; exit 4; }
fi

# 5) Mount ESP read-only if provided
if [ -n "$ESP" ]; then
  mount -o ro "$ESP" /mnt/esp || echo "Warning: failed to mount ESP at $ESP" 1>&2
fi

# 6) Run Tegrity offline boot scan if available
if [ -x /Tegrity/scripts/tegrity.py ]; then
  python3 /Tegrity/scripts/tegrity.py boot --root /mnt/newroot ${ESP:+--esp /mnt/esp}
else
  echo "Tegrity not found at /Tegrity/scripts/tegrity.py; skipping offline scan"
fi

echo "P4XOS init complete (non-destructive). New root mounted at /mnt/newroot (ro)."
exit 0
