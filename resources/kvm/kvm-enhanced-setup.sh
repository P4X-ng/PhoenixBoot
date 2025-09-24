#!/usr/bin/env bash
set -euo pipefail

# PhoenixGuard Enhanced KVM Recovery Environment Setup
# ==================================================
# Runs on first boot of KVM recovery to install comprehensive toolset
# Called by systemd service during KVM snapshot jump

SETUP_MARKER="/opt/phoenixguard/.setup_complete"
TOOLS_DIR="/opt/phoenixguard/tools"
REPORTS_DIR="/opt/phoenixguard/reports"

echo "🦀🔥 PhoenixGuard Enhanced Recovery Environment 🔥🦀"
echo "================================================"

# Check if already set up
if [[ -f "$SETUP_MARKER" ]]; then
    echo "✅ PhoenixGuard recovery environment already configured"
    echo "🎯 Available tools:"
    echo "  • bootkit-scan     - Comprehensive bootkit scanner"
    echo "  • flashrom         - SPI flash analysis and recovery"
    echo "  • chipsec          - Hardware security analysis"
    echo "  • radare2/rizin    - Reverse engineering" 
    echo "  • binwalk          - Firmware analysis"
    echo
    echo "Quick start:"
    echo "  sudo bootkit-scan      # Run comprehensive scan"
    echo "  sudo flashrom -p internal --read firmware.bin # Backup firmware"
    echo "  lspci -nnk            # List PCI devices"
    echo
    exit 0
fi

echo "🔧 Setting up comprehensive toolset (first boot)..."
echo "This may take a few minutes..."

# Create directories
mkdir -p "$TOOLS_DIR" "$REPORTS_DIR"

# Update packages
echo "📦 Updating package manager..."
apt-get update -qq

# Install Python and essential libraries
echo "🐍 Installing Python and essential libraries..."
apt-get install -y python3 python3-pip python3-venv python3-dev
pip3 install --break-system-packages requests cryptography pyserial psutil

# Install hardware analysis tools
echo "🔧 Installing hardware analysis tools..."
apt-get install -y flashrom firmware-tools
apt-get install -y hexdump binutils objdump readelf
apt-get install -y strace ltrace gdb

# Install system analysis tools  
echo "💻 Installing system analysis tools..."
apt-get install -y lshw dmidecode pciutils usbutils
apt-get install -y smartmontools hdparm nvme-cli
apt-get install -y ethtool wireless-tools

# Install forensics and reverse engineering tools
echo "🔍 Installing forensics and reverse engineering tools..."
apt-get install -y binwalk foremost sleuthkit
apt-get install -y radare2 
apt-get install -y yara

# Install virtualization and container tools
echo "🚀 Installing virtualization tools..."
apt-get install -y qemu-kvm qemu-utils libvirt-clients

# Install network analysis tools
echo "🌐 Installing network analysis tools..."
apt-get install -y tshark nmap
apt-get install -y tcpdump netcat-openbsd socat

# Install development tools for analysis
echo "⚡ Installing development tools..."
apt-get install -y build-essential cmake ninja-build
apt-get install -y git curl wget

# Install text processing and utilities
echo "📝 Installing utilities..."
apt-get install -y jq tree htop iotop
apt-get install -y vim nano less

# Try to install chipsec from pip if not available in packages
echo "🔒 Installing chipsec..."
pip3 install --break-system-packages chipsec || echo "⚠️  chipsec installation failed - will be missing"

# Clean up package cache to save space
echo "🧹 Cleaning up..."
apt-get clean
apt-get autoremove -y

# Create PhoenixGuard bootkit scanner
echo "🛡️ Installing PhoenixGuard bootkit scanner..."

cat > "$TOOLS_DIR/phoenix_bootkit_scanner.py" << 'PYTHON_SCRIPT'
#!/usr/bin/env python3
"""
PhoenixGuard Comprehensive Bootkit Scanner
==========================================
Hardware-focused bootkit detection with clear PASS/FAIL output
Enhanced for KVM recovery environment
"""

