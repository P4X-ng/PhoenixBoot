#!/usr/bin/env bash
set -euo pipefail

# PhoenixGuard KVM Snapshot Jump - Enhanced Recovery Edition
# Launches comprehensive recovery environment with full toolset

# Launch QEMU/KVM and resume a snapshot with passthrough.
# Reads configuration from /etc/phoenixguard/kvm-snapshot.conf

CFG=/etc/phoenixguard/kvm-snapshot.conf
[[ -f "$CFG" ]] || { echo "Missing config: $CFG"; exit 1; }
# shellcheck disable=SC1090
source "$CFG"

log() { echo "[kvm-snapshot-jump] $*"; }

# Verify root UUID matches expected
ROOT_SRC=$(findmnt -n -o SOURCE / || true)
ROOT_UUID_CUR=$(blkid -s UUID -o value "$ROOT_SRC" 2>/dev/null || true)
if [[ "$ROOT_UUID_CUR" != "$ROOT_UUID" ]]; then
  log "ERROR: Running root UUID ($ROOT_UUID_CUR) != expected ($ROOT_UUID). Aborting."
  exit 1
fi

# Verify qcow2 and snapshot name
[[ -f "$QCOW2" ]] || { log "Missing qcow2: $QCOW2"; exit 1; }
[[ -n "$LOADVM" ]] || { log "LOADVM name not set"; exit 1; }

# Optional: ensure vfio bindings (best when done at boot via vfio-pci.ids)
ensure_bound() {
  local bdf="$1"
  [[ -z "$bdf" ]] && return 0
  if [[ ! -e "/sys/bus/pci/devices/$bdf/driver" ]]; then
    log "WARN: $bdf has no driver bound"
    return 0
  fi
  local drv
  drv=$(basename "$(readlink -f "/sys/bus/pci/devices/$bdf/driver")")
  if [[ "$drv" != "vfio-pci" ]]; then
    log "ERROR: $bdf bound to $drv (expected vfio-pci)."
    exit 1
  fi
}

ensure_bound "$GPU_BDF"
ensure_bound "${AUDIO_BDF:-}"
ensure_bound "${NVME_BDF:-}"

# Build QEMU device args
DEV_ARGS=("-device" "vfio-pci,host=${GPU_BDF},multifunction=on,x-vga=on")
if [[ -n "${AUDIO_BDF:-}" ]]; then
  DEV_ARGS+=("-device" "vfio-pci,host=${AUDIO_BDF}")
fi
if [[ -n "${NVME_BDF:-}" ]]; then
  DEV_ARGS+=("-device" "vfio-pci,host=${NVME_BDF}")
fi

# OVMF varstore path (writable copy)
OVMF_CODE="/usr/share/OVMF/OVMF_CODE.secboot.fd"
OVMF_VARS="/var/lib/qemu/OVMF_VARS_kvmjump.fd"
if [[ -f "$OVMF_CODE" ]]; then
  if [[ ! -f "$OVMF_VARS" ]]; then
    install -D -m 0644 /usr/share/OVMF/OVMF_VARS.fd "$OVMF_VARS" || true
  fi
  UEFI_ARGS=(
    -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE"
    -drive if=pflash,format=raw,file="$OVMF_VARS"
  )
else
  UEFI_ARGS=()
fi

# Networking (user-mode by default; adjust as needed)
NET_ARGS=("-netdev" "user,id=net0" "-device" "virtio-net-pci,netdev=net0")

# Launch QEMU and load snapshot
exec qemu-system-x86_64 \
  -enable-kvm -cpu host -machine type=q35,accel=kvm \
  -smp 8 -m 16384 \
  "${UEFI_ARGS[@]}" \
  -drive file="$QCOW2",if=virtio,aio=native,cache=none \
  "${DEV_ARGS[@]}" \
  "${NET_ARGS[@]}" \
  -loadvm "$LOADVM"
