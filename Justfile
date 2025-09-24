# PhoenixGuard Production Orchestrator
# ===================================
# Primary build orchestrator for production firmware defense system.
# This file imports modular Justfiles. See Justfile.* for details.

# Import variables only; module recipes are invoked via their own Justfiles to avoid name conflicts
import './Justfile.vars'

# Default task: show available commands
default: help

# Show available targets
help:
	@echo "🔥 PHOENIXGUARD - Production Firmware Defense System"
	@echo "===================================================="
	@echo ""
	@echo "📋 High-level Workflows:"
	@echo "  just run                        # Main production pipeline"
	@echo "  just secure-pipeline            # Secure Boot production pipeline"
	@echo ""
	@echo "🎯 Module Commands (run 'just <module>' for help):"
	@echo "  just secure [op]                # Secure Boot and MOK management"
	@echo "  just build [op]                 # Build and packaging tasks"
	@echo "  just test [op]                  # Testing workflows"
	@echo "  just nuke [op]                  # Nuclear Boot workflows"
	@echo "  just usb [op]                   # USB media creation"
	@echo "  just iso [op]                   # ISO-related workflows"
	@echo "  just os [op]                    # Host OS interactions"
	@echo "  just validate [op]              # Validation and verification tasks"
	@echo "  just code-org [op]              # Code organization and refactoring"
	@echo "  just maint [op]                 # Maintenance, linting, formatting"
	@echo ""
	@echo "💡 Examples:"
	@echo "  just secure                     # Show secure module help"
	@echo "  just secure keygen              # Generate Secure Boot keys"
	@echo "  just build esp                  # Build ESP image"
	@echo "  just test qemu                  # Run QEMU boot tests"
	@echo ""
	@echo "🔎 To see all available recipes from all modules, run:"
	@echo "  just --list"
	@echo ""

# --- High-level pipelines ---
run:
	@echo "🚀 PhoenixGuard pipeline: setup → build → package-esp → verify → virtual-tests"
	just build setup
	just build build
	just build package-esp
	just validate verify-esp-robust
	just test virtual-tests

secure-pipeline:
	@echo "🔐 PhoenixGuard secure pipeline: setup → build → enroll → verify → secure tests"
	just build setup
	just build build
	just build package-esp-enroll
	just secure enroll-secureboot
	just build package-esp
	just validate verify-esp-robust
	just test tests-secure

# --- Alias targets for backward compatibility ---
verify:
	@echo "🔎 Running verification (validate-all + verify-esp-robust)"
	just validate validate-all
	just validate verify-esp-robust

# --- Module namespace dispatchers with help defaults ---

# Secure Boot module commands
secure op="help" +args="":
	@if [ "{{op}}" = "help" ]; then \
		just --justfile {{justfile_directory()}}/Justfile.secure help; \
	else \
		just --justfile {{justfile_directory()}}/Justfile.secure {{op}} {{args}}; \
	fi

# Nuclear wipe module commands
nuke op="help" +args="":
	@if [ "{{op}}" = "help" ]; then \
		just --justfile {{justfile_directory()}}/Justfile.nuke help; \
	else \
		just --justfile {{justfile_directory()}}/Justfile.nuke {{op}} {{args}}; \
	fi

# Build module commands
build op="help" +args="":
	@if [ "{{op}}" = "help" ]; then \
		just --justfile {{justfile_directory()}}/Justfile.build help; \
	else \
		just --justfile {{justfile_directory()}}/Justfile.build {{op}} {{args}}; \
	fi

# Test module commands
test op="help" +args="":
	@if [ "{{op}}" = "help" ]; then \
		just --justfile {{justfile_directory()}}/Justfile.test help; \
	else \
		just --justfile {{justfile_directory()}}/Justfile.test {{op}} {{args}}; \
	fi

# USB workflows
usb op="help" +args="":
	@if [ "{{op}}" = "help" ]; then \
		just --justfile {{justfile_directory()}}/Justfile.usb help; \
	else \
		just --justfile {{justfile_directory()}}/Justfile.usb {{op}} {{args}}; \
	fi

# ISO workflows
iso op="help" +args="":
	@if [ "{{op}}" = "help" ]; then \
		just --justfile {{justfile_directory()}}/Justfile.iso help; \
	else \
		just --justfile {{justfile_directory()}}/Justfile.iso {{op}} {{args}}; \
	fi

# OS workflows
os op="help" +args="":
	@if [ "{{op}}" = "help" ]; then \
		just --justfile {{justfile_directory()}}/Justfile.os help; \
	else \
		just --justfile {{justfile_directory()}}/Justfile.os {{op}} {{args}}; \
	fi

# Validation workflows
validate op="help" +args="":
	@if [ "{{op}}" = "help" ]; then \
		just --justfile {{justfile_directory()}}/Justfile.validate help; \
	else \
		just --justfile {{justfile_directory()}}/Justfile.validate {{op}} {{args}}; \
	fi

# Code organization workflows
code-org op="help" +args="":
	@if [ "{{op}}" = "help" ]; then \
		just --justfile {{justfile_directory()}}/Justfile.code-org help; \
	else \
		just --justfile {{justfile_directory()}}/Justfile.code-org {{op}} {{args}}; \
	fi

# Maintenance workflows
maint op="help" +args="":
	@if [ "{{op}}" = "help" ]; then \
		just --justfile {{justfile_directory()}}/Justfile.maintenance help; \
	else \
		just --justfile {{justfile_directory()}}/Justfile.maintenance {{op}} {{args}}; \
	fi
