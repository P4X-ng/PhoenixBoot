#!/bin/bash
set -e

echo "🚀 Installing PhoenixGuard AUTONUKE in test VM..."

# Install required packages
sudo apt update
sudo apt install -y python3 python3-pip make flashrom dmidecode tree curl wget

# Install chipsec (may fail in VM, that's OK)
sudo pip3 install chipsec || echo "⚠️  chipsec install failed (expected in VM)"

# Copy PhoenixGuard to /opt
sudo mkdir -p /opt/phoenixguard
sudo cp -r . /opt/phoenixguard/
sudo chown -R $USER:$USER /opt/phoenixguard

# Make scripts executable
chmod +x /opt/phoenixguard/scripts/*.py
chmod +x /opt/phoenixguard/scripts/*.sh

# Create symlink for easy access
ln -sf /opt/phoenixguard/scripts/autonuke.py ~/autonuke

echo "✅ PhoenixGuard installed successfully!"
echo ""
echo "🎯 To test AUTONUKE:"
echo "  cd /opt/phoenixguard && make autonuke"
echo "  OR: ~/autonuke"
echo ""
echo "🔍 Available targets:"
echo "  make scan-bootkits      # Test bootkit detection"
echo "  make build-nuclear-cd   # Test Nuclear Boot CD creation"
echo "  make deploy-esp-iso     # Test ESP virtual CD deployment"
echo "  make autonuke          # 💥 Test full AUTONUKE workflow"
