# scripts directory

This folder contains host-side helper scripts. They do not run inside UEFI; they prepare your system or ESP from Linux.

Key scripts
- install_clean_grub_boot.sh: Stage shim/grub and a minimal grub.cfg under EFI/PhoenixGuard on the ESP.
  Example:
    sudo ./scripts/install_clean_grub_boot.sh --esp /boot/efi --root-uuid <UUID>

- install_xen_snapshot_jump.sh: Stage xen.efi chainload and dom0 kernel/initrd onto the ESP.
  Example:
    sudo ./scripts/install_xen_snapshot_jump.sh --esp /boot/efi --dom0-vmlinuz /boot/vmlinuz-<ver> --dom0-initrd /boot/initrd.img-<ver>

Notes
- These scripts require root privileges when writing to the ESP.
- Read resources/xen/README.md for Xen usage and dom0 setup.

