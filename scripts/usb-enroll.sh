#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib/common.sh

: "${USB1_DEV:?USB1_DEV is required, e.g. /dev/sdX}"
ENROLL_IMG=out/esp/enroll-esp.img
[ -f "$ENROLL_IMG" ] || die "Missing $ENROLL_IMG; run 'just package-esp-enroll-nosudo' first"

info "🔐 Preparing Secure Boot enrollment USB on ${USB1_DEV} (partition ${USB1_DEV}1)"

sudo mkdir -p /mnt/pgusb1 /mnt/enrollloop
sudo mount -o loop,ro "$ENROLL_IMG" /mnt/enrollloop
sudo mount "${USB1_DEV}1" /mnt/pgusb1

# Copy entire enrollment ESP contents onto USB
sudo rsync -a --inplace --chmod=Du=rwx,Dg=rx,Do=rx,Fu=rw,Fg=r,Fo=r /mnt/enrollloop/ /mnt/pgusb1/

sync
sudo umount /mnt/enrollloop || true
sudo umount /mnt/pgusb1 || true
rmdir /mnt/enrollloop /mnt/pgusb1 2>/dev/null || true

ok "Enrollment USB prepared on ${USB1_DEV}"

