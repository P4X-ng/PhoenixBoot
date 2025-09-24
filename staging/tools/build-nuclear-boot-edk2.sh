#!/bin/bash
#
# Build Nuclear Boot EDK2 Application
# Integrates with existing PhoenixGuard EDK2 setup
#

set -euo pipefail

# Store original directory at the very beginning
ORIG_DIR=$(pwd)

echo "🦀🔥 Building Nuclear Boot EDK2 Application 🔥🦀"
echo "=================================================="

# Check if we're in the right directory
if [ ! -f "NuclearBootEdk2.c" ] || [ ! -f "NuclearBootEdk2.inf" ]; then
    echo "ERROR: Nuclear Boot source files not found"
    echo "Run this script from the directory containing NuclearBootEdk2.c"
    exit 1
fi

# Check for EDK2 setup
if [ -z "${EDK_TOOLS_PATH:-}" ]; then
    echo "Setting up EDK2 environment..."
    
    # Try to find EDK2 in common locations
    if [ -d "/opt/edk2" ]; then
        export WORKSPACE="/opt/edk2"
    elif [ -d "$HOME/edk2" ]; then
        export WORKSPACE="$HOME/edk2"
    elif [ -d "../../../edk2" ]; then
        export WORKSPACE="$(pwd)/../../../edk2"
    else
        echo "EDK2 not found — cloning to $HOME/edk2 ..."
        git clone --depth=1 https://github.com/tianocore/edk2 "$HOME/edk2"
        export WORKSPACE="$HOME/edk2"
    fi
    
    echo "Using EDK2 workspace: $WORKSPACE"
    
    if [ -f "$WORKSPACE/edksetup.sh" ]; then
        cd "$WORKSPACE"
        # Initialize submodules (e.g., OpenSSL)
        git submodule update --init --depth=1 || true
        # Build BaseTools if missing
        make -C BaseTools -j"${NPROC:-$(nproc 2>/dev/null || echo 2)}" || make -C BaseTools
        # Ensure Python is set for edksetup.sh
        export PYTHON_COMMAND=${PYTHON_COMMAND:-python3}
        # Temporarily relax 'set -u' for edksetup.sh
        set +u
        source edksetup.sh
        set -u
        cd -
    else
        echo "ERROR: EDK2 setup script not found at $WORKSPACE/edksetup.sh"
        exit 1
    fi
fi

# Create application directory in EDK2 workspace
APP_DIR="$WORKSPACE/PhoenixGuardPkg/Application/NuclearBoot"
echo "Creating application directory: $APP_DIR"
mkdir -p "$APP_DIR"

# Copy source files to EDK2 workspace
echo "Copying source files..."
cp NuclearBootEdk2.c "$APP_DIR/"
cp NuclearBootEdk2.inf "$APP_DIR/"

# Create package DSC file if it doesn't exist
PKG_DIR="$WORKSPACE/PhoenixGuardPkg"
DSC_FILE="$PKG_DIR/PhoenixGuardPkg.dsc"

if [ ! -f "$DSC_FILE" ]; then
    echo "Creating PhoenixGuard package DSC file..."
    mkdir -p "$PKG_DIR"
    
    cat > "$DSC_FILE" << 'EOF'
[Defines]
  PLATFORM_NAME                  = PhoenixGuardPkg
  PLATFORM_GUID                  = 87654321-4321-4321-4321-210987654321
  PLATFORM_VERSION               = 0.1
  DSC_SPECIFICATION               = 0x00010006
  OUTPUT_DIRECTORY                = Build/PhoenixGuardPkg
  SUPPORTED_ARCHITECTURES         = X64
  BUILD_TARGETS                   = DEBUG|RELEASE
  SKUID_IDENTIFIER                = DEFAULT

