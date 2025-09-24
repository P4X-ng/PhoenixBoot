#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib/common.sh

info "📦 Creating bootable ESP image (no sudo, mtools)"
[ -f out/staging/BootX64.efi ] || die "No BootX64.efi found - run 'just build' first"
require_cmd sbsign

ensure_dir out/esp

ESP_MB=${ESP_MB:-64}
if [ -n "${ISO_PATH:-}" ] && [ -f "${ISO_PATH}" ]; then
  ISO_BYTES=$(stat -c%s "${ISO_PATH}" 2>/dev/null || stat -f%z "${ISO_PATH}" 2>/dev/null || echo 0)
  ISO_MB=$(( (ISO_BYTES + 1048575) / 1048576 ))
  [ "$ISO_MB" -lt 64 ] && ISO_MB=64
  OVERHEAD_MB=${OVERHEAD_MB:-512}
  ESP_MB=$(( ISO_MB + OVERHEAD_MB ))
  info "Sizing ESP to ${ESP_MB} MiB for ISO inclusion (${ISO_MB} MiB ISO + ${OVERHEAD_MB} MiB overhead)"
fi

rm -f out/esp/esp.img
dd if=/dev/zero of=out/esp/esp.img bs=1M count=${ESP_MB}
mkfs.fat -F32 out/esp/esp.img

# Directories
mmd -i out/esp/esp.img ::/EFI || true
mmd -i out/esp/esp.img ::/EFI/BOOT || true
mmd -i out/esp/esp.img ::/EFI/PhoenixGuard || true
mmd -i out/esp/esp.img ::/boot || true
mmd -i out/esp/esp.img ::/boot/grub || true
mmd -i out/esp/esp.img ::/boot/grub/x86_64-efi || true

# Optional user cfg
if [ -f staging/config/grub/user.cfg ]; then
  ok "Including user.cfg from staging/config/grub/user.cfg"
  mcopy -i out/esp/esp.img -o staging/config/grub/user.cfg ::/EFI/PhoenixGuard/user.cfg
fi

# Bootloaders: sign PhoenixGuard with db and copy to default and vendor paths
if [ -f keys/db.key ] && [ -f keys/db.crt ]; then
  SIGNED_TMP=$(mktemp)
  sbsign --key keys/db.key --cert keys/db.crt \
    --output "$SIGNED_TMP" out/staging/BootX64.efi
  mcopy -i out/esp/esp.img -o "$SIGNED_TMP" ::/EFI/BOOT/BOOTX64.EFI
  mcopy -i out/esp/esp.img -o "$SIGNED_TMP" ::/EFI/PhoenixGuard/BootX64.efi
  rm -f "$SIGNED_TMP"
else
  die "DB signing keys missing (keys/db.key, keys/db.crt). Run 'just keygen' and 'just make-auth' to generate and enroll keys."
fi
if [ -f out/staging/KeyEnrollEdk2.efi ]; then
  mcopy -i out/esp/esp.img -o out/staging/KeyEnrollEdk2.efi ::/EFI/BOOT/KeyEnrollEdk2.efi
fi

# Shim/grub (best-effort)
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
  mcopy -i out/esp/esp.img -o "$GRUB_SRC" ::/EFI/PhoenixGuard/grubx64.efi
else
  warn "grubx64.efi not found on host; Clean GRUB Boot will skip grub"
fi
if [ -n "$SHIM_SRC" ]; then
  ok "Found shim at $SHIM_SRC"
  mcopy -i out/esp/esp.img -o "$SHIM_SRC" ::/EFI/PhoenixGuard/shimx64.efi
else
  info "shimx64.efi not found on host; will attempt direct GRUB chainload"
fi

# Modules
for mod in part_gpt fat iso9660 loopback normal linux efi_gop efi_uga search regexp test ls gzio; do
  [ -f "/usr/lib/grub/x86_64-efi/${mod}.mod" ] && mcopy -i out/esp/esp.img -o "/usr/lib/grub/x86_64-efi/${mod}.mod" ::/boot/grub/x86_64-efi/ || true
done

# Optional ISO
ISO_BASENAME=""; ISO_EXTRA_ARGS="${ISO_EXTRA_ARGS:-}"
if [ -n "${ISO_PATH:-}" ] && [ -f "${ISO_PATH}" ]; then
  ISO_BASENAME=$(basename "${ISO_PATH}")
  ok "Including ISO: ${ISO_PATH}"
  mmd -i out/esp/esp.img ::/ISO || true
  mcopy -i out/esp/esp.img -o "${ISO_PATH}" ::/ISO/"${ISO_BASENAME}"
fi

# UUID and sidecar from signed binary (hash local signed file again)
SIGNED_TMP2=$(mktemp)
sbsign --key keys/db.key --cert keys/db.crt \
  --output "$SIGNED_TMP2" out/staging/BootX64.efi
SIGNED_HASH=$(sha256sum "$SIGNED_TMP2" | awk '{print $1}')
BUILD_UUID=${BUILD_UUID:-${SIGNED_HASH:0:8}-${SIGNED_HASH:8:4}-${SIGNED_HASH:12:4}-${SIGNED_HASH:16:4}-${SIGNED_HASH:20:12}}
printf '%s\n' "$BUILD_UUID" > out/esp/BUILD_UUID
# Write attestation sidecar into ESP using mtools
SIDE_TMP=$(mktemp)
printf '%s\n' "$SIGNED_HASH" > "$SIDE_TMP"
mcopy -i out/esp/esp.img -o "$SIDE_TMP" ::/EFI/PhoenixGuard/NuclearBootEdk2.sha256
rm -f "$SIDE_TMP" "$SIGNED_TMP2"

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
  # Substitute ISO basename token
  ISO_BASENAME_ESC=$(printf '%s' "$ISO_BASENAME" | sed -e 's/[\\/&]/\\&/g')
  sed -i -e "s|@@ISO_BASENAME@@|${ISO_BASENAME_ESC}|g" "$APPEND_TMP"
  cat "$APPEND_TMP" >> "$GRUBCFG_TMP"
  rm -f "$APPEND_TMP"
fi

mcopy -i out/esp/esp.img -o "$GRUBCFG_TMP" ::/EFI/BOOT/grub.cfg
mcopy -i out/esp/esp.img -o "$GRUBCFG_TMP" ::/EFI/PhoenixGuard/grub.cfg
mcopy -i out/esp/esp.img -o "$GRUBCFG_TMP" ::/boot/grub/grub.cfg
rm -f "$GRUBCFG_TMP"

# Record OVMF paths
if [ -f out/setup/ovmf_code_path ] && [ -f out/setup/ovmf_vars_path ]; then
  OVMF_CODE_PATH=$(cat out/setup/ovmf_code_path)
  OVMF_VARS_PATH=$(cat out/setup/ovmf_vars_path)
  printf '%s\n%s\n' "$OVMF_CODE_PATH" "$OVMF_VARS_PATH" > out/esp/ovmf_paths.txt
  ok "Using discovered OVMF paths: $OVMF_CODE_PATH"
else
  die "OVMF paths not discovered - run 'just setup' first"
fi

sha256sum out/esp/esp.img > out/esp/esp.img.sha256
ok "ESP image created (no sudo): out/esp/esp.img"
