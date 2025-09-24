# WARP

# PhoenixGuard Strategic Context

## Mission
PhoenixGuard delivers **production-ready firmware defense** against bootkit attacks through network-based secure boot protocols that bypass traditional storage dependencies.

## Core Principle
NEVER compromise boot security for development convenience. Every production artifact must be built from `staging/` code only, with full isolation from demo/WIP/dev content.

## Project Reorganization

### Transformation: Mixed → Production-First
PhoenixGuard underwent comprehensive reorganization from mixed-purpose repository to production-focused firmware defense system:

#### Before: Contaminated Development Environment
- Demo code intermixed with production sources
- Unclear boundaries between stable and experimental code
- Build system included demo dependencies
- No validation of production-only builds

#### After: Production-First Architecture  
- **staging/**: Only fully functional, tested production code
- **dev/**: Hardware-specific boot development (completely isolated)
- **wip/**: Experimental features (excluded from production builds)
- **demo/**: Demonstration content (quarantined and excluded)

#### Benefits Achieved
- **Zero demo contamination** in production artifacts
- **Deterministic builds** from staging/ sources only
- **Real boot validation** via automated QEMU testing
- **CI/CD-ready workflow** with quality gates
- **Clear development boundaries** prevent accidental inclusion

## Production Philosophy
"Embrace the breach" - assume firmware compromise will occur, focus on automatic recovery and business continuity rather than prevention-only strategies.

## Quality Gate Architecture

### Production Workflow Stages
1. **`just setup`** - Bootstrap and validate toolchain
2. **`just build`** - Compile staging/ → out/staging/ (zero external deps)
3. **`just package-esp`** - Create bootable FAT32 ESP image
4. **`just qemu-test`** - Execute full UEFI boot validation
5. **`just test`** - Aggregate production test suite

### QEMU Boot Test Architecture

#### Real UEFI Boot Validation
The `qemu-test` target performs **actual hardware-equivalent boot testing**:

```bash
# Full UEFI boot simulation with production artifacts
qemu-system-x86_64 \
  -machine q35 \
  -cpu host \
  -enable-kvm \
  -m 2G \
  -drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd \
  -drive if=pflash,format=raw,file=out/qemu/OVMF_VARS_test.fd \
  -drive format=raw,file=out/esp/esp.img \
  -serial file:out/qemu/serial.log
```

#### Boot Flow Validation
1. **OVMF Firmware Boot**: UEFI loads from production ESP image
2. **PhoenixGuard Launch**: Nuclear Boot EFI application executes
3. **Network Boot Simulation**: HTTPS-based boot protocol demonstration
4. **Nuclear Wipe Execution**: Memory sanitization and cache flush
5. **Kernel Transfer**: Control passed to network-downloaded OS
6. **Success Confirmation**: Serial output contains "PhoenixGuard" marker

#### Validation Outputs
- **`out/qemu/serial.log`** - Complete boot sequence capture
- **`out/qemu/report.xml`** - JUnit-compatible test results
- **PASS/FAIL determination** - Based on PhoenixGuard execution markers
- **Timeout handling** - 60-second maximum boot time

## Orchestration
Justfile provides centralized build orchestration with **strict separation** between production workflow and development/demo activities. No demo content can contaminate production builds through any build path.

**Production builds boot real systems. No compromises.**

# PROJECT

PhoenixGuard - Production Firmware Defense System

PhoenixGuard is a production-grade UEFI firmware defense and recovery system designed to detect, neutralize, and recover from advanced persistent firmware threats including bootkits and UEFI rootkits.

## Production-First Architecture

PhoenixGuard has been completely reorganized around a **production-first policy** that enforces strict separation between production code and development/demo content:

### Directory Structure
- **staging/**: Production-ready firmware protection modules (only source for builds)
  - src/ - Core UEFI applications (NuclearBootEdk2, KeyEnrollEdk2)
  - boot/ - Compiled EFI binaries
  - tools/ - Production build scripts
  - include/ - Production headers
- **dev/**: Hardware boot development and platform bring-up code (isolated)
  - boot/ - Hardware-specific boot sequences
  - bringup/ - Platform initialization code
  - tools/ - Hardware debugging and analysis scripts
- **wip/**: Work-in-progress features (excluded from production builds)
  - universal-bios/ - Universal BIOS compatibility system
- **demo/**: Demonstration and testing content (completely quarantined)
  - legacy/, testing/, makefile/ - All demo content isolated here
- **out/**: Build artifacts with strict staging/ sourcing
  - staging/ - Production artifacts (BootX64.efi, manifests)
  - esp/ - Bootable ESP images with checksums
  - qemu/ - Boot test results and serial logs

### Zero-Contamination Policy
Production builds **cannot** access demo, wip, or dev content through any build path. The build system validates this constraint and fails if any external dependencies are detected.

## Production Capabilities
- **Nuclear Boot**: Network-based secure boot bypassing local storage
- **Memory Sanitization**: Nuclear wipe capabilities for anti-forensics
- **Cryptographic Verification**: RSA-4096 signature validation of boot images
- **Hardware Recovery**: Real SPI flash access and firmware restoration
- **Bootkit Detection**: Hardware-level threat detection and bypass
- **Secure Boot Integration**: Custom key enrollment for enterprise deployment
- **Real Hardware Validation**: QEMU-based production boot testing

## Production Build System

Production builds use the **Justfile orchestrator** with CI/CD-style quality gates:

### Core Workflow
1. **`just setup`** - Bootstrap toolchain (gcc, qemu, OVMF, python)
2. **`just build`** - Compile staging/ → out/staging/ (zero external deps)
3. **`just package-esp`** - Create bootable FAT32 ESP with production BootX64.efi
4. **`just qemu-test`** - Full UEFI boot validation with serial capture
5. **`just test`** - Complete production test suite

### Quality Assurance
- **`just lint`** - Static analysis of production sources
- **`just format`** - Code formatting (excludes demo content)
- **`just clean`** - Artifact cleanup with preservation policies

### Validation Requirements
- Production artifacts must boot successfully in QEMU with OVMF firmware
- Serial output must contain PhoenixGuard execution markers
- JUnit-compatible test reports generated for CI integration
- Build manifests track artifact provenance and exclusions

## Enterprise Deployment Philosophy

"Embrace the breach" - The system is designed for enterprise deployment with focus on **availability over prevention**. Rather than halting operations when compromise is detected, PhoenixGuard automatically recovers systems and maintains business continuity while neutralizing threats.

This production-first architecture ensures that deployed systems receive only validated, tested firmware protection components with no development or demonstration code contamination.

# CHANGES

changed: [project structure from mixed-purpose to production-focused]
added: [Justfile orchestrator, PROJECT.txt, WARP.md, staging/ layout, dev/ layout, wip/ layout, demo/ isolation]
modified: []
deleted: []
impact: Clean separation of production code from development and demo content enables reliable enterprise builds
changed: [NuclearBootEdk2.c, KeyEnrollEdk2.c, build-nuclear-boot-edk2.sh]
added: [staging/src/, staging/boot/, staging/tools/]
modified: []
deleted: []
impact: Core production UEFI components organized for clean builds
changed: [hardware_database/, scraped_hardware/, hardware scripts]
impact: Hardware-specific development code isolated from production
changed: [universal_bios_database/, universal_bios scripts, deploy_universal_bios.sh]
impact: WIP features isolated from production builds
changed: [Makefile.demo, bak/, examples/, legacy/, test scripts]
added: [demo/ directory structure]
impact: All demo content isolated and excluded from production

# TODO

TODO-001: Extend production boot features
  category: extend_feature
  rationale: Core boot functionality needs hardening for enterprise deployment
  target_or_path: just build
  acceptance_hint: BootX64.efi artifacts build cleanly from staging/ only

TODO-002: Probe hardware compatibility bugs  
  category: bug_probe
  rationale: Hardware-specific firmware access may fail on diverse platforms
  target_or_path: just qemu-test
  acceptance_hint: QEMU boot test passes with PhoenixGuard marker in serial log

TODO-003: Add secure boot capability
  category: new_capability  
  rationale: Enterprise environments require Secure Boot integration
  target_or_path: staging/src
  acceptance_hint: KeyEnrollEdk2.efi successfully enrolls custom keys

# IDEAS

IDEA-001: AI-Powered Firmware Threat Detection
  concept: Machine learning model trained on firmware compromise patterns
  potential: Real-time detection of novel bootkit signatures during boot process
  implementation: Lightweight TensorFlow Lite model embedded in Nuclear Boot EFI
  impact: Proactive threat detection before compromise completes

IDEA-002: Blockchain-Based Firmware Integrity Ledger
  concept: Immutable distributed ledger for firmware version verification
  potential: Supply chain attack detection through consensus-based validation
  implementation: Integration with enterprise blockchain infrastructure
  impact: Cryptographic proof of firmware authenticity across fleet

IDEA-003: Zero-Trust Network Boot Protocol
  concept: Extended Nuclear Boot with per-connection cryptographic verification
  potential: Eliminate network-based attack vectors in boot process
  implementation: Custom TLS implementation with hardware security module integration
  impact: Network boot security equivalent to local encrypted storage

IDEA-004: Hardware Security Module Integration
  concept: Direct HSM communication for key management and attestation
  potential: Hardware-backed security for all cryptographic operations
  implementation: PKCS#11 interface within UEFI environment
  impact: Cryptographic operations immune to software-based attacks

IDEA-005: Mesh Recovery Network
  concept: Peer-to-peer firmware recovery between trusted fleet members
  potential: Resilient recovery even when centralized servers compromised
  implementation: Distributed hash table for firmware distribution
  impact: Self-healing enterprise infrastructure without single points of failure

- CI/CD integration with automated hardware-in-the-loop testing
- TPM-based firmware integrity attestation and remote verification  
- Container-based firmware recovery environments using Podman
- Machine learning threat detection for advanced bootkit patterns
- Distributed recovery mesh for enterprise-wide firmware coordination

# HOTSPOTS

HOTSPOT-001: EDK2 Development Environment Setup
  location: staging/tools/build-nuclear-boot-edk2.sh
  issue: Build script requires full EDK2 installation but uses pre-built binaries as fallback
  risk: Production builds may not be reproducible without proper EDK2 environment
  priority: HIGH
  action: Establish containerized EDK2 build environment for consistent compilation

HOTSPOT-002: OVMF Firmware Path Dependencies
  location: Justfile qemu-test and package-esp targets
  issue: Hard-coded OVMF paths may not exist on all systems
  risk: QEMU boot tests fail on systems with different OVMF installation paths
  priority: MEDIUM
  action: Add dynamic OVMF discovery logic with multiple fallback paths

HOTSPOT-003: Nuclear Wipe Security Verification
  location: staging/src/NuclearBootEdk2.c (memory sanitization)
  issue: No cryptographic verification of memory wipe completion
  risk: Forensic recovery possible if wipe process fails silently
  priority: HIGH
  action: Add cryptographic hash verification of wiped memory regions

HOTSPOT-004: Network Boot Certificate Validation
  location: Nuclear Boot HTTPS simulation code
  issue: Certificate pinning not implemented for production deployment
  risk: Man-in-the-middle attacks during network boot process
  priority: CRITICAL
  action: Implement certificate pinning and chain validation

HOTSPOT-005: Secure Boot Key Management
  location: staging/src/KeyEnrollEdk2.c
  issue: No automated key rotation or revocation mechanism
  risk: Compromised keys cannot be easily revoked across enterprise fleet
  priority: MEDIUM
  action: Design automated key lifecycle management system

1. staging/src/NuclearBootEdk2.c - Core UEFI application with complex firmware interaction
2. staging/tools/build-nuclear-boot-edk2.sh - Build system single point of failure  
3. dev/tools/hardware_firmware_recovery.py - Direct hardware access, privilege escalation
4. scripts/ - Heterogeneous scripts with varied security models
5. Makefile - Legacy build system conflicts with new Justfile orchestration
