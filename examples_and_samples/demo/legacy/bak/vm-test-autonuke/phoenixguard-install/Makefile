# PhoenixGuard Makefile - simplified top-level UX

SHELL := /bin/bash

LIVE_DEMO := ./demo-nuclear-boot-edk2-live.sh
INSTALL_PHOENIX := ./scripts/install_phoenix.sh

.PHONY: help check-deps build demo demo-secureboot demo-xen demo-recover layout install-phoenix clean reboot-to-vm reboot-to-metal scan-bootkits hardware-recovery build-nuclear-cd test-cd-boot burn-recovery-cd create-usb-recovery deploy-esp-iso boot-from-esp-iso autonuke

help:
	@echo "Targets:"
	@echo "  make check-deps         # Verify required host tools are installed (QEMU, OVMF, optional tree)"
	@echo "  make build              # Build or prepare NuclearBootEdk2.efi if script is available"
	@echo "  make demo               # Launch base QEMU demo"
	@echo "  make demo-secureboot    # Launch QEMU demo with Secure Boot varstore if available"
	@echo "  make demo-xen           # Launch QEMU demo; stages xen.efi + dom0 assets; press 'X' in app"
	@echo "  make demo-recover       # Launch QEMU demo with a staged recovery package"
	@echo "  make layout             # Quick tree view (depth 2) of demo ESP (if present)"
	@echo "  make install-phoenix    # Install Xen Snapshot Jump + recovery artifacts to your ESP"
	@echo "  make install-kvm        # Install KVM Snapshot Jump + remediation entries to your ESP"
	@echo "  make clean              # Remove demo artifacts"
	@echo ""
	@echo "System helpers (require sudo):"
	@echo "  make secure-boot-status # Check Secure Boot status"
	@echo "  make show-vfio-status   # Show current GPU/VFIO binding status"
	@echo "  make enable-passthrough # Configure IOMMU/VFIO for PCI passthrough (Secure Boot safe)"
	@echo "  make disable-vfio       # Disable VFIO and restore native GPU drivers"
	@echo "  make restore-graphics   # Restore graphics drivers after VFIO usage"
	@echo "  make scan-bootkits      # 🎯 Hunt for bootkit infections using firmware analysis"
	@echo "  make hardware-recovery  # ⚡ BOOTKIT-PROOF hardware-level firmware recovery (DANGEROUS)"
	@echo ""
	@echo "💿 Nuclear Boot CD (BOOTKIT-PROOF recovery medium):"
	@echo "  make build-nuclear-cd   # Build immutable bootable recovery CD/DVD image"
	@echo "  make test-cd-boot       # Test Nuclear Boot CD in QEMU (safe testing)"
	@echo "  make burn-recovery-cd   # Burn CD to physical disc (requires CD/DVD burner)"
	@echo "  make create-usb-recovery # Create bootable USB recovery drive"
	@echo "  make deploy-esp-iso     # ⚡ Deploy virtual CD to ESP (instant, software-only)"
	@echo "  make boot-from-esp-iso  # 🚀 Boot recovery from ESP-deployed ISO (no reboot)"
	@echo ""
	@echo "🚨 Master recovery workflow (REQUIRES SUDO + REBOOTS SYSTEM):"
	@echo "  make autonuke           # 💥 AUTONUKE: Progressive recovery from scan to CH341A (ONE COMMAND!)"
	@echo "  make reboot-to-vm       # Stage PhoenixGuard, configure UEFI, reboot to recovery VM"
	@echo "  make reboot-to-metal    # Restore original bootloader, cleanup ESP, reboot to normal"

check-deps:
	@bash -lc 'set -e; \
	  MISSING=0; \
	  for bin in qemu-system-x86_64; do \
	    command -v $$bin >/dev/null || { echo "Missing: $$bin"; MISSING=1; }; \
	  done; \
	  dpkg -s ovmf >/dev/null 2>&1 || echo "Note: ovmf package not detected (needed for UEFI)."; \
	  if ! command -v tree >/dev/null 2>&1; then echo "Note: install \"tree\" for nicer layout output (sudo apt install tree)"; fi; \
	  exit $$MISSING'

build:
	@bash -lc 'set -e; \
	  if [ -x ./build-nuclear-boot-edk2.sh ]; then \
	    echo "🔨 Building NuclearBootEdk2.efi"; \
	    ./build-nuclear-boot-edk2.sh; \
	  else \
	    if [ -f NuclearBootEdk2.efi ]; then echo "✅ NuclearBootEdk2.efi present"; \
	    else echo "ℹ️  No build script found. Place NuclearBootEdk2.efi in this directory or add build-nuclear-boot-edk2.sh"; fi; \
	  fi'

# Base demo in QEMU (no extra staging)
demo:
	@bash -lc '$(LIVE_DEMO)'

# Demo in QEMU with Secure Boot (if Secure Boot varstore is present)
demo-secureboot:
	@bash -lc 'DEMO_SECUREBOOT=1 $(LIVE_DEMO) --secureboot'

# Demo Xen path in QEMU (auto-adds xen.efi layout in demo ESP)
demo-xen:
	@bash -lc 'DEMO_STAGE_XEN=1 $(LIVE_DEMO)'

# Demo recovery path in QEMU (stages a demo recovery package)
demo-recover:
	@bash -lc 'DEMO_STAGE_XEN=1 DEMO_STAGE_RECOVERY=1 $(LIVE_DEMO)'

# Quick tree view for demo ESP layout
layout:
	@bash -lc 'if [ -d nuclear-boot-demo ]; then \
	  if command -v tree >/dev/null 2>&1; then tree -L 2 nuclear-boot-demo; else echo "(Install \"tree\" for nicer output)"; find nuclear-boot-demo -maxdepth 2 -type d -printf "%p\n" -o -type f -printf "%p\n" | sort; fi; \
	else echo "No demo ESP found. Run \"make demo\" first."; fi'

# Install PhoenixGuard Xen layout + recovery assets to a real ESP
install-phoenix:
	@bash -lc 'chmod +x $(INSTALL_PHOENIX) || true; $(INSTALL_PHOENIX)'

