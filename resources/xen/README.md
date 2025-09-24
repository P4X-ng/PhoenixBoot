# Xen-based Snapshot Jump assets

This folder contains everything to enable NuclearBoot’s “Snapshot Jump (Xen)” and perform fast, safe remediation of bootkits.

Contents
- esp/EFI/Xen/xen.cfg           – Xen EFI boot config template (update to flat layout: xen.efi+xen.cfg+dom0-* at EFI root)
- dom0/p4xos-jump.service       – dom0 systemd unit to restore/create the domU
- dom0/p4xos-jump.sh            – remediation-aware helper (light checks + xl restore/create)
- dom0/bootkit-remediate.sh     – safe-by-default ESP/NVRAM/SPI audit + remediation script
- dom0/gen-domu-from-metal.sh   – generate a domU cfg from an existing metal install (disk/GPU/controller passthrough)
- domU/domU.cfg                 – sample HVM domU configuration

Install path (concise)
1) Install Xen on dom0 (Ubuntu/Debian)
- apt install xen-hypervisor-amd64 xen-utils-… efibootmgr grub-efi-amd64
- Ensure ESP mounted at /boot/efi.

2) Stage Xen Snapshot Jump assets on the ESP
- Provide dom0 kernel+initrd (from /boot):
  sudo ./scripts/install_xen_snapshot_jump.sh \
    --esp /boot/efi \
    --dom0-vmlinuz /boot/vmlinuz-<ver> \
    --dom0-initrd /boot/initrd.img-<ver> \
    [--uuid <DOM0-ROOT-UUID> | --dom0-root /dev/nvme0n1p2]
- The script attempts to auto-detect the UUID if you don’t pass one.
- Ensure xen.efi exists at /boot/efi/EFI/xen.efi (copy from /usr/lib/xen-*/boot/xen.efi if needed).

3) Enable dom0 restore service
- sudo install -m 755 resources/xen/dom0/p4xos-jump.sh /usr/local/sbin/p4xos-jump.sh
- sudo install -m 644 resources/xen/dom0/p4xos-jump.service /etc/systemd/system/p4xos-jump.service
- sudo systemctl enable p4xos-jump.service

4) First boot via NuclearBoot
- In NuclearBoot, press X for Snapshot Jump (Xen) to chainload xen.efi.
- Xen boots dom0 kernel/initrd from ESP; dom0 runs p4xos-jump.sh to restore or create the domU.

No-snapshot flow (remediation-first)
- Boot Xen → dom0, then run (dry run):
  BOOT_DEV=/dev/nvme0n1p1 resources/xen/dom0/bootkit-remediate.sh
- Review logs and /var/log/p4xos-bootkit-report.json; then run with P4XOS_CLEAN=1 (and AGGRESSIVE=1 if you want to quarantine non-whitelisted ESP items).
- To run your installed system safely under Xen:
  sudo resources/xen/dom0/gen-domu-from-metal.sh \
    --name p4xos --root /dev/nvme0n1 --out /etc/xen/p4xos.cfg \
    [--ctrl 0000:03:00.0] [--gpu 0000:01:00.0,0000:01:00.1]
  xl create /etc/xen/p4xos.cfg

IOMMU and pciback (for passthrough)
- Enable IOMMU and reserve devices for passthrough:
  - In GRUB (Xen cmdline): GRUB_CMDLINE_XEN_DEFAULT="dom0_mem=4096M,max:4096M loglvl=all guest_loglvl=all pciback.hide=(0000:01:00.0,0000:01:00.1,0000:03:00.0)"
  - In Linux cmdline: GRUB_CMDLINE_LINUX_DEFAULT="intel_iommu=on iommu=pt" (or amd_iommu=on)
- update-grub; reboot. Verify: lspci -nnk shows devices bound to pciback; IOMMU groups look sane.

Disk/GPU passthrough examples
- Disk block backend (simple):
  disk = [ 'phy:/dev/nvme0n1,xvda,rw' ]
- NVMe controller passthrough (best isolation):
  pci = [ '0000:03:00.0' ]
- GPU passthrough (include audio function):
  pci += [ '0000:01:00.0', '0000:01:00.1' ]
- Use a UEFI-capable guest for modern GPUs.

Return to metal (post-remediation)
- Reinstall bootloader (grub-install/update-grub or systemd-boot) to a clean ESP.
- Option A (clean boot): reboot firmware → OS boots normally.
- Option B (no firmware): kexec from dom0 into your metal root; useful to avoid re-running a tampered firmware during this session.

Threat model notes
- Snapshot Jump bypasses the tainted UEFI→bootloader path by resuming a VM.
- Dom0 provides tooling to inspect/repair EFI/NVRAM/SPI while domU runs.
- Extremely low-level firmware compromises can persist under any OS; use flashrom/chipsec/fwupd judiciously.

