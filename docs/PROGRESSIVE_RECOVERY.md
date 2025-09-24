# Progressive Recovery

This document describes the PhoenixGuard progressive recovery ladder and how to operate it safely in production.

Principles
- Safe-by-default: No host modifications unless you opt in (PG_HOST_OK=1).
- No demo contamination: Only production assets from staging/ and scripts/ are used.
- Auditability: Every run can produce a JSON planfile under plans/.
- Clear safety gates: Destructive steps require explicit confirmation.

Commands
- Interactive (safe defaults):
  just nuke progressive

- Dry run (planfile only, no changes):
  just nuke progressive-dry-run

- Individual levels:
  - Level 1 — Detect (read-only)
    just nuke level1-scan
  - Level 2 — ESP build (optional host deploy)
    just nuke level2-esp
    PG_HOST_OK=1 ISO_PATH=/path/to.iso just nuke level2-esp
  - Level 3 — Secure firmware access (double-kexec)
    just nuke level3-secure -- --backup current.bin
    just nuke level3-secure -- --read suspect.bin
    just nuke level3-secure -- --write drivers/G615LPAS.325
  - Level 4 — KVM Snapshot Jump
    just nuke level4-kvm
  - Level 5 — Xen Snapshot Jump prep
    just nuke level5-xen dom0_vmlinuz=/boot/vmlinuz-<ver> dom0_initrd=/boot/initrd.img-<ver> [esp=/boot/efi] [uuid=<UUID>] [dom0_root=/dev/nvme0n1p2]
  - Level 6 — Hardware recovery (danger)
    just nuke level6-hw fw=drivers/G615LPAS.325 [verify_only=1] [verbose=1]

Safety gates
- Level 1–2: Non-destructive; Level 2 can modify host ESP only if PG_HOST_OK=1 and you confirm.
- Level 3: Requires root; temporarily disables kernel lockdown and re-locks automatically.
- Level 4–5: Reboot paths; ensure configurations are prepared (KVM/Xen assets).
- Level 6: Dangerous; type-to-confirm inside the tool and ensure you have a programmer backup.

Planfile output
- Written to plans/phoenix_progressive_<timestamp>.json, includes:
  - run metadata: run_id, created_utc, environment
  - levels attempted with ok/err details
  - outputs: logs_dir and plan_path
  - errors: top-level unexpected errors

Baseline and scanning
- The scanner script (scripts/scan-bootkits.sh) will:
  - Use /home/punk/.venv/bin/python3 if present
  - Create baseline at out/baseline/firmware_baseline.json (unless overridden via BASELINE_JSON)
  - Save scan results to out/logs/bootkit_scan_results.json (unless overridden via SCAN_OUT)

Rollback guidance
- Level 2 (host deploy): Remove /etc/grub.d/42_phoenixguard_recovery and rerun update-grub.
- Level 3: A second kexec returns to lockdown=integrity; reboot restores kernel defaults.
- Level 4/5: Reboot back to metal and normal boot order; remove Xen/KVM assets if desired.
- Level 6: Reflash prior backup firmware image.

Troubleshooting
- OVMF not found: run just build setup then just build package-esp.
- ESP verification fails: inspect out/logs/esp-normalize-secure.log and ensure keys exist.
- Baseline analyzer missing: add dev/tools/analyze_firmware_baseline.py or specify BASELINE_JSON to an existing baseline.