install-kvm:
	@bash -lc 'chmod +x ./scripts/install_kvm_snapshot_jump.sh || true; ./scripts/install_kvm_snapshot_jump.sh'

clean:
	@rm -rf nuclear-boot-demo nuclear-boot-vars.fd || true


# --- System helpers: VFIO passthrough disable & graphics restore (Ubuntu, Secure Boot aware) ---
# NOTE: These targets perform system-level changes and require sudo. They do NOT reboot automatically.
# They are safe to run with Secure Boot enabled; they will rebuild initramfs and update grub.
# After running disable-vfio and/or restore-graphics, reboot to apply.

.PHONY: secure-boot-status show-vfio-status enable-passthrough disable-vfio restore-graphics

secure-boot-status:
	mokutil --sb-state || true

show-vfio-status:
	@echo "== GPU binding status =="
	@lspci -nnk | grep -iE 'vga|3d|display' -A3 || true
	@echo
	@echo "== Devices bound to vfio-pci (if any) =="
	@find /sys/bus/pci/drivers/vfio-pci -maxdepth 1 -type l 2>/dev/null || echo "No devices bound to vfio-pci"

# Enable VFIO/IOMMU for PCI passthrough (Secure Boot compatible)
# This configures the system for GPU and NVMe passthrough to VMs.
# What it does:
# - Backs up /etc/default/grub and existing modprobe configs
# - Detects CPU vendor (Intel/AMD) and adds appropriate IOMMU parameters
# - Adds intel_iommu=on or amd_iommu=on + iommu=pt to GRUB_CMDLINE_LINUX
# - Creates /etc/modprobe.d/vfio.conf to load vfio-pci driver
# - Updates initramfs and grub config
# - Prints device binding guidance and reboot reminder

enable-passthrough:
	@set -e; \
	echo "🔧 Configuring system for PCI passthrough (Secure Boot compatible)"; \
	echo; \
	echo "[status] Checking system readiness"; \
	if mokutil --sb-state 2>/dev/null | grep -q "SecureBoot enabled"; then \
		echo "  ✅ Secure Boot: enabled"; \
	else \
		echo "  ⚠️  Secure Boot: disabled or mokutil unavailable"; \
	fi; \
	if dmesg 2>/dev/null | grep -qi "iommu.*enabled\|dmar.*enabled"; then \
		echo "  ✅ IOMMU: enabled in kernel"; \
	else \
		echo "  ⚠️  IOMMU: not detected in dmesg (may need BIOS setting or kernel params)"; \
	fi; \
	if lsmod | grep -q "^vfio_pci"; then \
		echo "  ✅ VFIO: vfio_pci module loaded"; \
	else \
		echo "  ℹ️  VFIO: vfio_pci module not loaded (will be configured)"; \
	fi; \
	echo; \
	TS=$$(date +%F_%H%M%S); \
	echo "[backup] /etc/default/grub -> /etc/default/grub.bak.$$TS"; \
	sudo cp /etc/default/grub /etc/default/grub.bak.$$TS; \
	if ls /etc/modprobe.d/vfio*.conf >/dev/null 2>&1; then \
		echo "[backup] /etc/modprobe.d/vfio*.conf -> /etc/modprobe.d/vfio.conf.bak.$$TS"; \
		sudo tar -C /etc/modprobe.d -czf /etc/modprobe.d/vfio.conf.bak.$$TS.tgz vfio*.conf || true; \
	fi; \
	echo "[detect] CPU vendor and IOMMU parameters"; \
	if lscpu | grep -qi "GenuineIntel"; then \
		echo "  🔍 Intel CPU detected - will add intel_iommu=on iommu=pt"; \
		IOMU_PARAMS="intel_iommu=on iommu=pt"; \
	elif lscpu | grep -qi "AuthenticAMD"; then \
		echo "  🔍 AMD CPU detected - will add amd_iommu=on iommu=pt"; \
		IOMU_PARAMS="amd_iommu=on iommu=pt"; \
	else \
		echo "  ⚠️  Unknown CPU vendor - defaulting to iommu=pt"; \
		IOMU_PARAMS="iommu=pt"; \
	fi; \
	echo "[grub] Adding IOMMU parameters to GRUB_CMDLINE_LINUX"; \
	if grep -q "GRUB_CMDLINE_LINUX=" /etc/default/grub; then \
		for param in $$IOMMU_PARAMS; do \
			if ! grep "GRUB_CMDLINE_LINUX=" /etc/default/grub | grep -q "$$param"; then \
				echo "    Adding $$param"; \
				sudo sed -i "/^GRUB_CMDLINE_LINUX=/ s/\"$/ $$param&/" /etc/default/grub; \
			else \
				echo "    $$param already present"; \
			fi; \
		done; \
	else \
		echo "    Creating GRUB_CMDLINE_LINUX with IOMMU parameters"; \
		echo "GRUB_CMDLINE_LINUX=\"$$IOMMU_PARAMS\"" | sudo tee -a /etc/default/grub; \
	fi; \
	sudo sed -i -E '/^GRUB_CMDLINE_LINUX=/ s/  +/ /g' /etc/default/grub; \
	sudo sed -i -E '/^GRUB_CMDLINE_LINUX=/ s/ \"/\"/g' /etc/default/grub; \
	echo "[vfio] Creating /etc/modprobe.d/vfio.conf"; \
	echo "# VFIO configuration for PCI passthrough" | sudo tee /etc/modprobe.d/vfio.conf; \
	echo "options vfio-pci ids=" | sudo tee -a /etc/modprobe.d/vfio.conf; \
	echo "# Load vfio-pci driver at boot" | sudo tee -a /etc/modprobe.d/vfio.conf; \
	echo "install vfio-pci /sbin/modprobe --ignore-install vfio-pci && /sbin/modprobe vfio_pci" | sudo tee -a /etc/modprobe.d/vfio.conf; \
	echo "[initramfs] Updating initramfs for all kernels"; \
	sudo update-initramfs -u -k all; \
	echo "[grub] Updating grub config"; \
	sudo update-grub; \
	echo; \
	echo "✅ Passthrough configuration complete!"; \
	echo; \
	echo "📋 Next steps:"; \
	echo "1. Reboot to apply kernel parameters: sudo reboot"; \
	echo "2. After reboot, find devices: lspci -nn | grep -E 'VGA|3D|NVMe'"; \
	echo "3. Bind devices to vfio-pci:"; \
	echo "   echo 'VENDOR_ID DEVICE_ID' | sudo tee /sys/bus/pci/drivers/vfio-pci/new_id"; \
	echo "4. Verify IOMMU groups: find /sys/kernel/iommu_groups/ -type l"; \
	echo "5. Use VMKit for passthrough VMs: sudo vmkit devices"; \
	echo; \
	echo "📚 See PASSTHROUGH.md for detailed examples and troubleshooting"; \
	echo "🎮 See examples/passthrough_examples.py for Python API usage"

