#!/usr/bin/env bash
set -euo pipefail

# Generate a domU config to run an existing metal install under Xen.
# Supports disk passthrough (phy:/dev/...), optional controller/GPU passthrough.
#
# Usage:
#   sudo ./gen-domu-from-metal.sh --name p4xos --root /dev/nvme0n1 --out /etc/xen/p4xos.cfg [--gpu 0000:01:00.0,0000:01:00.1] [--ctrl 0000:03:00.0]

NAME=p4xos
ROOT_DEV=
OUT=/etc/xen/p4xos.cfg
GPU_BDFS=
CTRL_BDFS=
MEM=8192
VCPUS=4
BRIDGE=xenbr0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name) NAME="$2"; shift 2;;
    --root) ROOT_DEV="$2"; shift 2;;
    --out) OUT="$2"; shift 2;;
    --gpu) GPU_BDFS="$2"; shift 2;;
    --ctrl) CTRL_BDFS="$2"; shift 2;;
    --mem) MEM="$2"; shift 2;;
    --vcpus) VCPUS="$2"; shift 2;;
    --bridge) BRIDGE="$2"; shift 2;;
    *) echo "Unknown arg: $1"; exit 1;;
  esac
done

if [[ -z "$ROOT_DEV" ]]; then
  echo "--root /dev/.. required"
  exit 1
fi

mkdir -p "$(dirname "$OUT")"

cat > "$OUT" <<CFG
name = "$NAME"
builder = "hvm"
memory = $MEM
vcpus = $VCPUS
vif = [ 'bridge=$BRIDGE' ]
# Pass the whole disk as block backend
# NOTE: ensure dom0 does not mount this root while domU is running

disk = [ 'phy:$ROOT_DEV,xvda,rw' ]
boot = "c"
acpi = 1
apic = 1
vnc = 0
serial = "pty"

# Optional PCI passthrough (GPU, controller)
CFG

if [[ -n "$CTRL_BDFS" ]]; then
  echo -n "pci = [ " >> "$OUT"
  first=1
  IFS=',' read -ra arr <<< "$CTRL_BDFS"
  for b in "${arr[@]}"; do
    [[ $first -eq 0 ]] && echo -n ", " >> "$OUT"
    echo -n "'$b'" >> "$OUT"
    first=0
  done
  if [[ -n "$GPU_BDFS" ]]; then
    IFS=',' read -ra garr <<< "$GPU_BDFS"
    for b in "${garr[@]}"; do
      echo -n ", '$b'" >> "$OUT"
    done
  fi
  echo " ]" >> "$OUT"
elif [[ -n "$GPU_BDFS" ]]; then
  echo -n "pci = [ " >> "$OUT"
  first=1
  IFS=',' read -ra garr <<< "$GPU_BDFS"
  for b in "${garr[@]}"; do
    [[ $first -eq 0 ]] && echo -n ", " >> "$OUT"
    echo -n "'$b'" >> "$OUT"
    first=0
  done
  echo " ]" >> "$OUT"
fi

cat >> "$OUT" <<CFG
on_poweroff = "destroy"
on_reboot   = "restart"
on_crash    = "restart"
CFG

echo "Wrote domU config: $OUT"
echo "Reminder: bind devices to pciback (pciback.hide=...) and enable IOMMU (intel_iommu=on iommu=pt)."

