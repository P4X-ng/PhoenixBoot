#!/usr/bin/env bash
set -euo pipefail

# Common helpers for PhoenixGuard scripts
# Usage: source "$(dirname "$0")/lib/common.sh"

log()  { printf '%s\n' "$*"; }
info() { printf 'ℹ️  %s\n' "$*"; }
ok()   { printf '✅ %s\n' "$*"; }
warn() { printf '⚠️  %s\n' "$*"; }
err()  { printf '❌ %s\n' "$*" >&2; }
die()  { err "$*"; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

ensure_dir() {
  mkdir -p "$1"
}

unmount_if_mounted() {
  local mnt="$1"
  if mountpoint -q "$mnt" 2>/dev/null; then
    warn "Unmounting previous $mnt"
    sudo umount "$mnt" || sudo umount -l "$mnt" || true
  fi
  rmdir "$mnt" 2>/dev/null || true
}

detach_loops_for_image() {
  local img="$1"
  local loops
  loops=$(sudo losetup -j "$img" 2>/dev/null | cut -d: -f1 || true)
  if [ -n "${loops}" ]; then
    warn "Detaching loop devices for $img: ${loops}"
    echo "$loops" | xargs -r -n1 sudo losetup -d || true
  fi
}

mount_rw_loop() {
  local img="$1" mnt="$2"
  ensure_dir "$mnt"
  sudo mount -o loop,rw "$img" "$mnt" || die "Failed to mount $img rw at $mnt"
}

discover_ovmf() {
  local code vars
  if [ -f out/setup/ovmf_code_path ] && [ -f out/setup/ovmf_vars_path ]; then
    code=$(cat out/setup/ovmf_code_path)
    vars=$(cat out/setup/ovmf_vars_path)
    [ -f "$code" ] && [ -f "$vars" ] || return 1
    printf '%s\n' "$code" "$vars"
    return 0
  fi
  return 1
}

sha256_file() {
  sha256sum "$1" | awk '{print $1}'
}

