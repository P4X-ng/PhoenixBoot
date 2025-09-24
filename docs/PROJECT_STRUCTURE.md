# PhoenixGuard Project Structure

This document helps you navigate the repository quickly.

Top-level overview
- NuclearBootEdk2.c / .inf / .efi: Main UEFI app (source, EDK2 INF, built binary)
- KeyEnrollEdk2.c / .inf: Minimal UEFI app to enroll custom Secure Boot keys
- Makefile: Unified entry point for builds, demos, tests, and Secure Boot helpers
- build-nuclear-boot-edk2.sh: Builds NuclearBoot with EDK2 toolchain
- demo-nuclear-boot-edk2-live.sh: QEMU live demo launcher (auto-stages OVMF, ESP)
- nuclear-boot-vars.fd: OVMF varstore file (created by demo or sb-prepare)
- resources/: Assets for GRUB and Xen paths; config templates
- scripts/: Installers for Clean GRUB Boot and Xen Snapshot Jump onto a real ESP
- vm-test/: Test VM assets and helpers for networking and demo testing
- legacy/: Archived prototypes, examples, and older scripts kept for reference
- OmegaImage/: Prior related work and PoC content (kept separate from core app)

Getting started
- make check-deps: Verify needed packages on Ubuntu
- make build: Build the NuclearBoot UEFI app
- make demo: Run the live QEMU demo
- make help: See all common targets
- make layout: Print the repo layout (top-level + depth 2)

Key directories
- resources/grub/esp/EFI/PhoenixGuard/
  - grub.cfg: Minimal clean GRUB config template (UUID-pinned)
- resources/xen/
  - README.md: Guide for Snapshot Jump (Xen) remediation path
  - dom0/: Scripts and systemd units for dom0 configuration
  - esp/: Templates to stage onto the ESP (xen.cfg)
- scripts/
  - install_clean_grub_boot.sh: Stage shim/grub and grub.cfg onto ESP
  - install_xen_snapshot_jump.sh: Stage Xen chainload assets onto ESP
- vm-test/
  - start-test-vm.sh: Run a prepared test VM under OVMF
  - simulate-cloudboot.sh: Simple cloudboot simulation
  - test-network-boot.sh: Network boot test helper

Secure Boot quick notes
- For QEMU testing with custom keys: make sb-demo-custom
- For signing our app with a local test db key: make sb-sign
- For staging signed shim/grub into the demo ESP: make stage-clean-grub

Conventions
- Do not commit generated binaries unless they are test fixtures (e.g., vm-test/OVMF_VARS_test.fd)
- Keep experimental/old content under legacy/
- Use Makefile targets instead of ad-hoc commands where possible