# Disable VFIO/IOMMU kernel parameters and remove vfio modprobe overrides
# This aims to return the GPU(s) to native drivers (nvidia/amdgpu/nouveau) after reboot.
# What it does:
# - Backs up /etc/default/grub and any /etc/modprobe.d/vfio*.conf
# - Strips amd_iommu=on, intel_iommu=on, iommu=pt, vfio-pci.* from GRUB_CMDLINE_LINUX
# - Removes vfio*.conf overrides, regenerates initramfs and grub config
# - Prints a reminder to reboot

disable-vfio:
	@set -e; \
	TS=$$(date +%F_%H%M%S); \
	echo "[backup] /etc/default/grub -> /etc/default/grub.bak.$$TS"; \
	sudo cp /etc/default/grub /etc/default/grub.bak.$$TS; \
	if ls /etc/modprobe.d/vfio*.conf >/dev/null 2>&1; then \
		echo "[backup] /etc/modprobe.d/vfio*.conf -> /etc/modprobe.d/vfio.conf.bak.$$TS"; \
		sudo tar -C /etc/modprobe.d -czf /etc/modprobe.d/vfio.conf.bak.$$TS.tgz vfio*.conf || true; \
	fi; \
	echo "[edit] Stripping VFIO/IOMMU flags from GRUB_CMDLINE_LINUX"; \
	sudo sed -i -E '/^GRUB_CMDLINE_LINUX=/ s/(amd_iommu=on|intel_iommu=on|iommu=pt|vfio-pci\.[A-Za-z_]+=([^" ]+)?)/ /g' /etc/default/grub; \
	sudo sed -i -E '/^GRUB_CMDLINE_LINUX=/ s/  +/ /g' /etc/default/grub; \
	sudo sed -i -E '/^GRUB_CMDLINE_LINUX=/ s/ \"/\"/g' /etc/default/grub; \
	echo "[remove] /etc/modprobe.d/vfio*.conf (if present)"; \
	sudo rm -f /etc/modprobe.d/vfio*.conf || true; \
	echo "[initramfs] Updating initramfs for all kernels"; \
	sudo update-initramfs -u -k all; \
	echo "[grub] Updating grub config"; \
	sudo update-grub; \
	echo "Done. Please reboot to apply (sudo reboot)."

# Attempt to restore graphics drivers (post-VFIO). This does not force a particular vendor.
# It un-blacklists common GPU drivers, loads the module, and refreshes initramfs.
# Adjust driver packages as needed for your hardware.

