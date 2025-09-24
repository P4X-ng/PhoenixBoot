#!/usr/bin/env bash
set -euo pipefail

# Install KVM Snapshot Jump (no Xen) and a backup remediation boot path.
# - Stages host kernel/initrd to ESP under EFI/PhoenixGuard
# - Appends GRUB entries for:
#     1) KVM Snapshot Jump (boots host, launches QEMU, resumes snapshot, with passthrough)
#     2) Remediation Boot (boots host into a service that runs fwupd/vendor flasher)
# - Installs host-side scripts + systemd units under /usr/local and /etc/systemd/system
#
# Usage (example; all values are hard-coded by args, no auto-detects):
#   sudo ./scripts/install_kvm_snapshot_jump.sh \
#     --esp /boot/efi \
#     --vmlinuz /boot/vmlinuz-6.8.0-xyz \
#     --initrd /boot/initrd.img-6.8.0-xyz \
#     --root-uuid bf07aefd-2d2e-4fa7-9f35-dc80637efce7 \
#     --qcow2 /var/lib/libvirt/images/metal.qcow2 \
#     --loadvm clean-snap \
#     --gpu-bdf 0000:02:00.0 --gpu-ids 10de:2d58 \
#     [--audio-bdf 0000:02:00.1] \
#     [--nvme-bdf 0000:03:00.0 --nvme-ids vvvv:dddd] \
#     [--firmware-capsule /path/fw.cab --firmware-capsule /path/other.cab]
#
# Notes:
# - Secure Boot is assumed: you should launch GRUB via shim or a trusted GRUB; this script only writes entries.
# - If passing through NVMe controller, it MUST NOT host the running root FS.
# - QEMU snapshot resume requires an internal savevm snapshot named by --loadvm.

ESP=
VMLINUZ=
INITRD=
ROOT_UUID=
QCOW2=
LOADVM=
GPU_BDF=
GPU_IDS=
AUDIO_BDF=
NVME_BDF=
NVME_IDS=
FIRMWARE_CAPSULES=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --esp) ESP="$2"; shift 2;;
    --vmlinuz) VMLINUZ="$2"; shift 2;;
    --initrd) INITRD="$2"; shift 2;;
    --root-uuid) ROOT_UUID="$2"; shift 2;;
    --qcow2) QCOW2="$2"; shift 2;;
    --loadvm) LOADVM="$2"; shift 2;;
    --gpu-bdf) GPU_BDF="$2"; shift 2;;
    --gpu-ids) GPU_IDS="$2"; shift 2;;
    --audio-bdf) AUDIO_BDF="$2"; shift 2;;
    --nvme-bdf) NVME_BDF="$2"; shift 2;;
    --nvme-ids) NVME_IDS="$2"; shift 2;;
    --firmware-capsule) FIRMWARE_CAPSULES+=("$2"); shift 2;;
    *) echo "Unknown arg: $1"; exit 1;;
  esac
done

# Basic validation
[[ -n "$ESP" && -d "$ESP" ]] || { echo "ESP path invalid or missing: $ESP"; exit 1; }
[[ -f "$VMLINUZ" ]] || { echo "vmlinuz not found: $VMLINUZ"; exit 1; }
[[ -f "$INITRD" ]] || { echo "initrd not found: $INITRD"; exit 1; }
[[ -n "$ROOT_UUID" ]] || { echo "--root-uuid required"; exit 1; }
[[ -f "$QCOW2" ]] || { echo "qcow2 not found: $QCOW2"; exit 1; }
[[ -n "$LOADVM" ]] || { echo "--loadvm <name> required"; exit 1; }
[[ -n "$GPU_BDF" && -n "$GPU_IDS" ]] || { echo "--gpu-bdf and --gpu-ids required"; exit 1; }

# Install host-side scripts
install -D -m 0755 resources/kvm/kvm-snapshot-jump.sh /usr/local/sbin/kvm-snapshot-jump.sh
install -D -m 0644 resources/kvm/kvm-snapshot-jump.service /etc/systemd/system/kvm-snapshot-jump.service
install -D -m 0755 resources/kvm/pg-remediate.sh /usr/local/sbin/pg-remediate.sh
install -D -m 0644 resources/kvm/pg-remediate.service /etc/systemd/system/pg-remediate.service

