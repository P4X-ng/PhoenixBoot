#!/usr/bin/env bash
# Description: Creates the initial directory structure for the project.

set -euo pipefail

# Create staging directories
mkdir -p staging/{src,include,boot,drivers,platform,tests,tools}

# Create dev directories
mkdir -p dev/{boot,bringup,tools}

# Create WIP directories
mkdir -p wip/universal-bios

# Create demo directory
mkdir -p demo

# Create output directories
mkdir -p out/{staging,esp,qemu,lint}

# Keep directories with .gitkeep
for dir in staging/{src,include,boot,drivers,platform,tests,tools} dev/{boot,bringup,tools} wip/universal-bios demo out/{staging,esp,qemu,lint}; do
    touch "$dir/.gitkeep"
done

echo "✅ Production directory structure created"

