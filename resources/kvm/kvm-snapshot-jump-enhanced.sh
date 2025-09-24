#!/usr/bin/env bash
set -euo pipefail

# Enhanced QEMU/KVM launcher with SSH access and bridged networking
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

# Start SSH daemon for host access
log "Ensuring SSH daemon is running for host access..."
systemctl start ssh || true
systemctl status ssh --no-pager -l || true

# Show host IP for SSH access
HOST_IP=$(ip route get 1 2>/dev/null | awk '{print $(NF-2); exit}' || echo "unknown")
log "🔗 HOST SSH ACCESS: ssh $(whoami)@$HOST_IP"
log "   You can manage the host/VM from another machine via SSH"

# Optional: ensure vfio bindings
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

# Setup bridge networking for better VM connectivity
BRIDGE_NAME="kvmbr0"
if ! ip link show "$BRIDGE_NAME" >/dev/null 2>&1; then
  log "Creating bridge $BRIDGE_NAME for VM networking..."
  ip link add name "$BRIDGE_NAME" type bridge || true
  ip link set dev "$BRIDGE_NAME" up || true
  # Give bridge an IP for SSH access to VM
  ip addr add 192.168.100.1/24 dev "$BRIDGE_NAME" || true
fi

# Create TAP interface for VM
TAP_IF="kvmtap0"
if ! ip link show "$TAP_IF" >/dev/null 2>&1; then
  log "Creating TAP interface $TAP_IF..."
  ip tuntap add "$TAP_IF" mode tap || true
  ip link set "$TAP_IF" master "$BRIDGE_NAME" || true
  ip link set dev "$TAP_IF" up || true
fi

# Build QEMU device args
DEV_ARGS=("-device" "vfio-pci,host=${GPU_BDF},multifunction=on,x-vga=on")
if [[ -n "${AUDIO_BDF:-}" ]]; then
  DEV_ARGS+=("-device" "vfio-pci,host=${AUDIO_BDF}")
fi
if [[ -n "${NVME_BDF:-}" ]]; then
  DEV_ARGS+=("-device" "vfio-pci,host=${NVME_BDF}")
fi

# OVMF Secure Boot configuration (respects user's Secure Boot preference)
if [[ -f "/usr/share/OVMF/OVMF_CODE_4M.secboot.fd" ]]; then
  # Use 4M OVMF for better compatibility
  OVMF_CODE="/usr/share/OVMF/OVMF_CODE_4M.secboot.fd"
  OVMF_VARS="/var/lib/qemu/OVMF_VARS_4M_kvmjump.fd"
  TEMPLATE_VARS="/usr/share/OVMF/OVMF_VARS_4M.ms.fd"
  
  # Create Secure Boot enabled varstore if it doesn't exist
  if [[ ! -f "$OVMF_VARS" ]]; then
    mkdir -p /var/lib/qemu
    # Use Microsoft keys template for Secure Boot compatibility
    install -D -m 0644 "$TEMPLATE_VARS" "$OVMF_VARS" || true
    log "🔐 Created Secure Boot enabled OVMF varstore"
  fi
  
elif [[ -f "/usr/share/OVMF/OVMF_CODE.secboot.fd" ]]; then
  # Fallback to regular OVMF
  OVMF_CODE="/usr/share/OVMF/OVMF_CODE.secboot.fd"
  OVMF_VARS="/var/lib/qemu/OVMF_VARS_kvmjump.fd"
  
  if [[ ! -f "$OVMF_VARS" ]]; then
    mkdir -p /var/lib/qemu
    install -D -m 0644 /usr/share/OVMF/OVMF_VARS.fd "$OVMF_VARS" || true
  fi
else
  log "WARNING: No Secure Boot OVMF found - VM will boot without Secure Boot"
  OVMF_CODE=""
  OVMF_VARS=""
fi

# Configure UEFI args
if [[ -n "$OVMF_CODE" && -f "$OVMF_CODE" ]]; then
  UEFI_ARGS=(
    -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE"
    -drive if=pflash,format=raw,file="$OVMF_VARS"
    -global ICH9-LPC.disable_s3=1  # Disable S3 for stability
    -global ICH9-LPC.disable_s4=1  # Disable S4 for stability
  )
  log "🔐 Using Secure Boot OVMF: $(basename "$OVMF_CODE")"
else
  UEFI_ARGS=()
  log "WARNING: Booting without UEFI/Secure Boot"
fi

# Enhanced networking - bridged for SSH access to VM
NET_ARGS=(
  "-netdev" "tap,id=net0,ifname=$TAP_IF,script=no,downscript=no"
  "-device" "virtio-net-pci,netdev=net0,mac=52:54:00:12:34:56"
)

# USB passthrough for peripherals (optional)
USB_ARGS=()
if [[ "${PASSTHROUGH_USB:-}" == "yes" ]]; then
  # Pass through USB keyboard/mouse for better control
  USB_ARGS+=("-usb" "-device" "usb-host,hostbus=1,hostaddr=2" "-device" "usb-host,hostbus=1,hostaddr=3")
fi

log "🚀 Launching QEMU with enhanced networking..."
log "   VM will be accessible at 192.168.100.x"
log "   Host SSH: ssh $(whoami)@$HOST_IP"
log "   Press Ctrl+Alt+G to release cursor in VNC"

# Wait a moment for user to see the message
sleep 3

# CPU topology detection for optimal passthrough
HOST_CORES=$(nproc)
VM_CORES=${VM_CORES:-$((HOST_CORES > 4 ? HOST_CORES - 2 : HOST_CORES / 2))}
VM_THREADS=${VM_THREADS:-2}  # SMT/HyperThreading

log "🖥️  Host CPU cores: $HOST_CORES, VM cores: $VM_CORES (threads: $VM_THREADS)"

# Enhanced CPU args for maximum performance
CPU_ARGS=(
  "-cpu" "host,migratable=no,+invtsc,+aes,+avx,+avx2,kvm=on"
  "-smp" "cores=$VM_CORES,threads=$VM_THREADS,sockets=1"
  "-machine" "type=q35,accel=kvm,kernel_irqchip=on,vmport=off"
)

# CPU pinning for performance isolation (if configured)
if [[ -n "${CPU_AFFINITY:-}" ]]; then
  # e.g., CPU_AFFINITY="4-7" to pin VM to cores 4-7
  CPU_ARGS+=("-object" "thread-context,id=tc1,cpu-affinity=$CPU_AFFINITY")
fi

# Launch QEMU and load snapshot
exec qemu-system-x86_64 \
  -enable-kvm \
  "${CPU_ARGS[@]}" \
  "${UEFI_ARGS[@]}" \
  -drive file="$QCOW2",if=virtio,aio=native,cache=none \
  "${DEV_ARGS[@]}" \
  "${NET_ARGS[@]}" \
  "${USB_ARGS[@]}" \
  -vnc :1 \
  -monitor unix:/tmp/qemu-monitor-socket,server,nowait \
  -loadvm "$LOADVM"
