#!/usr/bin/env bash
# Description: Builds the production artifacts from the staging/ directory.

set -euo pipefail
source /home/punk/.venv/bin/activate

FORCE_BUILD=${PG_FORCE_BUILD:-}

# Use prebuilt binaries unless forcing a source rebuild
if [ -z "$FORCE_BUILD" ] && [ -f staging/boot/NuclearBootEdk2.efi ] && [ -f staging/boot/KeyEnrollEdk2.efi ]; then
    echo "✅ Using existing pre-built EFI binaries (unset PG_FORCE_BUILD to force)"
    cp staging/boot/NuclearBootEdk2.efi out/staging/BootX64.efi
    cp staging/boot/KeyEnrollEdk2.efi out/staging/

    # Verify the binary format
    file out/staging/BootX64.efi | grep -q "PE32+" || {
        echo "❌ Invalid EFI binary format"
        exit 1
    }
else
    # Compile from source via EDK2
    if [ -f staging/tools/build-nuclear-boot-edk2.sh ]; then
        echo "🔨 Compiling from source (PG_FORCE_BUILD='${FORCE_BUILD}')..."
        cd staging/src
        chmod +x ../tools/build-nuclear-boot-edk2.sh
        if ! ../tools/build-nuclear-boot-edk2.sh; then
            echo "❌ EDK2 source compilation failed"
            cd ../..
            # If forcing, fail hard; otherwise, fall back to prebuilt if available
            if [ -n "$FORCE_BUILD" ]; then
                exit 1
            elif [ -f staging/boot/NuclearBootEdk2.efi ]; then
                echo "ℹ️  Falling back to prebuilt binaries"
                cp staging/boot/NuclearBootEdk2.efi out/staging/BootX64.efi
                [ -f staging/boot/KeyEnrollEdk2.efi ] && cp staging/boot/KeyEnrollEdk2.efi out/staging/
            else
                echo "❌ No prebuilt binaries available to fall back to"
                exit 1
            fi
        else
            cd ../..
            # After a successful build, copy artifacts from either staging/src or staging/boot
            if [ -f staging/src/NuclearBootEdk2.efi ]; then
                cp staging/src/NuclearBootEdk2.efi out/staging/BootX64.efi
            elif [ -f staging/boot/NuclearBootEdk2.efi ]; then
                cp staging/boot/NuclearBootEdk2.efi out/staging/BootX64.efi
            fi
            if [ -f staging/src/KeyEnrollEdk2.efi ]; then
                cp staging/src/KeyEnrollEdk2.efi out/staging/
            elif [ -f staging/boot/KeyEnrollEdk2.efi ]; then
                cp staging/boot/KeyEnrollEdk2.efi out/staging/
            fi
        fi
    else
        echo "❌ No build script found at staging/tools/build-nuclear-boot-edk2.sh"
        exit 1
    fi
fi

# Generate build manifest
{
    echo '{';
    echo '  "timestamp": "'$(date -Iseconds)'",';
    echo '  "source_tree": "staging/",';
    echo '  "artifacts": [],';
    echo '  "build_type": "production",';
    echo '  "exclusions": ["demo/", "wip/"]';
    echo '}';
} > out/staging/manifest.json

if [ -f out/staging/BootX64.efi ]; then
    echo "✅ Production build complete"
else
    echo "❌ Production build failed - no BootX64.efi generated"
    exit 1
fi