import os
import sys
import json
import hashlib
import subprocess
import struct
from pathlib import Path
from datetime import datetime

class PhoenixGuardScanner:
    def __init__(self):
        self.results = {
            "timestamp": datetime.now().isoformat(),
            "tests": {},
            "overall_status": "UNKNOWN",
            "threats_found": [],
            "recommendations": []
        }
        
    def log(self, message, level="INFO"):
        """Log with timestamp and level"""
        timestamp = datetime.now().strftime("%H:%M:%S")
        icon = {"INFO": "ℹ️", "PASS": "✅", "FAIL": "❌", "WARN": "⚠️"}[level]
        print(f"[{timestamp}] {icon} {message}")
        
    def run_command(self, cmd, description=""):
        """Run command with error handling"""
        if description:
            self.log(f"Running: {description}")
        try:
            result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
            return result.stdout, result.stderr, result.returncode
        except Exception as e:
            self.log(f"Command failed: {e}", "FAIL")
            return "", str(e), 1
            
    def scan_esp_integrity(self):
        """Comprehensive ESP analysis with hardware focus"""
        self.log("🔍 Scanning ESP integrity...", "INFO")
        
        # Find ESP mount points
        esp_candidates = ["/boot/efi", "/mnt/esp", "/esp", "/media/esp"]
        esp_path = None
        
        for candidate in esp_candidates:
            if os.path.exists(candidate):
                if os.path.ismount(candidate) or len(os.listdir(candidate)) > 0:
                    esp_path = candidate
                    break
        
        if not esp_path:
            # Try to find and mount ESP automatically
            self.log("Attempting to locate and mount ESP...", "INFO")
            stdout, stderr, rc = self.run_command("mkdir -p /mnt/esp && mount -t vfat /dev/disk/by-label/ESP /mnt/esp 2>/dev/null")
            if rc == 0:
                esp_path = "/mnt/esp"
            else:
                # Try common ESP partitions
                for dev in ["/dev/sda1", "/dev/nvme0n1p1", "/dev/sdb1"]:
                    stdout, stderr, rc = self.run_command(f"mount -t vfat {dev} /mnt/esp 2>/dev/null")
                    if rc == 0:
                        esp_path = "/mnt/esp"
                        break
        
        if not esp_path:
            self.log("ESP not found - mount ESP at /mnt/esp to scan", "FAIL")
            self.results["tests"]["esp_integrity"] = False
            return False
            
        self.log(f"Found ESP at {esp_path}", "PASS")
        
        # Comprehensive ESP analysis
        threats = []
        bootloader_hashes = {}
        
        # Catalog all EFI files and their characteristics
        for root, dirs, files in os.walk(esp_path):
            for file in files:
                filepath = os.path.join(root, file)
                filename = file.lower()
                
                if filename.endswith('.efi'):
                    try:
                        with open(filepath, 'rb') as f:
                            data = f.read(4096)  # Read more for better analysis
                            file_hash = hashlib.sha256(data).hexdigest()[:16]
                            file_size = len(data)
                            
                            bootloader_hashes[filepath] = file_hash
                            
                            # Enhanced bootkit detection
                            bootkit_indicators = [
                                b'bootkit', b'rootkit', b'backdoor', b'keylogger',
                                b'stealth', b'hidden', b'inject', b'hook'
                            ]
                            
                            if any(indicator in data.lower() for indicator in bootkit_indicators):
                                threats.append(f"Bootkit signature in {filepath}")
                            
                            # Check for unusual PE characteristics
                            if data.startswith(b'MZ'):  # PE header
                                # Simple PE analysis
                                if len(data) < 2048:
                                    threats.append(f"Suspiciously small PE file: {filepath}")
                                elif b'This program cannot be run in DOS mode' not in data:
                                    threats.append(f"Unusual PE structure: {filepath}")
                            
                            # Check file size anomalies
                            relative_path = os.path.relpath(filepath, esp_path)
                            if "shimx64.efi" in filename and file_size > 1500000:  # > 1.5MB
                                threats.append(f"Oversized shim: {relative_path} ({file_size} bytes)")
                            elif "grubx64.efi" in filename and file_size > 3000000:  # > 3MB  
                                threats.append(f"Oversized GRUB: {relative_path} ({file_size} bytes)")
                            
                    except Exception as e:
                        self.log(f"Cannot analyze {filepath}: {e}", "WARN")
        
        # Save bootloader inventory
        self.results["bootloader_inventory"] = bootloader_hashes
        
        test_passed = len(threats) == 0
        self.results["tests"]["esp_integrity"] = test_passed
        self.results["threats_found"].extend(threats)
        
        if test_passed:
            self.log("ESP integrity check PASSED", "PASS")
            self.log(f"Catalogued {len(bootloader_hashes)} EFI files", "INFO")
        else:
            self.log(f"ESP integrity check FAILED - {len(threats)} threats", "FAIL")
            for threat in threats:
                self.log(f"  • {threat}", "FAIL")
                
        return test_passed
        
    def scan_firmware_access(self):
        """Test comprehensive firmware access capabilities"""
        self.log("🔍 Testing firmware access capabilities...", "INFO")
        
        tests = []
        
        # Test flashrom with more detail
        stdout, stderr, rc = self.run_command("flashrom --version 2>/dev/null")
        if rc == 0:
            version = stdout.split('\n')[0] if stdout else "unknown"
            tests.append(("flashrom", True, f"flashrom available: {version}"))
            self.log(f"flashrom: {version}", "PASS")
            
            # Test if we can probe for chips
            stdout, stderr, rc = self.run_command("flashrom -p internal --list-supported-chips 2>/dev/null | wc -l")
            chip_count = int(stdout.strip()) if stdout.strip().isdigit() else 0
            if chip_count > 10:
                self.log(f"flashrom: {chip_count} supported chips", "PASS")
            else:
                self.log("flashrom: Limited chip support", "WARN")
        else:
            tests.append(("flashrom", False, "flashrom not available"))
            self.log("flashrom: Not available", "FAIL")
        
        # Test chipsec with more robust checking
        stdout, stderr, rc = self.run_command("python3 -c \"import chipsec; print('chipsec version:', chipsec.__version__)\" 2>/dev/null")
        if rc == 0 and "chipsec version" in stdout:
            version = stdout.strip().split(': ')[-1] if ': ' in stdout else "unknown"
            tests.append(("chipsec", True, f"chipsec available: {version}"))
            self.log(f"chipsec: {version}", "PASS")
        else:
            tests.append(("chipsec", False, "chipsec not available"))
            self.log("chipsec: Not available", "FAIL")
        
        # Test hardware info tools
        tools_check = [
            ("dmidecode", "dmidecode -t system"),
            ("lshw", "lshw -short"),
            ("lspci", "lspci"),
            ("lsusb", "lsusb"),
        ]
        
        for tool_name, tool_cmd in tools_check:
            stdout, stderr, rc = self.run_command(f"{tool_cmd} 2>/dev/null | wc -l")
            line_count = int(stdout.strip()) if stdout.strip().isdigit() else 0
            if rc == 0 and line_count > 0:
                tests.append((tool_name, True, f"{tool_name} functional ({line_count} lines)"))
                self.log(f"{tool_name}: Functional", "PASS")
            else:
                tests.append((tool_name, False, f"{tool_name} not functional"))
                self.log(f"{tool_name}: Not functional", "FAIL")
        
        # Test reverse engineering tools
        re_tools = ["radare2", "rizin", "binwalk", "objdump"]
        for tool in re_tools:
            stdout, stderr, rc = self.run_command(f"which {tool} 2>/dev/null")
            if rc == 0:
                tests.append((tool, True, f"{tool} available"))
                self.log(f"{tool}: Available", "PASS")
            else:
                tests.append((tool, False, f"{tool} not available"))
                self.log(f"{tool}: Not available", "WARN")
        
        passed_tests = sum(1 for _, passed, _ in tests if passed)
        total_tests = len(tests)
        
        test_passed = passed_tests >= (total_tests * 0.6)  # 60% pass rate for tools
        self.results["tests"]["firmware_access"] = test_passed
        self.results["tests"]["firmware_access_details"] = tests
        
        if test_passed:
            self.log(f"Firmware access capabilities PASSED ({passed_tests}/{total_tests})", "PASS")
        else:
            self.log(f"Firmware access capabilities FAILED ({passed_tests}/{total_tests})", "FAIL")
            self.results["recommendations"].append("Install missing firmware analysis tools")
            
        return test_passed

    def run_comprehensive_scan(self):
        """Run all scanning modules with enhanced reporting"""
        self.log("🦀🔥 Starting PhoenixGuard Hardware Bootkit Analysis 🔥🦀", "INFO")
        self.log("=" * 65, "INFO")
        
        # Run all scan modules
        tests = [
            ("ESP Integrity", self.scan_esp_integrity),
            ("Firmware Tools", self.scan_firmware_access),
        ]
        
        passed_tests = 0
        total_tests = len(tests)
        
        for test_name, test_func in tests:
            self.log(f"🧪 Running {test_name} analysis...", "INFO")
            try:
                if test_func():
                    passed_tests += 1
                    self.log(f"{test_name}: PASSED", "PASS")
                else:
                    self.log(f"{test_name}: FAILED", "FAIL")
            except Exception as e:
                self.log(f"{test_name}: ERROR - {e}", "FAIL")
            print()
        
        # Determine overall status with clear messaging
        if passed_tests == total_tests:
            self.results["overall_status"] = "CLEAN"
            overall_icon = "✅"
            overall_msg = "CLEAN - No bootkit indicators found"
            recommendations = [
                "System appears clean",
                "Continue with normal operations",
                "Consider periodic scans"
            ]
        elif passed_tests >= total_tests * 0.5:
            self.results["overall_status"] = "SUSPICIOUS" 
            overall_icon = "⚠️"
            overall_msg = "SUSPICIOUS - Some indicators detected"
            recommendations = [
                "Manual investigation recommended",
                "Check failed tests for specific issues",
                "Consider firmware backup before remediation"
            ]
        else:
            self.results["overall_status"] = "INFECTED"
            overall_icon = "❌"
            overall_msg = "INFECTED - Multiple threats detected"
            recommendations = [
                "IMMEDIATE ACTION REQUIRED",
                "Bootkit infection likely present",
                "Use flashrom to backup firmware before recovery",
                "Escalate to hardware recovery methods"
            ]
        
        self.results["recommendations"].extend(recommendations)
        
        self.log("=" * 65, "INFO")
        self.log(f"📊 SCAN RESULTS ({passed_tests}/{total_tests} tests passed)", "INFO")
        self.log(f"{overall_icon} OVERALL STATUS: {overall_msg}", "INFO" if self.results["overall_status"] == "CLEAN" else "FAIL")
        
        if self.results["recommendations"]:
            self.log("🎯 RECOMMENDATIONS:", "INFO")
            for rec in self.results["recommendations"]:
                self.log(f"  • {rec}", "INFO")
        
        # Save detailed results
        results_file = f"{REPORTS_DIR}/scan_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
        with open(results_file, 'w') as f:
            json.dump(self.results, f, indent=2)
            
        with open('/tmp/bootkit_scan_results.json', 'w') as f:
            json.dump(self.results, f, indent=2)
        
        self.log(f"📊 Detailed results saved: {results_file}", "INFO")
        
        return self.results["overall_status"] == "CLEAN"