# Install enhanced setup script for comprehensive toolset
install -D -m 0755 resources/kvm/kvm-enhanced-setup.sh /opt/phoenixguard/tools/kvm-enhanced-setup.sh

# Generate a config file consumed by the scripts (hard-coded values written here)
CFG_DIR=/etc/phoenixguard
install -d -m 0755 "$CFG_DIR"
CFG="$CFG_DIR/kvm-snapshot.conf"
cat > "$CFG" <<CFG
# PhoenixGuard KVM Snapshot Jump configuration
ROOT_UUID="$ROOT_UUID"
QCOW2="$QCOW2"
LOADVM="$LOADVM"
GPU_BDF="$GPU_BDF"
GPU_IDS="$GPU_IDS"
AUDIO_BDF="${AUDIO_BDF:-}"
NVME_BDF="${NVME_BDF:-}"
NVME_IDS="${NVME_IDS:-}"
# Optional firmware capsules (space-delimited)
FIRMWARE_CAPSULES="${FIRMWARE_CAPSULES[*]:-}"
CFG
chmod 0644 "$CFG"

echo "Wrote config: $CFG"

# Stage kernel/initrd on ESP under PhoenixGuard
ESP_DIR="$ESP/EFI/PhoenixGuard"
install -d -m 0755 "$ESP_DIR"
cp -f "$VMLINUZ" "$ESP_DIR/vmlinuz"
cp -f "$INITRD" "$ESP_DIR/initrd.img"

# Append/ensure GRUB entries
GRUB_CFG="$ESP_DIR/grub.cfg"
if [[ ! -f "$GRUB_CFG" ]]; then
  echo "Creating new $GRUB_CFG"
  cat > "$GRUB_CFG" <<'BASE'
set timeout=2
set default=0

menuentry "Rescue shell" {
    insmod terminal
    terminal_output console
}
BASE
fi

# Build vfio ids param
VFIO_IDS="$GPU_IDS"
if [[ -n "${NVME_IDS:-}" ]]; then
  VFIO_IDS="${VFIO_IDS},${NVME_IDS}"
fi

# CPU/IOMMU params (Intel by default; adjust for AMD if needed)
IOMMU_PARAMS="intel_iommu=on iommu=pt rd.driver.pre=vfio-pci vfio-pci.ids=${VFIO_IDS} module_blacklist=nvidia,nvidia_drm,nvidia_modeset,nouveau"

# Add KVM Snapshot Jump entry
cat >> "$GRUB_CFG" <<'GRUB'

menuentry "KVM Snapshot Jump" {
    insmod part_gpt
    insmod fat
    search --no-floppy --file --set=esp /EFI/PhoenixGuard/vmlinuz
    linux ($esp)/EFI/PhoenixGuard/vmlinuz root=UUID=${ROOT_UUID} ro quiet ${IOMMU_PARAMS} systemd.unit=kvm-snapshot-jump.service
    initrd ($esp)/EFI/PhoenixGuard/initrd.img
}
GRUB

# Add Remediation Boot entry
cat >> "$GRUB_CFG" <<'GRUB'

menuentry "Remediation Boot (fwupd/vendor)" {
    insmod part_gpt
    insmod fat
    search --no-floppy --file --set=esp /EFI/PhoenixGuard/vmlinuz
    linux ($esp)/EFI/PhoenixGuard/vmlinuz root=UUID=${ROOT_UUID} ro quiet systemd.unit=pg-remediate.service
    initrd ($esp)/EFI/PhoenixGuard/initrd.img
}
GRUB

# Reload systemd units
systemctl daemon-reload || true

echo "Installed KVM Snapshot Jump + Remediation entries. Review: $GRUB_CFG"
echo "You can now reboot and select 'KVM Snapshot Jump' from PhoenixGuard's Clean GRUB path."
