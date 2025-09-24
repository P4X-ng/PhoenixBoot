#!/bin/bash

# PhoenixGuard Demo Build Script
# "RISE FROM THE ASHES OF COMPROMISED FIRMWARE!"

echo "🔥 Building PhoenixGuard Demo..."
echo ""

# Check if we have gcc
if ! command -v gcc &> /dev/null; then
    echo "❌ Error: gcc not found. Please install build-essential:"
    echo "   sudo apt update && sudo apt install build-essential"
    exit 1
fi

# Build the demo
echo "🔨 Compiling PhoenixGuard demo..."
gcc -o phoenixguard_demo demo.c -std=c99 -Wall -Wextra

if [ $? -eq 0 ]; then
    echo "✅ Build successful!"
    echo ""
    echo "🚀 Running PhoenixGuard demonstration..."
    echo ""
    ./phoenixguard_demo
    echo ""
    echo "🎉 Demo complete!"
    echo ""
    echo "To run again: ./phoenixguard_demo"
    echo "Interactive mode: ./phoenixguard_demo --interactive"
else
    echo "❌ Build failed!"
    exit 1
fi
