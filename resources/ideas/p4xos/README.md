# P4XOS micro-host scaffold

This directory contains a minimal scaffold to prototype the P4XOS micro-host flow:
- Verify a signed manifest and hash for a target OS image
- Optionally set up dm-verity for that image
- Run Tegrity in offline mode against the mounted image/ESP
- Launch a clean OS via KVM/QEMU or Firecracker (not yet wired here)

Files
- init.sh
  - Reference init flow to run within the micro-host (UKI). Non-destructive.
- verify_manifest.py
  - Verifies manifest.json against manifest.json.sig using an RSA public key.
  - Streams SHA-256 of the image to compare with manifest.
- manifest.example.json
  - Example manifest structure with fields used by verify_manifest.py.

Usage (dev/demo)
- Build or place a signed UKI at: EFI/PhoenixGuard/P4XOS/p4xos-microhost.efi
- Place a verified root image (e.g., root.img) and manifest.json / manifest.json.sig somewhere accessible to the micro-host.
- In the micro-host, run:
    /EFI/PhoenixGuard/P4XOS/init.sh \
      --manifest /path/to/manifest.json \
      --signature /path/to/manifest.json.sig \
      --pubkey /path/to/public.pem \
      --image /path/to/root.img \
      --esp /path/to/esp
- After verification, mount and run Tegrity offline scan:
    python3 /Tegrity/scripts/tegrity.py boot --root /mnt/newroot --esp /mnt/esp

Notes
- This scaffold avoids destructive actions (no SPI writes, no ESP changes) by default.
- For Secure Boot simulation in QEMU, ensure an SB-enabled OVMF varstore is used.

