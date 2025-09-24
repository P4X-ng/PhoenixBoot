# PhoenixGuard Host OS Workflows

# Import shared variables
import './Justfile.vars'


# Show os module help
help:
	@echo "🖥️  PhoenixGuard OS Module"
	@echo "=========================="
	@echo ""
	@echo "Available commands:"
	@echo "  just os boot-clean                      # Clean stale UEFI boot entries"
	@echo "  just os mok-enroll                      # Enroll host MOK for module signing"
	@echo "  just os mok-find-enrolled               # Map enrolled MOKs to local certs"
	@echo "  just os harden                          # Host hardening (SB + sign modules)"
	@echo "  just os kmod-setup-fastpath [ko]        # Sign+install+autoload utils/pfs_fastpath.ko"
	@echo "  just os kmod-autoload name=<mod>        # Configure module autoload"
	@echo "  just os boot-once                       # One-shot boot to UUEFI"
	@echo "  just os kmod-load <name>                # Load kernel module"
	@echo "  just os kmod-unload <name>              # Unload kernel module"
	@echo "  just os kmod-status <name>              # Show kernel module status"
	@echo "  just os kmod-sign path=<file|dir> [force=1]  # Sign one module or recursively sign a directory"
	@echo ""

# Clean stale UEFI boot entries safely
os-boot-clean:
	@bash scripts/os-boot-clean.sh
# Alias without prefix for module dispatcher
boot-clean:
	@bash scripts/os-boot-clean.sh

# Enroll host MOK for module signing (wrapper)
os-mok-enroll:
	@just secure enroll-mok
# Alias
mok-enroll:
	@just secure enroll-mok

# List available MOK certs/keys and enrollment status
os-mok-list-keys:
	@bash scripts/mok-list-keys.sh
# Alias
mok-list-keys:
	@bash scripts/mok-list-keys.sh

# Select a MOK cert+key to use for signing (prints exports)
os-mok-select:
	@bash scripts/mok-select-key.sh
# Alias
mok-select:
	@bash scripts/mok-select-key.sh

# Host harden: verify SB and sign modules
os-harden:
	@echo "🛡️  Host hardening: verify SB → sign kernel modules"
	@bash scripts/verify-sb.sh || true
	@bash scripts/sign-kmods.sh
	@echo "[OK] Host hardening steps completed"
# Alias
harden:
	@echo "🛡️  Host hardening: verify SB → sign kernel modules"
	@bash scripts/verify-sb.sh || true
	@bash scripts/sign-kmods.sh
	@echo "[OK] Host hardening steps completed"

# One-shot boot to UUEFI (install if needed)
os-boot-once:
	@just validate uuefi-install
	@just os host-uuefi-once
# Alias
boot-once:
	@just validate uuefi-install
	@just os host-uuefi-once

# Install UUEFI then set one-shot BootNext and exit
host-uuefi-once:
	@just validate uuefi-install
	@bash scripts/host-uuefi-once.sh

os-kmod-load name="":
	@bash scripts/os-kmod.sh load '{{name}}'

# Alias
kmod-load name="":
	@bash scripts/os-kmod.sh load '{{name}}'

os-kmod-unload name="":
	@bash scripts/os-kmod.sh unload '{{name}}'
# Alias
kmod-unload name="":
	@bash scripts/os-kmod.sh unload '{{name}}'

os-kmod-status name="":
	@bash scripts/os-kmod.sh status '{{name}}'
# Alias
kmod-status name="":
	@bash scripts/os-kmod.sh status '{{name}}'

# Configure autoload at boot
os-kmod-autoload name="":
	@if [ -z "{{name}}" ]; then echo "Usage: just os kmod-autoload name=<module>"; exit 1; fi
	@bash scripts/kmod-autoload.sh '{{name}}'
# Alias
kmod-autoload name="":
	@if [ -z "{{name}}" ]; then echo "Usage: just os kmod-autoload name=<module>"; exit 1; fi
	@bash scripts/kmod-autoload.sh '{{name}}'

# Sign one module file or recursively sign all .ko under a directory
os-kmod-sign path="" force="0":
	@if [ -z "{{path}}" ]; then echo "Usage: just os kmod-sign path=<file|dir> [force=1]"; exit 1; fi
	@echo "🔏 Signing kernel module(s) at: {{path}}"
	@{{PYTHON}} utils/pgmodsign.py {{path}} $([ "{{force}}" = "1" ] && printf -- '--force' || true)
# Alias
kmod-sign path="" force="0":
	@if [ -z "{{path}}" ]; then echo "Usage: just os kmod-sign path=<file|dir> [force=1]"; exit 1; fi
	@{{PYTHON}} utils/pgmodsign.py {{path}} $([ "{{force}}" = "1" ] && printf -- '--force' || true)

# Find enrolled MOKs and match to local certs
os-mok-find-enrolled:
	@bash scripts/mok-find-enrolled.sh
# Aliases
mok-find-enrolled:
	@bash scripts/mok-find-enrolled.sh
# Friendlier alias (so 'just os find-enrolled' works)
find-enrolled:
	@bash scripts/mok-find-enrolled.sh