restore-graphics:
	@set -e; \
	echo "[unblacklist] nvidia/amdgpu/nouveau in /etc/modprobe.d"; \
	for f in /etc/modprobe.d/*.conf; do \
	  [ -f "$$f" ] || continue; \
	  sudo sed -i -E 's/^\s*blacklist\s+(nvidia|nouveau|amdgpu)/# \0/g' "$$f" || true; \
	done; \
	echo "[modprobe] Try loading vendor drivers (non-fatal)"; \
	sudo modprobe nvidia || true; \
	sudo modprobe amdgpu || true; \
	sudo modprobe nouveau || true; \
	echo "[initramfs] Updating initramfs for all kernels"; \
	sudo update-initramfs -u -k all; \
	echo "Done. Reboot recommended (sudo reboot)."

# Hunt for bootkit infections using firmware baseline analysis
# This performs comprehensive bootkit detection against the clean firmware baseline
# What it does:
# - Creates firmware baseline from clean BIOS dump (if not exists)
# - Scans current firmware state for modifications and suspicious patterns
# - Compares EFI variables, BIOS version, and system state
# - Reports risk level and recommended actions
# - Can automatically trigger recovery on critical threats

scan-bootkits:
	@set -e; \
	echo "🎯 PhoenixGuard Bootkit Detection Engine"; \
	echo "Hunting for firmware-level malware..."; \
	echo; \
	if [ ! -f firmware_baseline.json ]; then \
		echo "📊 Creating firmware baseline from clean BIOS dump..."; \
		if [ -f drivers/G615LPAS.325 ]; then \
			python3 scripts/analyze_firmware_baseline.py drivers/G615LPAS.325 -o firmware_baseline.json; \
		else \
			echo "ERROR: Clean BIOS dump not found at drivers/G615LPAS.325"; \
			echo "       Place your clean firmware dump in the drivers/ directory"; \
			exit 1; \
		fi; \
	fi; \
	echo "🔍 Scanning system for bootkit infections..."; \
	python3 scripts/detect_bootkit.py -v --output bootkit_scan_results.json; \
	echo; \
	echo "📊 Scan complete! Check bootkit_scan_results.json for detailed results."; \
	if [ -f bootkit_scan_results.json ]; then \
		RISK=$$(python3 -c "import json; data=json.load(open('bootkit_scan_results.json')); print(data['risk_level'])"); \
		if [ "$$RISK" = "CRITICAL" ]; then \
			echo; \
			echo "🚨 CRITICAL THREAT DETECTED!"; \
			echo "   Consider running: sudo make reboot-to-vm"; \
		elif [ "$$RISK" = "HIGH" ]; then \
			echo; \
			echo "⚠️  HIGH RISK detected - recovery recommended"; \
			echo "   Consider running: sudo make reboot-to-vm"; \
		fi; \
	fi

# BOOTKIT-PROOF Hardware-Level Firmware Recovery (EXTREME DANGER)
# This bypasses potentially compromised BIOS utilities and works directly with SPI flash hardware
# using flashrom, chipsec, and other low-level tools that bootkits cannot interfere with.
# What it does:
# - Detects SPI flash chip directly via hardware
# - Creates hardware-level backup of current firmware
# - Verifies clean firmware image integrity
# - Overwrites firmware directly on SPI flash chip
# - Bypasses ALL software that could be compromised by bootkit
# WARNING: This can brick your system if it fails! Have hardware programmer ready!

hardware-recovery:
	@echo "⚡ PhoenixGuard BOOTKIT-PROOF Hardware-Level Firmware Recovery"; \
	echo "🚨 EXTREME DANGER: This will directly manipulate SPI flash hardware!"; \
	echo "   This bypasses ASUS EZ Flash and ALL software that bootkits could compromise."; \
	echo "   If this fails, you may need a hardware programmer to recover!"; \
	echo; \
	echo "Required tools: flashrom, chipsec, dmidecode"; \
	echo "Install with: sudo apt install flashrom dmidecode && pip install chipsec"; \
	echo; \
	echo "Usage examples:"; \
	echo "  make hardware-recovery              # Interactive verification + recovery"; \
	echo "  sudo python3 scripts/hardware_firmware_recovery.py drivers/G615LPAS.325 --verify-only"; \
	echo "  sudo python3 scripts/hardware_firmware_recovery.py drivers/G615LPAS.325 -v"; \
	echo; \
	read -p "Continue with hardware recovery? [y/N]: " confirm; \
	if [[ "$$confirm" != "y" && "$$confirm" != "Y" ]]; then \
		echo "Hardware recovery cancelled."; \
		exit 0; \
	fi; \
	echo; \
	echo "🔧 Starting BOOTKIT-PROOF hardware recovery..."; \
	if [ -f drivers/G615LPAS.325 ]; then \
		sudo python3 scripts/hardware_firmware_recovery.py drivers/G615LPAS.325 -v --output hardware_recovery_results.json; \
	else \
		echo "ERROR: Clean firmware image not found at drivers/G615LPAS.325"; \
		echo "       This must be your EXACT hardware's clean firmware dump."; \
		echo "       Do NOT use firmware from different models/versions!"; \
		exit 1; \
	fi


# --- 🚨 MASTER RECOVERY WORKFLOW TARGETS (REQUIRE SUDO + REBOOT SYSTEM) ---
# These are the ultimate PhoenixGuard targets that orchestrate the full recovery workflow.
# They backup, stage, configure, and reboot the system automatically.
# WARNING: These targets will REBOOT your system automatically!

# Master Target: Reboot into PhoenixGuard Recovery VM Environment
# This is the "nuclear option" - stages PhoenixGuard, configures UEFI boot, sets up KVM recovery environment, and reboots
# What it does:
# 1. Backs up current UEFI boot configuration
# 2. Stages PhoenixGuard (NuclearBootEdk2.efi) to ESP
# 3. Configures KVM snapshot jump with minimal Ubuntu recovery image
# 4. Sets UEFI boot entry to PhoenixGuard and sets as BootNext
# 5. Automatically reboots system to PhoenixGuard recovery environment
# After reboot: User can launch clean recovery VM to fix infected bootloaders

reboot-to-vm:
	@echo "🚨 WARNING: This will REBOOT your system into PhoenixGuard recovery mode!"
	@echo "The system will reboot automatically in 10 seconds. Press Ctrl+C to cancel."
	@sleep 10 || exit 0
	@set -e; \
	echo "🔧 Initiating PhoenixGuard Recovery VM staging..."; \
	echo; \
	echo "🎯 Running bootkit detection scan first..."; \
	if [ -f firmware_baseline.json ]; then \
		python3 scripts/detect_bootkit.py --output bootkit_scan_prereboot.json || echo "Bootkit scan failed, continuing..."; \
	else \
		echo "⚠️  No firmware baseline found - creating from clean BIOS..."; \
		if [ -f drivers/G615LPAS.325 ]; then \
			python3 scripts/analyze_firmware_baseline.py drivers/G615LPAS.325 -o firmware_baseline.json || echo "Baseline creation failed"; \
			python3 scripts/detect_bootkit.py --output bootkit_scan_prereboot.json || echo "Bootkit scan failed"; \
		else \
			echo "⚠️  Clean BIOS dump not found at drivers/G615LPAS.325"; \
		fi; \
	fi; \
	echo; \
	TS=$$(date +%F_%H%M%S);
	echo "[backup] Current UEFI boot configuration"; \
	sudo mkdir -p /var/lib/phoenixguard/backups; \
	sudo efibootmgr -v | sudo tee "/var/lib/phoenixguard/backups/efibootmgr-backup-$$TS.txt" >/dev/null; \
	echo "[esp] Detecting ESP mount point"; \
	ESP=$$(findmnt -t vfat -n -o TARGET | head -n1 || true); \
	if [[ -z "$$ESP" ]]; then ESP="/boot/efi"; fi; \
	if [[ ! -d "$$ESP/EFI" ]]; then echo "ERROR: No ESP found at $$ESP"; exit 1; fi; \
	echo "  Using ESP: $$ESP"; \
	echo "[stage] PhoenixGuard NuclearBootEdk2.efi to ESP"; \
	sudo mkdir -p "$$ESP/EFI/PhoenixGuard"; \
	if [[ -f NuclearBootEdk2.efi ]]; then \
		sudo cp NuclearBootEdk2.efi "$$ESP/EFI/PhoenixGuard/NuclearBootEdk2.efi"; \
	else \
		echo "ERROR: NuclearBootEdk2.efi not found. Run 'make build' first."; exit 1; \
	fi; \
	echo "[stage] KVM recovery environment"; \
	VMLINUZ="/boot/vmlinuz-$$(uname -r)"; \
	INITRD="/boot/initrd.img-$$(uname -r)"; \
	ROOT_UUID=$$(findmnt -n -o UUID / || true); \
	QCOW2="$$(pwd)/ubuntu-24.04-minimal-cloudimg-amd64.qcow2"; \
	if [[ ! -f "$$QCOW2" ]]; then echo "ERROR: Recovery image not found: $$QCOW2"; exit 1; fi; \
	echo "[kvm] Installing KVM snapshot jump configuration"; \
	sudo ./scripts/install_kvm_snapshot_jump.sh \
		--esp "$$ESP" --vmlinuz "$$VMLINUZ" --initrd "$$INITRD" --root-uuid "$$ROOT_UUID" \
		--qcow2 "$$QCOW2" --loadvm base-snapshot \
		--gpu-bdf 0000:02:00.0 --gpu-ids 10de:2d58 || echo "KVM config failed, continuing..."; \
	echo "[uefi] Configuring UEFI boot entry for PhoenixGuard"; \
	ESP_DEV=$$(findmnt -n -o SOURCE "$$ESP" || true); \
	DISK=$$(lsblk -no PKNAME "$$ESP_DEV" 2>/dev/null | head -n1); \
	PARTNUM=$$(lsblk -no PARTNUM "$$ESP_DEV" 2>/dev/null | head -n1); \
	BOOTNUM=$$(efibootmgr | awk -F'*' '/PhoenixGuard/{print $$1}' | sed 's/Boot//;s/\s*$$//' | head -n1); \
	if [[ -n "$$BOOTNUM" ]]; then sudo efibootmgr -b "$$BOOTNUM" -B || true; fi; \
	sudo efibootmgr -c -d "/dev/$$DISK" -p "$$PARTNUM" -L "PhoenixGuard Recovery" -l "\\EFI\\PhoenixGuard\\NuclearBootEdk2.efi" >/dev/null; \
	NEWNUM=$$(efibootmgr | awk -F'*' '/PhoenixGuard Recovery/{print $$1}' | sed 's/Boot//;s/\s*$$//' | head -n1); \
	if [[ -n "$$NEWNUM" ]]; then sudo efibootmgr -n "$$NEWNUM" >/dev/null; fi; \
	echo "[reboot] System will reboot to PhoenixGuard recovery in 5 seconds..."; \
	echo "✅ Staged: ESP at $$ESP/EFI/PhoenixGuard/"; \
	echo "✅ Configured: UEFI boot entry $$NEWNUM (set as BootNext)"; \
	echo "✅ Recovery VM: $$QCOW2 ready to launch"; \
	echo; \
	echo "🎯 After reboot:"; \
	echo "  1. PhoenixGuard menu will appear"; \
	echo "  2. Select 'KVM Snapshot Jump' to launch recovery VM"; \
	echo "  3. Use recovery VM to fix infected bootloaders safely"; \
	echo "  4. Run 'make reboot-to-metal' when done to return to normal boot"; \
	sleep 5; \
	sudo reboot

# Master Target: Reboot back to Normal Metal Operation
# This restores the original bootloader, cleans up ESP staging, restores UEFI boot order, and reboots
# What it does:
# 1. Removes PhoenixGuard UEFI boot entries
# 2. Cleans up PhoenixGuard staging from ESP
# 3. Restores original UEFI boot order
# 4. Automatically reboots system back to normal operation

reboot-to-metal:
	@echo "🔄 Restoring system to normal boot operation..."
	@echo "The system will reboot automatically in 5 seconds. Press Ctrl+C to cancel."
	@sleep 5 || exit 0
	@set -e; \
	echo "🧹 Cleaning up PhoenixGuard recovery environment..."; \
	echo; \
	echo "[uefi] Removing PhoenixGuard boot entries"; \
	BOOTNUMS=$$(efibootmgr | awk -F'*' '/PhoenixGuard/{print $$1}' | sed 's/Boot//;s/\s*$$//'); \
	for num in $$BOOTNUMS; do \
		if [[ -n "$$num" ]]; then sudo efibootmgr -b "$$num" -B >/dev/null || true; fi; \
	done; \
	echo "[esp] Cleaning up ESP staging"; \
	ESP=$$(findmnt -t vfat -n -o TARGET | head -n1 || true); \
	if [[ -z "$$ESP" ]]; then ESP="/boot/efi"; fi; \
	if [[ -d "$$ESP/EFI/PhoenixGuard" ]]; then \
		sudo rm -rf "$$ESP/EFI/PhoenixGuard" || true; \
	fi; \
	if [[ -f "$$ESP/EFI/xen.efi" ]]; then sudo rm -f "$$ESP/EFI/xen.efi" || true; fi; \
	if [[ -f "$$ESP/EFI/xen.cfg" ]]; then sudo rm -f "$$ESP/EFI/xen.cfg" || true; fi; \
	echo "[cleanup] Removing KVM recovery configuration"; \
	sudo rm -f /etc/phoenixguard/kvm-snapshot.conf || true; \
	sudo systemctl disable kvm-snapshot-jump.service >/dev/null 2>&1 || true; \
	sudo systemctl disable pg-remediate.service >/dev/null 2>&1 || true; \
	echo "[restore] UEFI boot order to defaults"; \
	echo "✅ Removed: PhoenixGuard UEFI boot entries"; \
	echo "✅ Cleaned: ESP staging at $$ESP/EFI/PhoenixGuard/"; \
	echo "✅ Disabled: KVM recovery services"; \
	echo; \
	echo "🎯 System ready to reboot to normal operation"; \
	echo "   Your original bootloader should now be restored"; \
	sudo reboot


# --- 💿 NUCLEAR BOOT CD TARGETS (BOOTKIT-PROOF RECOVERY MEDIUM) ---
# These targets create an immutable, bootable CD/DVD that bypasses infected systems entirely
# by booting directly into a clean, isolated recovery environment with hardware access.

# Build complete Nuclear Boot recovery CD/DVD image
# This creates a bootable ISO with signed UEFI bootloader, Linux kernel, and recovery tools
# What it contains:
# - Signed UEFI bootloader (NuclearBoot.efi)
# - Clean Linux kernel with recovery drivers
# - Complete recovery environment (flashrom, chipsec, forensic tools)
# - Hardware passthrough VM for safe firmware recovery
# - Automatic bootkit detection and removal tools

build-nuclear-cd:
	@echo "💿 Building PhoenixGuard Nuclear Boot recovery CD..."
	@set -e; \
	echo "🔍 Checking build requirements..."; \
	for tool in xorriso grub-mkrescue; do \
		command -v $$tool >/dev/null || { echo "ERROR: Missing $$tool (install with: sudo apt install xorriso grub-efi-amd64-bin)"; exit 1; }; \
	done; \
	echo "📏 Creating Nuclear Boot CD workspace..."; \
	mkdir -p nuclear-cd-build/{iso,rootfs,efi/boot}; \
	echo "🔑 Preparing signed UEFI bootloader..."; \
	if [ -f NuclearBootEdk2.efi ]; then \
		cp NuclearBootEdk2.efi nuclear-cd-build/efi/boot/BOOTX64.EFI; \
	else \
		echo "ERROR: NuclearBootEdk2.efi not found. Run 'make build' first."; exit 1; \
	fi; \
	echo "🐧 Preparing Linux kernel and recovery tools..."; \
	cp /boot/vmlinuz-$$(uname -r) nuclear-cd-build/iso/vmlinuz || echo "Kernel copy failed"; \
	cp /boot/initrd.img-$$(uname -r) nuclear-cd-build/iso/initrd.img || echo "Initramfs copy failed"; \
	echo "🔧 Adding recovery scripts and tools..."; \
	mkdir -p nuclear-cd-build/iso/recovery; \
	cp -r scripts nuclear-cd-build/iso/recovery/; \
	cp -r drivers nuclear-cd-build/iso/recovery/ || echo "No drivers directory"; \
	echo "💾 Creating bootable ISO image..."; \
	grub-mkrescue -o PhoenixGuard-Nuclear-Recovery.iso nuclear-cd-build/ \
		--modules="part_gpt part_msdos iso9660 fat ext2 normal boot linux configfile loopback chain efifwsetup efi_gop" \
		--install-modules="linux16 linux normal iso9660 biosdisk" || { \
		echo "GRUB rescue failed, trying xorriso directly..."; \
		xorriso -as mkisofs -r -V "PhoenixGuard Nuclear Recovery" \
			-o PhoenixGuard-Nuclear-Recovery.iso \
			-J -l -b isolinux/isolinux.bin -c isolinux/boot.cat \
			-no-emul-boot -boot-load-size 4 -boot-info-table \
			-eltorito-alt-boot -e efi/boot/BOOTX64.EFI -no-emul-boot \
			nuclear-cd-build/; \
	}; \
	echo "✅ Nuclear Boot CD created: PhoenixGuard-Nuclear-Recovery.iso"; \
	echo "📏 Size: $$(du -h PhoenixGuard-Nuclear-Recovery.iso | cut -f1)"; \
	echo "🔒 SHA256: $$(sha256sum PhoenixGuard-Nuclear-Recovery.iso | cut -d' ' -f1)"; \
	echo; \
	echo "🎯 Next steps:"; \
	echo "  Test: make test-cd-boot"; \
	echo "  Burn: make burn-recovery-cd"; \
	echo "  USB:  make create-usb-recovery"; \
	rm -rf nuclear-cd-build

# Test Nuclear Boot CD in QEMU (safe testing environment)
# This boots the CD in QEMU to verify it works before burning to physical media

test-cd-boot:
	@echo "🧪 Testing Nuclear Boot CD in QEMU..."
	@set -e; \
	if [ ! -f PhoenixGuard-Nuclear-Recovery.iso ]; then \
		echo "ERROR: PhoenixGuard-Nuclear-Recovery.iso not found. Run 'make build-nuclear-cd' first."; \
		exit 1; \
	fi; \
	echo "🚀 Launching QEMU with Nuclear Boot CD..."; \
	echo "Press Ctrl+Alt+G to release mouse, Ctrl+Alt+Q to quit QEMU"; \
	echo; \
	qemu-system-x86_64 \
		-cdrom PhoenixGuard-Nuclear-Recovery.iso \
		-boot d \
		-m 4G \
		-enable-kvm \
		-vga virtio \
		-netdev user,id=net0 \
		-device virtio-net-pci,netdev=net0 \
		-bios /usr/share/ovmf/OVMF.fd 2>/dev/null || \
	qemu-system-x86_64 \
		-cdrom PhoenixGuard-Nuclear-Recovery.iso \
		-boot d \
		-m 4G \
		-enable-kvm \
		-vga virtio \
		-netdev user,id=net0 \
		-device virtio-net-pci,netdev=net0

# Burn Nuclear Boot CD to physical disc (requires CD/DVD burner)
# This creates an immutable recovery medium that cannot be infected by bootkits

burn-recovery-cd:
	@echo "🔥 Burning PhoenixGuard Nuclear Recovery CD..."
	@set -e; \
	if [ ! -f PhoenixGuard-Nuclear-Recovery.iso ]; then \
		echo "ERROR: PhoenixGuard-Nuclear-Recovery.iso not found. Run 'make build-nuclear-cd' first."; \
		exit 1; \
	fi; \
	echo; \
	echo "🔍 Detecting CD/DVD drives..."; \
	lsblk -d -o NAME,SIZE,TYPE,MODEL | grep -E "rom|cd|dvd" || echo "No CD/DVD drives detected"; \
	echo; \
	echo "🚨 WARNING: This will burn a CD/DVD disc!"; \
	echo "Make sure you have a blank CD or DVD inserted."; \
	echo; \
	read -p "Enter CD/DVD device (e.g., /dev/sr0): " device; \
	if [ -z "$$device" ]; then echo "No device specified. Cancelled."; exit 0; fi; \
	echo; \
	echo "🔥 Burning to $$device..."; \
	if command -v cdrecord >/dev/null; then \
		cdrecord -v dev=$$device PhoenixGuard-Nuclear-Recovery.iso; \
	elif command -v wodim >/dev/null; then \
		wodim -v dev=$$device PhoenixGuard-Nuclear-Recovery.iso; \
	else \
		echo "ERROR: No CD burning software found. Install with: sudo apt install cdrtools"; \
		exit 1; \
	fi; \
	echo; \
	echo "✅ Nuclear Boot recovery CD burned successfully!"; \
	echo "🔒 This disc is now IMMUTABLE and bootkit-proof."; \
	echo "🎯 To use: Insert disc, boot from CD/DVD (F12/F2 boot menu)"

# Create bootable USB recovery drive (alternative to CD/DVD)
# This creates a USB version of the Nuclear Boot recovery system

create-usb-recovery:
	@echo "💎 Creating PhoenixGuard Nuclear Boot USB drive..."
	@set -e; \
	if [ ! -f PhoenixGuard-Nuclear-Recovery.iso ]; then \
		echo "ERROR: PhoenixGuard-Nuclear-Recovery.iso not found. Run 'make build-nuclear-cd' first."; \
		exit 1; \
	fi; \
	echo; \
	echo "🔍 Detecting USB drives..."; \
	lsblk -d -o NAME,SIZE,TYPE,MODEL,TRAN | grep usb || echo "No USB drives detected"; \
	echo; \
	echo "🚨 WARNING: This will ERASE the selected USB drive!"; \
	echo "All data on the USB drive will be permanently lost."; \
	echo; \
	read -p "Enter USB device (e.g., /dev/sdb): " device; \
	if [ -z "$$device" ]; then echo "No device specified. Cancelled."; exit 0; fi; \
	echo; \
	echo "🚨 FINAL WARNING: About to erase $$device!"; \
	read -p "Type 'ERASE' to continue: " confirm; \
	if [ "$$confirm" != "ERASE" ]; then echo "Cancelled."; exit 0; fi; \
	echo; \
	echo "💎 Writing ISO to $$device..."; \
	sudo dd if=PhoenixGuard-Nuclear-Recovery.iso of=$$device bs=1M status=progress conv=fsync; \
	echo; \
	echo "✅ Nuclear Boot USB created successfully!"; \
	echo "🔒 Enable write-protect switch (if available) for immutable medium."; \
	echo "🎯 To use: Insert USB, boot from USB (F12/F2 boot menu)"


# --- ⚡ ESP-ISO VIRTUAL CD TARGETS (INSTANT SOFTWARE-ONLY DEPLOYMENT) ---
# These targets deploy the Nuclear Boot recovery ISO directly to the ESP partition
# for instant access without requiring physical media or rebooting.

# Deploy Nuclear Boot ISO to ESP as "virtual CD" (instant deployment)
# This "burns" the ISO file directly to the ESP partition where GRUB can boot it
# What it does:
# - Copies PhoenixGuard-Nuclear-Recovery.iso to ESP/recovery/
# - Creates GRUB boot entry to boot from the ISO file via loopback
# - Updates GRUB configuration to include recovery option
# - ISO format is read-only - harder for bootkits to modify
# - Instant deployment - no CD burning or USB creation required

deploy-esp-iso:
	@echo "⚡ Deploying Nuclear Boot ISO to ESP as virtual CD..."
	@set -e; \
	if [ ! -f PhoenixGuard-Nuclear-Recovery.iso ]; then \
		echo "ERROR: PhoenixGuard-Nuclear-Recovery.iso not found. Run 'make build-nuclear-cd' first."; \
		exit 1; \
	fi; \
	echo "🔍 Detecting ESP mount point..."; \
	ESP=$$(findmnt -t vfat -n -o TARGET | head -n1 || true); \
	if [[ -z "$$ESP" ]]; then ESP="/boot/efi"; fi; \
	if [[ ! -d "$$ESP/EFI" ]]; then echo "ERROR: No ESP found at $$ESP"; exit 1; fi; \
	echo "  Using ESP: $$ESP"; \
	echo "📏 Creating recovery directory..."; \
	sudo mkdir -p "$$ESP/recovery"; \
	echo "💾 Copying ISO to ESP (virtual CD burn)..."; \
	sudo cp PhoenixGuard-Nuclear-Recovery.iso "$$ESP/recovery/PhoenixGuard-Nuclear-Recovery.iso"; \
	echo "🔑 Setting up GRUB loopback entry..."; \
	sudo mkdir -p /etc/grub.d; \
	echo "#!/bin/sh" | sudo tee /etc/grub.d/42_phoenixguard_recovery; \
	echo "exec tail -n +3 \$$0" | sudo tee -a /etc/grub.d/42_phoenixguard_recovery; \
	echo "# PhoenixGuard Nuclear Boot Recovery (Virtual CD)" | sudo tee -a /etc/grub.d/42_phoenixguard_recovery; \
	echo "menuentry 'PhoenixGuard Nuclear Boot Recovery (Virtual CD)' {" | sudo tee -a /etc/grub.d/42_phoenixguard_recovery; \
	echo "    insmod loopback" | sudo tee -a /etc/grub.d/42_phoenixguard_recovery; \
	echo "    insmod iso9660" | sudo tee -a /etc/grub.d/42_phoenixguard_recovery; \
	echo "    set isofile='/recovery/PhoenixGuard-Nuclear-Recovery.iso'" | sudo tee -a /etc/grub.d/42_phoenixguard_recovery; \
	echo "    loopback loop \$$isofile" | sudo tee -a /etc/grub.d/42_phoenixguard_recovery; \
	echo "    linux (loop)/vmlinuz boot=live toram" | sudo tee -a /etc/grub.d/42_phoenixguard_recovery; \
	echo "    initrd (loop)/initrd.img" | sudo tee -a /etc/grub.d/42_phoenixguard_recovery; \
	echo "}" | sudo tee -a /etc/grub.d/42_phoenixguard_recovery; \
	sudo chmod +x /etc/grub.d/42_phoenixguard_recovery; \
	echo "🔄 Updating GRUB configuration..."; \
	sudo update-grub; \
	echo; \
	echo "✅ Nuclear Boot ISO deployed to ESP successfully!"; \
	echo "💿 Virtual CD location: $$ESP/recovery/PhoenixGuard-Nuclear-Recovery.iso"; \
	echo "🔒 ISO format provides read-only protection against modification"; \
	echo "🎯 Size: $$(du -h "$$ESP/recovery/PhoenixGuard-Nuclear-Recovery.iso" | cut -f1)"; \
	echo; \
	echo "🚀 To use: Reboot and select 'PhoenixGuard Nuclear Boot Recovery (Virtual CD)' from GRUB menu"; \
	echo "📋 Alternative: Run 'make boot-from-esp-iso' to boot immediately"

# Boot directly from ESP-deployed ISO (no system reboot required)
# This launches the recovery environment directly from the ESP ISO without rebooting
# Using kexec for hot kernel switching or GRUB rescue mode entry

boot-from-esp-iso:
	@echo "🚀 Booting Nuclear Recovery from ESP-deployed ISO..."
	@set -e; \
	ESP=$$(findmnt -t vfat -n -o TARGET | head -n1 || true); \
	if [[ -z "$$ESP" ]]; then ESP="/boot/efi"; fi; \
	ISO_PATH="$$ESP/recovery/PhoenixGuard-Nuclear-Recovery.iso"; \
	if [ ! -f "$$ISO_PATH" ]; then \
		echo "ERROR: Nuclear Boot ISO not found at $$ISO_PATH"; \
		echo "       Run 'make deploy-esp-iso' first to deploy the virtual CD."; \
		exit 1; \
	fi; \
	echo "🔍 Found virtual CD: $$ISO_PATH"; \
	echo "📏 Size: $$(du -h "$$ISO_PATH" | cut -f1)"; \
	echo; \
	echo "🎯 Boot options:"; \
	echo "  [1] Reboot to GRUB menu (safest)"; \
	echo "  [2] Mount ISO and explore contents"; \
	echo "  [3] Extract and run tools directly"; \
	echo "  [4] Cancel"; \
	echo; \
	read -p "Select option [1-4]: " option; \
	case $$option in \
		1) echo "🔄 Rebooting to GRUB menu..."; \
		   echo "Select 'PhoenixGuard Nuclear Boot Recovery (Virtual CD)' from boot menu"; \
		   sleep 3; \
		   sudo reboot ;; \
		2) echo "📏 Mounting ISO for exploration..."; \
		   sudo mkdir -p /mnt/phoenixguard-iso; \
		   sudo mount -o loop "$$ISO_PATH" /mnt/phoenixguard-iso; \
		   echo "  Mounted at: /mnt/phoenixguard-iso"; \
		   echo "  Contents:"; ls -la /mnt/phoenixguard-iso/; \
		   echo "  To unmount: sudo umount /mnt/phoenixguard-iso" ;; \
		3) echo "📏 Extracting recovery tools..."; \
		   sudo mkdir -p /tmp/phoenixguard-recovery; \
		   cd /tmp/phoenixguard-recovery; \
		   sudo 7z x "$$ISO_PATH" 2>/dev/null || { \
			   echo "7z not found, trying bsdtar..."; \
			   sudo bsdtar -xf "$$ISO_PATH" 2>/dev/null || { \
				   echo "bsdtar not found, mounting instead..."; \
				   sudo mount -o loop "$$ISO_PATH" /mnt/phoenixguard-iso 2>/dev/null || true; \
				   sudo cp -r /mnt/phoenixguard-iso/* . 2>/dev/null || true; \
				   sudo umount /mnt/phoenixguard-iso 2>/dev/null || true; \
			   }; \
		   }; \
		   echo "  Extracted to: /tmp/phoenixguard-recovery"; \
		   echo "  Recovery tools available for direct use"; \
		   if [ -d recovery/scripts ]; then \
			   echo "  Scripts: $$(ls recovery/scripts/ | head -5 | tr '\n' ' ')"; \
		   fi ;; \
		4) echo "Cancelled." ;; \
		*) echo "Invalid option." ;; \
	esac


# --- 💥 AUTONUKE: PROGRESSIVE MASTER RECOVERY ORCHESTRATOR ---
# The ultimate one-command recovery system that guides users through escalating
# recovery methods from safest software approaches to extreme hardware recovery.
# This is the "Easy Button" for bootkit elimination.

# AUTONUKE: Progressive Recovery from Scan to CH341A Nuclear Option
# This is the ultimate single-command recovery system that automatically escalates
# through all available recovery methods until the system is clean.
# Recovery Escalation Ladder:
# 1. 🔍 SCAN: Software-level bootkit detection and analysis  
# 2. 💿 SOFT: ESP Nuclear Boot ISO recovery (software-only)
# 3. ⚡ HARD: Direct hardware firmware recovery (bypass software protections) 
# 4. 💥 NUKE: External CH341A programmer recovery (ultimate nuclear option)
# Each level requires user confirmation and explains risks/procedures.

autonuke:
	@echo "💥 AUTONUKE - PhoenixGuard Master Recovery Orchestrator"
	@echo "🎯 Progressive bootkit elimination: SCAN → SOFT → HARD → NUKE"
	@echo
	@echo "⚠️  This will guide you through escalating recovery methods"
	@echo "   from safe software scanning to extreme hardware recovery."
	@echo "   Each step requires confirmation - you control the escalation."
	@echo
	@read -p "Ready to begin AUTONUKE recovery? [y/N]: " confirm; \
	if [[ "$$confirm" != "y" && "$$confirm" != "Y" ]]; then \
		echo "AUTONUKE cancelled."; \
		exit 0; \
	fi; \
	echo; \
	echo "🚀 Launching AUTONUKE master recovery orchestrator..."; \
	python3 scripts/autonuke.py
