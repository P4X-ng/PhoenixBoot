#!/usr/bin/env bash
# Description: Checks for required tools and firmware for the build process.

set -euo pipefail
mkdir -p out/setup

echo "Checking required toolchain..." > out/setup/report.txt
echo "=============================" >> out/setup/report.txt

MISSING=0
for tool in gcc qemu-system-x86_64 mtools mkfs.fat parted python3 mokutil openssl; do
    if command -v $tool >/dev/null 2>&1; then
        echo "✅ $tool: $(command -v $tool)" >> out/setup/report.txt
    else
        echo "❌ $tool: MISSING" >> out/setup/report.txt
        MISSING=1
    fi
done

# Dynamic OVMF firmware discovery
OVMF_CODE_PATH=""
OVMF_VARS_PATH=""
OVMF_SEARCH_PATHS=(
    "/usr/share/OVMF/OVMF_CODE_4M.fd:/usr/share/OVMF/OVMF_VARS_4M.fd"
    "/usr/share/OVMF/OVMF_CODE.fd:/usr/share/OVMF/OVMF_VARS.fd"
    "/usr/share/ovmf/OVMF_CODE_4M.fd:/usr/share/ovmf/OVMF_VARS_4M.fd"
    "/usr/share/ovmf/OVMF_CODE.fd:/usr/share/ovmf/OVMF_VARS.fd"
    "/usr/share/edk2-ovmf/OVMF_CODE.fd:/usr/share/edk2-ovmf/OVMF_VARS.fd"
    "/usr/share/qemu/OVMF_CODE.fd:/usr/share/qemu/OVMF_VARS.fd"
    "/opt/ovmf/OVMF_CODE.fd:/opt/ovmf/OVMF_VARS.fd"
)

for path_pair in "${OVMF_SEARCH_PATHS[@]}"; do
    CODE_PATH="${path_pair%:*}"
    VARS_PATH="${path_pair#*:}"
    if [ -f "$CODE_PATH" ] && [ -f "$VARS_PATH" ]; then
        OVMF_CODE_PATH="$CODE_PATH"
        OVMF_VARS_PATH="$VARS_PATH"
        echo "✅ OVMF: $CODE_PATH" >> out/setup/report.txt
        echo "      $VARS_PATH" >> out/setup/report.txt
        break
    fi
done

if [ -z "$OVMF_CODE_PATH" ]; then
    echo "❌ OVMF: MISSING (install ovmf package)" >> out/setup/report.txt
    MISSING=1
else
    echo "$OVMF_CODE_PATH" > out/setup/ovmf_code_path
    echo "$OVMF_VARS_PATH" > out/setup/ovmf_vars_path
fi

if [ $MISSING -eq 0 ]; then
    echo "✅ All required tools available"
    echo "SUCCESS: All tools available" >> out/setup/report.txt
else
    echo "❌ Missing tools found - check out/setup/report.txt"
    echo "FAILED: Missing required tools" >> out/setup/report.txt
    exit 1
fi