[LibraryClasses]
  UefiApplicationEntryPoint|MdePkg/Library/UefiApplicationEntryPoint/UefiApplicationEntryPoint.inf
  UefiLib|MdePkg/Library/UefiLib/UefiLib.inf
  DebugLib|MdePkg/Library/BaseDebugLibNull/BaseDebugLibNull.inf
  BaseMemoryLib|MdePkg/Library/BaseMemoryLib/BaseMemoryLib.inf
  MemoryAllocationLib|MdePkg/Library/UefiMemoryAllocationLib/UefiMemoryAllocationLib.inf
  PrintLib|MdePkg/Library/BasePrintLib/BasePrintLib.inf
  PcdLib|MdePkg/Library/BasePcdLibNull/BasePcdLibNull.inf
  BaseLib|MdePkg/Library/BaseLib/BaseLib.inf
  UefiBootServicesTableLib|MdePkg/Library/UefiBootServicesTableLib/UefiBootServicesTableLib.inf
  UefiRuntimeServicesTableLib|MdePkg/Library/UefiRuntimeServicesTableLib/UefiRuntimeServicesTableLib.inf
  DevicePathLib|MdePkg/Library/UefiDevicePathLib/UefiDevicePathLib.inf
  BaseCryptLib|CryptoPkg/Library/BaseCryptLib/BaseCryptLib.inf
  OpensslLib|CryptoPkg/Library/OpensslLib/OpensslLib.inf
  RegisterFilterLib|MdePkg/Library/RegisterFilterLibNull/RegisterFilterLibNull.inf
  StackCheckLib|MdePkg/Library/StackCheckLibNull/StackCheckLibNull.inf
  
[Components]
  PhoenixGuardPkg/Application/NuclearBoot/NuclearBootEdk2.inf

[PcdsFixedAtBuild]

[PcdsDynamicDefault]
EOF
    echo "✅ Created $DSC_FILE"
fi

# Create package DEC file if it doesn't exist  
DEC_FILE="$PKG_DIR/PhoenixGuardPkg.dec"

if [ ! -f "$DEC_FILE" ]; then
    echo "Creating PhoenixGuard package DEC file..."
    
    cat > "$DEC_FILE" << 'EOF'
[Defines]
  DEC_SPECIFICATION              = 0x00010006
  PACKAGE_NAME                   = PhoenixGuardPkg
  PACKAGE_GUID                   = 87654321-4321-4321-4321-210987654321
  PACKAGE_VERSION                = 0.1

[Includes]
  Include

[LibraryClasses]

[Guids]

[Protocols]

[PcdsFixedAtBuild]

[PcdsDynamic]
EOF
    echo "✅ Created $DEC_FILE"
fi

# Build the application and KeyEnroll helper
echo ""
echo "🔨 Building Nuclear Boot application..."
echo "======================================="

cd "$WORKSPACE"

# Add KeyEnrollEdk2 to DSC if not present
if ! grep -q "KeyEnrollEdk2" "$DSC_FILE" 2>/dev/null; then
    echo "Adding KeyEnrollEdk2 to DSC components..."
    sed -i '/\[Components\]/a \\  PhoenixGuardPkg/Application/NuclearBoot/KeyEnrollEdk2.inf' "$DSC_FILE" || true
fi

# Stage KeyEnrollEdk2 sources alongside NuclearBoot in workspace
if [ -f "$ORIG_DIR/KeyEnrollEdk2.c" ]; then
    cp -f "$ORIG_DIR/KeyEnrollEdk2.c" "$APP_DIR/"
    cp -f "$ORIG_DIR/KeyEnrollEdk2.inf" "$APP_DIR/"
else
    echo "KeyEnrollEdk2 files not found, removing from DSC"
    sed -i '/\KeyEnrollEdk2/ d' "$DSC_FILE" || true
fi

# Ensure BaseCryptLib, OpensslLib, and IntrinsicLib mappings exist (idempotent)
if ! grep -q "BaseCryptLib|CryptoPkg/Library/BaseCryptLib/BaseCryptLib.inf" "$DSC_FILE" 2>/dev/null; then
    sed -i '/^\s*DevicePathLib|/a \  BaseCryptLib|CryptoPkg/Library/BaseCryptLib/BaseCryptLib.inf' "$DSC_FILE" || true
fi
if ! grep -q "OpensslLib|CryptoPkg/Library/OpensslLib/OpensslLib.inf" "$DSC_FILE" 2>/dev/null; then
    sed -i '/^\s*BaseCryptLib|/a \  OpensslLib|CryptoPkg/Library/OpensslLib/OpensslLib.inf' "$DSC_FILE" || true
