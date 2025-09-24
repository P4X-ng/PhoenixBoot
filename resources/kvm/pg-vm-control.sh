#!/usr/bin/env bash
set -euo pipefail

# PhoenixGuard VM and Host Control Script
# Provides cleanup, monitoring, and management functions

CFG=/etc/phoenixguard/kvm-snapshot.conf
[[ -f "$CFG" ]] && source "$CFG" || echo "Warning: Config not found: $CFG"

log() { echo "[pg-vm-control] $*"; }

usage() {
  cat <<EOF
PhoenixGuard VM Control Script

Usage: $0 <command> [options]

Commands:
  status        - Show VM and host status
  save          - Save VM snapshot
  stop          - Gracefully stop VM
  kill          - Force stop VM
  cleanup       - Clean up networking and reset GPU
  reset-gpu     - Unbind GPU from vfio-pci, rebind to original driver
  bind-gpu      - Bind GPU to vfio-pci for passthrough
  host-info     - Show host system information
  vm-console    - Connect to VM console (VNC viewer)
  ssh-vm        - SSH to VM (requires VM to be configured)

Examples:
  $0 status
  $0 save my-checkpoint
  $0 cleanup
  $0 reset-gpu
EOF
}

get_qemu_pid() {
  pgrep -f "qemu-system-x86_64.*$QCOW2" || true
}

vm_status() {
  local qemu_pid
  qemu_pid=$(get_qemu_pid)
  
  log "=== VM Status ==="
  if [[ -n "$qemu_pid" ]]; then
    echo "✅ VM Running (PID: $qemu_pid)"
    echo "   CPU Usage: $(ps -p "$qemu_pid" -o %cpu= 2>/dev/null || echo "unknown")%"
    echo "   Memory: $(ps -p "$qemu_pid" -o rss= 2>/dev/null || echo "unknown") KB"
    
    # Check monitor socket
    if [[ -S /tmp/qemu-monitor-socket ]]; then
      echo "✅ Monitor socket available"
      echo "   Connect with: socat - UNIX-CONNECT:/tmp/qemu-monitor-socket"
    fi
  else
    echo "❌ VM Not Running"
  fi
  
  # Network status
  if ip link show kvmbr0 >/dev/null 2>&1; then
    echo "✅ Bridge network active (kvmbr0)"
    ip addr show kvmbr0 | grep -E "inet |state"
  fi
  
  if ip link show kvmtap0 >/dev/null 2>&1; then
    echo "✅ TAP interface active (kvmtap0)"
  fi
}

host_info() {
  log "=== Host Information ==="
  echo "🖥️  Hostname: $(hostname)"
  echo "🔗 IP Address: $(ip route get 1 2>/dev/null | awk '{print $(NF-2); exit}' || echo "unknown")"
  echo "📊 Load: $(uptime | awk -F'load average:' '{print $2}')"
  echo "💾 Memory: $(free -h | awk '/^Mem:/ {print $3 "/" $2}')"
  echo "💿 Disk: $(df -h / | awk 'NR==2 {print $3 "/" $2 " (" $5 ")"}')"
  
  if [[ -n "${GPU_BDF:-}" ]]; then
    echo "🎮 GPU Status:"
    local gpu_driver
    gpu_driver=$(lspci -k -s "$GPU_BDF" | awk '/Kernel driver in use:/ {print $5}' || echo "none")
    echo "   $GPU_BDF -> $gpu_driver"
  fi
}

save_snapshot() {
  local snap_name="${1:-checkpoint-$(date +%Y%m%d-%H%M%S)}"
  local qemu_pid
  qemu_pid=$(get_qemu_pid)
  
  if [[ -z "$qemu_pid" ]]; then
    log "ERROR: VM not running, cannot save snapshot"
    exit 1
  fi
  
  log "Saving snapshot: $snap_name"
  echo "savevm $snap_name" | socat - UNIX-CONNECT:/tmp/qemu-monitor-socket
  log "Snapshot saved: $snap_name"
}

stop_vm() {
  local qemu_pid
  qemu_pid=$(get_qemu_pid)
  
  if [[ -z "$qemu_pid" ]]; then
    log "VM not running"
    return 0
  fi
  
  log "Gracefully stopping VM (PID: $qemu_pid)"
  echo "quit" | socat - UNIX-CONNECT:/tmp/qemu-monitor-socket 2>/dev/null || kill -TERM "$qemu_pid"
  
  # Wait for graceful shutdown
  local count=0
  while [[ -n "$(get_qemu_pid)" ]] && [[ $count -lt 30 ]]; do
    sleep 1
    ((count++))
  done
  
  if [[ -n "$(get_qemu_pid)" ]]; then
    log "Force killing VM..."
    kill -KILL "$qemu_pid" 2>/dev/null || true
  fi
  
  log "VM stopped"
}

