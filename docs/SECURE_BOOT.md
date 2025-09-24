# Secure Boot with PhoenixGuard

This guide covers how to test and use Secure Boot with the NuclearBoot UEFI app in QEMU and on real hardware.

Paths and artifacts
- NuclearBootEdk2.efi: Unsigned build product (make build)
- NuclearBootEdk2.signed.efi: Locally signed app (make sb-sign)
- nuclear-boot-vars.fd: OVMF varstore used by demo (make sb-prepare or created by demo)
- nuclear-boot-demo/EFI/PhoenixGuard/: Demo ESP content

Quick recipes
1) Verify dependencies (Ubuntu):
   make check-deps

2) Sign the app with a local test key:
   make sb-sign
   - Produces NuclearBootEdk2.signed.efi (trusted only if your firmware db contains SB_DB_CRT)

3) Enroll custom Secure Boot keys in QEMU:
   make sb-demo-custom
   - This stages pk.auth, kek.auth, db.auth into the demo ESP and tries to launch KeyTool.efi if present.
   - In the UEFI shell, follow startup.nsh or run KeyTool manually and enroll PK, then KEK, then db.
   - Reboot and enable Secure Boot in OVMF (if not already).

4) Run demo with a pre-populated Secure Boot varstore:
   make demo-secureboot
   - If vm-test/OVMF_VARS_test.fd exists, it will be copied to nuclear-boot-vars.fd.

Using shim and signed GRUB
- On Ubuntu, shim-signed and grub-efi-amd64-signed provide Microsoft-signed shim and GRUB (or shim + vendor-signed GRUB) suitable for Secure Boot.
- Use make stage-clean-grub to copy shimx64.efi and grubx64.efi into the demo ESP under EFI/PhoenixGuard/.
- In Secure Boot mode, prefer launching shimx64.efi; shim will validate and chainload grubx64.efi according to its trust configuration.

Real hardware notes
- Most systems ship with Microsoft keys enrolled; shimx64.efi.signed should run out of the box.
- If using locally signed NuclearBootEdk2.signed.efi, you must enroll your test db certificate into firmware db.
- Use KeyEnrollEdk2.efi or firmware setup to enroll PK/KEK/db when testing custom chains.

Troubleshooting
- If QEMU shows a forbidden signature error, confirm Secure Boot state and whether the executable is signed by an enrolled key.
- If OVMF lacks Microsoft keys, shim may not verify; instead use your own keys (sb-demo-custom) or a varstore with appropriate db.
- For missing tools: sudo apt install shim-signed grub-efi-amd64-signed sbsigntool efitools openssl ovmf qemu-system-x86