fi
if ! grep -q "IntrinsicLib|CryptoPkg/Library/IntrinsicLib/IntrinsicLib.inf" "$DSC_FILE" 2>/dev/null; then
    sed -i '/^\s*OpensslLib|/a \  IntrinsicLib|CryptoPkg/Library/IntrinsicLib/IntrinsicLib.inf' "$DSC_FILE" || true
fi
# Ensure SynchronizationLib mapping exists
if ! grep -q "SynchronizationLib|MdePkg/Library/BaseSynchronizationLib/BaseSynchronizationLib.inf" "$DSC_FILE" 2>/dev/null; then
    sed -i '/^\s*PrintLib|/a \  SynchronizationLib|MdePkg/Library/BaseSynchronizationLib/BaseSynchronizationLib.inf' "$DSC_FILE" || true
fi
# Ensure TimerLib mapping exists
if ! grep -q "TimerLib|MdePkg/Library/BaseTimerLibNullTemplate/BaseTimerLibNullTemplate.inf" "$DSC_FILE" 2>/dev/null; then
    sed -i '/^\s*SynchronizationLib|/a \  TimerLib|MdePkg/Library/BaseTimerLibNullTemplate/BaseTimerLibNullTemplate.inf' "$DSC_FILE" || true
fi
# Ensure RngLib mapping exists
if ! grep -q "RngLib|MdePkg/Library/BaseRngLib/BaseRngLib.inf" "$DSC_FILE" 2>/dev/null; then
    sed -i '/^\s*TimerLib|/a \  RngLib|MdePkg/Library/BaseRngLib/BaseRngLib.inf' "$DSC_FILE" || true
fi

# Build command for X64 architecture
build -p PhoenixGuardPkg/PhoenixGuardPkg.dsc -a X64 -t GCC5 -b RELEASE

BUILD_STATUS=$?

if [ $BUILD_STATUS -eq 0 ]; then
    echo ""
    echo "🎉 BUILD SUCCESSFUL! 🎉"
    echo "======================="
    
    # Find the built EFI file
    EFI_FILE=$(find Build/ -name "NuclearBootEdk2.efi" 2>/dev/null | head -1)
    
    if [ -n "$EFI_FILE" ]; then
        echo "✅ Nuclear Boot EFI application: $WORKSPACE/$EFI_FILE"
        echo ""
        echo "📋 Next steps:"
        echo "   1. Copy to EFI System Partition: cp $EFI_FILE /boot/efi/EFI/PhoenixGuard/"
        echo "   2. Or run in QEMU: qemu-system-x86_64 -bios OVMF.fd -drive format=raw,file=fat:rw:/path/to/efi/files"
        echo "   3. Or test with: ./test-nuclear-boot-edk2.sh"
        
        # Copy back to current directory for convenience
        cp "$WORKSPACE/$EFI_FILE" "$ORIG_DIR/NuclearBootEdk2.efi"
        echo "✅ Copied EFI file to current directory: NuclearBootEdk2.efi"
        # Also sync to staging/boot for packaging paths
        mkdir -p "$ORIG_DIR/../boot"
        cp "$WORKSPACE/$EFI_FILE" "$ORIG_DIR/../boot/NuclearBootEdk2.efi" || true
        
    else
        echo "⚠️  NuclearBootEdk2.efi not found in build output"
    fi

    # Also copy KeyEnrollEdk2.efi if built
    KEY_ENROLL=$(find Build/ -name "KeyEnrollEdk2.efi" 2>/dev/null | head -1)
    if [ -n "$KEY_ENROLL" ]; then
        cp "$WORKSPACE/$KEY_ENROLL" "$ORIG_DIR/KeyEnrollEdk2.efi"
        echo "✅ Copied KeyEnrollEdk2.efi to current directory"
        # Also sync to staging/boot
        mkdir -p "$ORIG_DIR/../boot"
        cp "$WORKSPACE/$KEY_ENROLL" "$ORIG_DIR/../boot/KeyEnrollEdk2.efi" || true
    else
        echo "ℹ️  KeyEnrollEdk2.efi not found (optional)"
    fi
    
    echo ""
    echo "🦀 Nuclear Boot EDK2 build complete!"
    
else
    echo ""
    echo "❌ BUILD FAILED!"
    echo "==============="
    echo "Check the build log above for errors"
    exit 1
fi
