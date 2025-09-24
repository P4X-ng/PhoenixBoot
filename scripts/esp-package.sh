#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib/common.sh

info "📦 Creating bootable ESP image..."
require_cmd dd
require_cmd mkfs.fat
require_cmd sbsign

ensure_dir out/esp
unmount_if_mounted out/esp/mount

detach_loops_for_image out/esp/esp.img

[ -f out/staging/BootX64.efi ] || die "No BootX64.efi found - run 'just build' first"

ESP_MB=${ESP_MB:-64}
if [ -n "${ISO_PATH:-}" ] && [ -f "${ISO_PATH}" ]; then
  ISO_BYTES=$(stat -c%s "${ISO_PATH}" 2>/dev/null || stat -f%z "${ISO_PATH}" 2>/dev/null || echo 0)
  ISO_MB=$(( (ISO_BYTES + 1048575) / 1048576 ))
  [ "$ISO_MB" -lt 64 ] && ISO_MB=64
  OVERHEAD_MB=${OVERHEAD_MB:-512}
  ESP_MB=$(( ISO_MB + OVERHEAD_MB ))
  info "Sizing ESP to ${ESP_MB} MiB for ISO inclusion (${ISO_MB} MiB ISO + ${OVERHEAD_MB} MiB overhead)"
fi

# Create image and FS
rm -f out/esp/esp.img
dd if=/dev/zero of=out/esp/esp.img bs=1M count=${ESP_MB} status=progress
mkfs.fat -F32 out/esp/esp.img

# Mount rw
ensure_dir out/esp/mount
mount_rw_loop out/esp/esp.img out/esp/mount

# Layout
sudo mkdir -p out/esp/mount/EFI/BOOT
sudo mkdir -p out/esp/mount/EFI/PhoenixGuard
sudo mkdir -p out/esp/mount/boot/grub

# Copy and sign PhoenixGuard with db key, place as default and vendor copy
if [ -f keys/db.key ] && [ -f keys/db.crt ]; then
  SIGNED_TMP=$(mktemp)
  sbsign --key keys/db.key --cert keys/db.crt \
    --output "$SIGNED_TMP" out/staging/BootX64.efi
  sudo install -D -m0644 "$SIGNED_TMP" out/esp/mount/EFI/BOOT/BOOTX64.EFI
  sudo install -D -m0644 "$SIGNED_TMP" out/esp/mount/EFI/PhoenixGuard/BootX64.efi
  rm -f "$SIGNED_TMP"
else
  die "DB signing keys missing (keys/db.key, keys/db.crt). Run 'just keygen' and 'just make-auth' to generate and enroll keys."
fi
[ -f out/staging/KeyEnrollEdk2.efi ] && sudo cp out/staging/KeyEnrollEdk2.efi out/esp/mount/EFI/BOOT/

# Optional GRUB fragment
if [ -f staging/config/grub/user.cfg ]; then
  ok "Including user.cfg from staging/config/grub/user.cfg"
  sudo install -D -m0644 staging/config/grub/user.cfg out/esp/mount/EFI/PhoenixGuard/user.cfg
fi

# Try to include shim and grub
GRUB_SRC=""; SHIM_SRC=""
for cand in \
  "/usr/lib/grub/x86_64-efi-signed/grubx64.efi.signed" \
  "/usr/lib/grub/x86_64-efi/grubx64.efi" \
  "/boot/efi/EFI/ubuntu/grubx64.efi" \
  "/boot/efi/EFI/Boot/grubx64.efi"; do
  [ -f "$cand" ] && GRUB_SRC="$cand" && break || true
done
for cand in \
  "/usr/lib/shim/shimx64.efi.signed" \
  "/usr/lib/shim/shimx64.efi" \
  "/boot/efi/EFI/ubuntu/shimx64.efi"; do
  [ -f "$cand" ] && SHIM_SRC="$cand" && break || true
done
if [ -n "$GRUB_SRC" ]; then
  ok "Found grub at $GRUB_SRC"
  sudo cp "$GRUB_SRC" out/esp/mount/EFI/PhoenixGuard/grubx64.efi
else
  warn "grubx64.efi not found on host; Clean GRUB Boot will skip grub"
fi
if [ -n "$SHIM_SRC" ]; then
  ok "Found shim at $SHIM_SRC"
  sudo cp "$SHIM_SRC" out/esp/mount/EFI/PhoenixGuard/shimx64.efi
else
  info "shimx64.efi not found on host; will attempt direct GRUB chainload"
fi

# Minimal GRUB modules (best-effort)
sudo mkdir -p out/esp/mount/boot/grub/x86_64-efi
for mod in part_gpt fat iso9660 loopback normal linux efi_gop efi_uga search regexp test ls gzio; do
  [ -f "/usr/lib/grub/x86_64-efi/${mod}.mod" ] && sudo cp "/usr/lib/grub/x86_64-efi/${mod}.mod" out/esp/mount/boot/grub/x86_64-efi/ || true
done

# Optional ISO
ISO_BASENAME=""; ISO_EXTRA_ARGS="${ISO_EXTRA_ARGS:-}"
if [ -n "${ISO_PATH:-}" ] && [ -f "${ISO_PATH}" ]; then
  ISO_BASENAME=$(basename "${ISO_PATH}")
  ok "Including ISO: ${ISO_PATH}"
  sudo mkdir -p out/esp/mount/ISO
  sudo cp "${ISO_PATH}" "out/esp/mount/ISO/${ISO_BASENAME}"
fi

