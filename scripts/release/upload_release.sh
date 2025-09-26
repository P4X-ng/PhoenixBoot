#!/usr/bin/env bash
# upload_release.sh - Create/update a GitHub Release and upload assets
# Requirements: gh CLI (preferred) or a valid GH_TOKEN environment variable for gh
# Usage examples:
#   ./upload_release.sh -t v0.1.0 -a path/to/file1 -a path/to/file2 -n "PhoenixGuard v0.1.0" -N "Release notes"
set -euo pipefail

TAG=""
NAME=""
NOTES=""
ASSETS=()

while getopts ":t:n:N:a:" opt; do
  case "$opt" in
    t) TAG="$OPTARG" ;;
    n) NAME="$OPTARG" ;;
    N) NOTES="$OPTARG" ;;
    a) ASSETS+=("$OPTARG") ;;
    :) echo "Option -$OPTARG requires an argument" >&2; exit 2 ;;
    ?) echo "Unknown option: -$OPTARG" >&2; exit 2 ;;
  esac
done

if [[ -z "$TAG" ]]; then
  echo "ERROR: tag is required (-t vX.Y.Z)" >&2
  exit 2
fi

# Resolve repo "owner/name" from origin URL
origin_url=$(git config --get remote.origin.url)
if [[ "$origin_url" =~ ^git@github.com:(.*)\.git$ ]]; then
  REPO="${BASH_REMATCH[1]}"
elif [[ "$origin_url" =~ ^https://github.com/(.*)\.git$ ]]; then
  REPO="${BASH_REMATCH[1]}"
else
  echo "ERROR: could not determine GitHub repo from origin: $origin_url" >&2
  exit 2
fi

# Prefer gh CLI if available
if command -v gh >/dev/null 2>&1; then
  # Create or update release
  if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
    # Update notes/title if provided
    if [[ -n "$NAME" || -n "$NOTES" ]]; then
      args=(release edit "$TAG" --repo "$REPO")
      [[ -n "$NAME" ]] && args+=(--title "$NAME")
      [[ -n "$NOTES" ]] && args+=(--notes "$NOTES")
      gh "${args[@]}"
    fi
  else
    args=(release create "$TAG" --repo "$REPO" --verify-tag)
    [[ -n "$NAME" ]] && args+=(--title "$NAME")
    [[ -n "$NOTES" ]] && args+=(--notes "$NOTES")
    gh "${args[@]}"
  fi

  # Upload assets with SHA256 sidecars
  for a in "${ASSETS[@]}"; do
    if [[ ! -f "$a" ]]; then
      echo "WARN: skipping missing asset: $a" >&2
      continue
    fi
    sha_file="$a.sha256"
    sha256sum "$a" | awk '{print $1}' > "$sha_file"
    gh release upload "$TAG" "$a" "$sha_file" --repo "$REPO" --clobber
  done
else
  echo "ERROR: gh CLI not found. Install gh or authenticate it."
  echo "       On Ubuntu: sudo apt install gh && gh auth login"
  exit 3
fi

echo "Release $TAG updated for $REPO"