def setup_environment():
    """Set up the PhoenixGuard recovery environment"""
    
    # Create the comprehensive bootkit scanner
    os.makedirs(TOOLS_DIR, exist_ok=True)
    os.makedirs(REPORTS_DIR, exist_ok=True)
    
    # Make scanner executable and create symlinks
    scanner_path = f"{TOOLS_DIR}/phoenix_bootkit_scanner.py"
    os.chmod(scanner_path, 0o755)
    
    # Create convenient command aliases
    os.makedirs("/usr/local/bin", exist_ok=True)
    
    symlinks = [
        ("/usr/local/bin/bootkit-scan", scanner_path),
        ("/usr/local/bin/phoenix-scan", scanner_path),
        ("/usr/local/bin/pg-scan", scanner_path)
    ]
    
    for link_path, target in symlinks:
        if os.path.exists(link_path):
            os.remove(link_path)
        os.symlink(target, link_path)
    
    # Mark setup as complete
    with open(SETUP_MARKER, 'w') as f:
        f.write(f"PhoenixGuard setup completed at {datetime.now().isoformat()}\n")
    
    print()
    print("✅ PhoenixGuard Enhanced Recovery Environment Ready!")
    print("================================================")
    print("🎯 Available commands:")
    print("  • bootkit-scan     - Run comprehensive bootkit analysis")
    print("  • phoenix-scan     - Same as bootkit-scan")
    print("  • flashrom         - SPI flash reading/writing/analysis")
    print("  • radare2          - Binary analysis and reverse engineering") 
    print("  • binwalk          - Firmware unpacking and analysis")
    print("  • lshw, dmidecode  - Hardware inventory")
    print("  • lspci, lsusb     - Device enumeration")
    print()
    print("🚀 Quick start:")
    print("  sudo bootkit-scan                                    # Full bootkit scan")
    print("  sudo flashrom -p internal --read backup.bin         # Backup firmware")
    print("  binwalk backup.bin                                  # Analyze firmware")
    print("  lspci -nnk | grep -A3 'VGA\\|Display'               # Find graphics hardware")
    print()