# Build UUID and sidecar from signed binary on ESP
SIGNED_HASH=$(sudo sha256sum out/esp/mount/EFI/PhoenixGuard/BootX64.efi | awk '{print $1}')
BUILD_UUID=${BUILD_UUID:-${SIGNED_HASH:0:8}-${SIGNED_HASH:8:4}-${SIGNED_HASH:12:4}-${SIGNED_HASH:16:4}-${SIGNED_HASH:20:12}}
printf '%s\n' "$BUILD_UUID" > out/esp/BUILD_UUID
sudo bash -c "echo '$BUILD_UUID' > out/esp/mount/EFI/PhoenixGuard/ESP_UUID.txt"

sudo bash -c "echo $SIGNED_HASH > out/esp/mount/EFI/PhoenixGuard/NuclearBootEdk2.sha256"

# Render grub.cfg from template without expanding GRUB $ variables
TEMPLATE="scripts/templates/grub.cfg.tmpl"
[ -f "$TEMPLATE" ] || die "Template missing: $TEMPLATE"

TPL_TMP=$(mktemp)
cp "$TEMPLATE" "$TPL_TMP"

# sed-safe escape for replacements
_escape_sed() { printf '%s' "$1" | sed -e 's/[\\/&]/\\&/g'; }

BUILD_UUID_ESC=$(_escape_sed "$BUILD_UUID")
ISO_BASENAME_ESC=$(_escape_sed "$ISO_BASENAME")
ISO_EXTRA_ARGS_ESC=$(_escape_sed "$ISO_EXTRA_ARGS")

sed -i \
  -e "s|@@BUILD_UUID@@|${BUILD_UUID_ESC}|g" \
  -e "s|@@ISO_BASENAME@@|${ISO_BASENAME_ESC}|g" \
  -e "s|@@ISO_EXTRA_ARGS@@|${ISO_EXTRA_ARGS_ESC}|g" \
  "$TPL_TMP"

GRUBCFG_TMP=$(mktemp)
if [ -n "$ISO_BASENAME" ]; then
  # Keep ISO block, drop markers
  sed -e '/^# IF_HAS_ISO_START$/d' -e '/^# IF_HAS_ISO_END$/d' "$TPL_TMP" > "$GRUBCFG_TMP"
else
  # Remove ISO block entirely
  awk 'BEGIN{skip=0} /^# IF_HAS_ISO_START$/{skip=1;next} /^# IF_HAS_ISO_END$/{skip=0;next} skip==0{print}' "$TPL_TMP" > "$GRUBCFG_TMP"
fi
rm -f "$TPL_TMP"

# Append a robust auto-search ISO entry to handle unknown device paths
if [ -n "$ISO_BASENAME" ]; then
  APPEND_TMP=$(mktemp)
  cat > "$APPEND_TMP" <<'GRUBADD'
menuentry "Boot ISO (auto-search): @@ISO_BASENAME@@" {
  set isofile="/ISO/@@ISO_BASENAME@@"
  insmod search
  search --no-floppy --file $isofile --set=isodev
  if [ -z "$isodev" ]; then
    echo "ISO not found: $isofile"
    sleep 2
    return
  fi
  loopback loop ($isodev)$isofile
  if [ -f (loop)/casper/vmlinuz ]; then
    linux (loop)/casper/vmlinuz boot=casper iso-scan/filename=$isofile quiet splash ---
    if [ -f (loop)/casper/initrd ]; then
      initrd (loop)/casper/initrd
    fi
    boot
  elif [ -f (loop)/live/vmlinuz ]; then
    linux (loop)/live/vmlinuz boot=live iso-scan/filename=$isofile quiet splash ---
    if [ -f (loop)/live/initrd.img ]; then
      initrd (loop)/live/initrd.img
    fi
    boot
  elif [ -f (loop)/boot/vmlinuz ]; then
    linux (loop)/boot/vmlinuz iso-scan/filename=$isofile quiet splash ---
    if [ -f (loop)/boot/initrd ]; then
      initrd (loop)/boot/initrd
    fi
    boot
  else
    echo "No known kernel found inside ISO"
  fi
}
GRUBADD
  sed -i -e "s|@@ISO_BASENAME@@|${ISO_BASENAME_ESC}|g" "$APPEND_TMP"
  cat "$APPEND_TMP" >> "$GRUBCFG_TMP"
  rm -f "$APPEND_TMP"
fi

sudo cp "$GRUBCFG_TMP" out/esp/mount/EFI/BOOT/grub.cfg
sudo cp "$GRUBCFG_TMP" out/esp/mount/EFI/PhoenixGuard/grub.cfg
sudo cp "$GRUBCFG_TMP" out/esp/mount/boot/grub/grub.cfg
rm -f "$GRUBCFG_TMP"

# Unmount and finalize
sudo umount out/esp/mount
rmdir out/esp/mount
sha256sum out/esp/esp.img > out/esp/esp.img.sha256

# Record OVMF paths if discovered
if [ -f out/setup/ovmf_code_path ] && [ -f out/setup/ovmf_vars_path ]; then
  OVMF_CODE_PATH=$(cat out/setup/ovmf_code_path)
  OVMF_VARS_PATH=$(cat out/setup/ovmf_vars_path)
  printf '%s\n%s\n' "$OVMF_CODE_PATH" "$OVMF_VARS_PATH" > out/esp/ovmf_paths.txt
  ok "Using discovered OVMF paths: $OVMF_CODE_PATH"
else
  die "OVMF paths not discovered - run 'just setup' first"
fi

ok "ESP image created: out/esp/esp.img"