kill_vm() {
  local qemu_pid
  qemu_pid=$(get_qemu_pid)
  
  if [[ -z "$qemu_pid" ]]; then
    log "VM not running"
    return 0
  fi
  
  log "Force stopping VM (PID: $qemu_pid)"
  kill -KILL "$qemu_pid"
  log "VM killed"
}

cleanup_network() {
  log "Cleaning up network interfaces..."
  
  # Remove TAP interface
  if ip link show kvmtap0 >/dev/null 2>&1; then
    ip link delete kvmtap0 || true
    log "Removed TAP interface"
  fi
  
  # Remove bridge (only if no other interfaces)
  if ip link show kvmbr0 >/dev/null 2>&1; then
    # Check if bridge has other slaves
    local slaves
    slaves=$(ls /sys/class/net/kvmbr0/brif/ 2>/dev/null | wc -l || echo 0)
    if [[ $slaves -eq 0 ]]; then
      ip link delete kvmbr0 || true
      log "Removed bridge interface"
    else
      log "Bridge has $slaves interfaces, keeping it"
    fi
  fi
}

reset_gpu() {
  [[ -n "${GPU_BDF:-}" ]] || { log "GPU_BDF not set"; return 1; }
  
  log "Resetting GPU: $GPU_BDF"
  
  # Unbind from vfio-pci
  echo "$GPU_BDF" > /sys/bus/pci/devices/$GPU_BDF/driver/unbind 2>/dev/null || true
  
  # Remove device ID from vfio-pci
  echo "${GPU_IDS:-}" > /sys/bus/pci/drivers/vfio-pci/remove_id 2>/dev/null || true
  
  # Rescan PCI bus to rebind to original driver
  echo 1 > /sys/bus/pci/rescan
  
  sleep 2
  
  # Check what driver it bound to
  local new_driver
  new_driver=$(lspci -k -s "$GPU_BDF" | awk '/Kernel driver in use:/ {print $5}' || echo "none")
  log "GPU $GPU_BDF now using driver: $new_driver"
}

bind_gpu() {
  [[ -n "${GPU_BDF:-}" && -n "${GPU_IDS:-}" ]] || { log "GPU_BDF/GPU_IDS not set"; return 1; }
  
  log "Binding GPU to vfio-pci: $GPU_BDF ($GPU_IDS)"
  
  # Add device ID to vfio-pci
  echo "$GPU_IDS" > /sys/bus/pci/drivers/vfio-pci/new_id 2>/dev/null || true
  
  # Unbind from current driver
  echo "$GPU_BDF" > /sys/bus/pci/devices/$GPU_BDF/driver/unbind 2>/dev/null || true
  
  # Bind to vfio-pci
  echo "$GPU_BDF" > /sys/bus/pci/drivers/vfio-pci/bind 2>/dev/null || true
  
  sleep 1
  
  # Verify binding
  local driver
  driver=$(lspci -k -s "$GPU_BDF" | awk '/Kernel driver in use:/ {print $5}' || echo "none")
  if [[ "$driver" == "vfio-pci" ]]; then
    log "✅ GPU bound to vfio-pci successfully"
  else
    log "❌ Failed to bind GPU to vfio-pci (current: $driver)"
  fi
}

cleanup_all() {
  log "🧹 Performing full cleanup..."
  stop_vm
  cleanup_network
  reset_gpu
  log "✅ Cleanup complete"
}

vm_console() {
  log "Opening VNC viewer for VM console..."
  if command -v vncviewer >/dev/null; then
    vncviewer :1 &
  elif command -v vinagre >/dev/null; then
    vinagre vnc://localhost:5901 &
  else
    log "No VNC viewer found. Install 'tigervnc-viewer' or 'vinagre'"
    log "Manual connection: VNC to localhost:5901"
  fi
}

ssh_vm() {
  local vm_ip="${1:-192.168.100.10}"
  log "Connecting to VM via SSH: $vm_ip"
  ssh -o ConnectTimeout=5 "$vm_ip"
}

# Main command dispatch
case "${1:-}" in
  status) vm_status;;
  host-info) host_info;;
  save) save_snapshot "${2:-}";;
  stop) stop_vm;;
  kill) kill_vm;;
  cleanup) cleanup_all;;
  reset-gpu) reset_gpu;;
  bind-gpu) bind_gpu;;
  vm-console) vm_console;;
  ssh-vm) ssh_vm "${2:-}";;
  *) usage; exit 1;;
esac