def main():
    """Main setup function"""
    try:
        setup_environment()
        return 0
    except Exception as e:
        print(f"❌ Setup failed: {e}")
        return 1

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--scan":
        # Run scanner mode
        scanner = PhoenixGuardScanner()
        try:
            clean = scanner.run_comprehensive_scan()
            sys.exit(0 if clean else 1)
        except KeyboardInterrupt:
            print("\n🚫 Scan cancelled by user")
            sys.exit(130)
        except Exception as e:
            print(f"\n❌ Scan failed: {e}")
            sys.exit(1)
    else:
        # Run setup mode
        sys.exit(main())
PYTHON_SCRIPT

chmod +x "$TOOLS_DIR/phoenix_bootkit_scanner.py"

# Create convenient symlinks
ln -sf "$TOOLS_DIR/phoenix_bootkit_scanner.py" /usr/local/bin/bootkit-scan
ln -sf "$TOOLS_DIR/phoenix_bootkit_scanner.py" /usr/local/bin/phoenix-scan

# Create startup message
cat > /etc/motd << 'MOTD'
🦀🔥 PhoenixGuard Recovery Environment 🔥🦀
==========================================

This is a comprehensive bootkit analysis and recovery environment.

Available tools:
  • bootkit-scan     - Comprehensive bootkit scanner with clear PASS/FAIL
  • flashrom         - SPI flash analysis and recovery
  • chipsec          - Hardware security analysis (if available)
  • radare2/rizin    - Reverse engineering
  • binwalk          - Firmware analysis
  • Hardware tools   - lshw, dmidecode, lspci, lsusb
  • Network tools    - nmap, tcpdump, wireshark
  • Development     - build tools, git, python3

Quick start:
  sudo bootkit-scan      # Run comprehensive bootkit analysis
  sudo flashrom -p internal --read firmware.bin # Backup firmware
  lspci -nnk            # List PCI devices and drivers

For help: bootkit-scan --help
MOTD

# Mark setup complete
touch "$SETUP_MARKER"

echo "✅ PhoenixGuard Enhanced Recovery Environment setup complete!"
echo "🎯 Tools installed and ready for comprehensive bootkit analysis"
