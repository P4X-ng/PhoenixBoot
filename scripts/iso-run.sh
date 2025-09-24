#!/usr/bin/env bash
# Description: Prepares an ESP with an ISO and boots it in QEMU.

set -euo pipefail

[ -n "${ISO_PATH:-}" ] || { echo "❌ ISO_PATH=/path.iso is required"; exit 1; }

just --justfile Justfile setup
just --justfile Justfile build

# Build an ESP containing the ISO
ISO_PATH="${ISO_PATH}" just --justfile Justfile package-esp-iso

# Ensure Secure Boot shim is the default BOOTX64
just --justfile Justfile valid-esp-secure

# Verify and boot in QEMU (headless)
just --justfile Justfile verify-esp-robust
just --justfile Justfile qemu-test

echo "✅ ISO run completed"

