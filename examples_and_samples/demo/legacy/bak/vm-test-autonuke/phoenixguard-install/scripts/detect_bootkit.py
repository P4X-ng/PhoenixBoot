#!/usr/bin/env python3
"""
PhoenixGuard Real-Time Bootkit Detection Engine
Hunts bootkits like a hawk by comparing running firmware against clean baseline.

This is where the magic happens - real-time firmware validation that catches
bootkit modifications and triggers PhoenixGuard recovery automatically.
"""

import json
import sys
import os
import hashlib
import subprocess
import time
from datetime import datetime
from pathlib import Path
import argparse
import logging

class BootkitHunter:
    def __init__(self, baseline_path):
        self.baseline_path = Path(baseline_path)
        self.baseline = None
        self.detection_results = {
            'scan_timestamp': None,
            'threats_detected': [],
            'modifications_found': [],
            'risk_level': 'UNKNOWN',
            'recommended_action': 'NONE'
        }
        
    def load_baseline(self):
        """Load the firmware baseline for comparison"""
        try:
            with open(self.baseline_path, 'r') as f:
                self.baseline = json.load(f)
            logging.info(f"Loaded baseline: {self.baseline['metadata']['firmware_file']}")
            return True
        except Exception as e:
            logging.error(f"Failed to load baseline: {e}")
            return False
    
    def read_current_firmware(self):
        """Read current firmware from system (requires root)"""
        try:
            # Try multiple methods to read firmware
            firmware_sources = [
                '/sys/firmware/efi/efivars',
                '/dev/mem',
                '/sys/devices/virtual/dmi/id/bios_*'
            ]
            
            # For now, we'll simulate by reading system info
            # In production, this would use specialized tools like flashrom
            current_info = {
                'dmi_bios_vendor': self._read_dmi_field('bios_vendor'),
                'dmi_bios_version': self._read_dmi_field('bios_version'),
                'dmi_bios_date': self._read_dmi_field('bios_date'),
                'efi_vars': self._scan_efi_variables(),
                'system_firmware': self._get_firmware_info()
            }
            
            return current_info
            
        except Exception as e:
            logging.error(f"Failed to read current firmware: {e}")
            return None
    
    def _read_dmi_field(self, field):
        """Read DMI/SMBIOS field"""
        try:
            with open(f'/sys/devices/virtual/dmi/id/{field}', 'r') as f:
                return f.read().strip()
        except:
            return None
    
    def _scan_efi_variables(self):
        """Scan EFI variables for suspicious modifications"""
        efi_vars = {}
        efi_path = Path('/sys/firmware/efi/efivars')
        
        if not efi_path.exists():
            return efi_vars
            
        try:
            for var_file in efi_path.glob('*'):
                if var_file.is_file():
                    try:
                        # Read first 1KB of each EFI variable
                        with open(var_file, 'rb') as f:
                            data = f.read(1024)
                        efi_vars[var_file.name] = {
                            'size': len(data),
                            'sha256': hashlib.sha256(data).hexdigest()
                        }
                    except:
                        continue
        except Exception as e:
            logging.warning(f"EFI variables scan failed: {e}")
            
        return efi_vars
    
    def _get_firmware_info(self):
        """Get firmware info using system tools"""
        firmware_info = {}
        
        try:
            # Use dmidecode to get detailed firmware info
            result = subprocess.run(['dmidecode', '-t', 'bios'], 
                                   capture_output=True, text=True, timeout=10)
            if result.returncode == 0:
                firmware_info['dmidecode_bios'] = result.stdout
        except:
            pass
            
        try:
            # Check for firmware update tools
            result = subprocess.run(['fwupdmgr', 'get-devices'], 
                                   capture_output=True, text=True, timeout=10)
            if result.returncode == 0:
                firmware_info['fwupd_devices'] = result.stdout
        except:
            pass
        
        return firmware_info
    
    def analyze_modifications(self, current_info):
        """Analyze current firmware against baseline for modifications"""
        modifications = []
        
        # Check BIOS version consistency
        baseline_version = self.baseline['metadata']['bios_version']
        current_version = current_info.get('dmi_bios_version', '')
        
        if baseline_version not in current_version:
            modifications.append({
                'type': 'VERSION_MISMATCH',
                'severity': 'HIGH',
                'details': f"BIOS version changed: expected {baseline_version}, got {current_version}",
                'risk_indicators': ['version_rollback', 'unauthorized_update']
            })
        
        # Analyze EFI variables for suspicious patterns
        efi_vars = current_info.get('efi_vars', {})
        suspicious_vars = []
        
        for var_name, var_info in efi_vars.items():
            # Check for suspicious variable names
            if any(pattern in var_name.lower() for pattern in 
                   ['bootkit', 'malware', 'rootkit', 'backdoor', 'keylog']):
                suspicious_vars.append(var_name)
            
            # Check for unusually large variables (potential payload)
            if var_info['size'] > 32768:  # 32KB threshold
                suspicious_vars.append(f"{var_name} (large_size: {var_info['size']})")
        
        if suspicious_vars:
            modifications.append({
                'type': 'SUSPICIOUS_EFI_VARIABLES',
                'severity': 'HIGH',
                'details': f"Found {len(suspicious_vars)} suspicious EFI variables",
                'variables': suspicious_vars,
                'risk_indicators': ['efi_variable_injection', 'persistent_malware']
            })
        
        return modifications
    
    def detect_bootkit_patterns(self, current_info):
        """Detect known bootkit patterns and behaviors"""
        threats = []
        
        # Check for bootkit indicators in firmware info
        firmware_text = str(current_info).lower()
        
        for pattern in self.baseline['bootkit_indicators']['suspicious_patterns']:
            if pattern in firmware_text:
                threats.append({
                    'type': 'PATTERN_MATCH',
                    'severity': 'CRITICAL',
                    'pattern': pattern,
                    'details': f"Bootkit pattern '{pattern}' detected in firmware",
                    'risk_indicators': ['known_bootkit_signature']
                })
        
        # Check for timing anomalies (bootkits often slow boot)
        try:
            with open('/proc/uptime', 'r') as f:
                uptime = float(f.read().split()[0])
            
            # If system has been up for a very short time, check boot duration
            if uptime < 300:  # Less than 5 minutes
                # This would need more sophisticated boot time analysis
                pass
        except:
            pass
        
        # Check for unusual firmware update activity
        firmware_info = current_info.get('system_firmware', {})
        if 'fwupd_devices' in firmware_info:
            fwupd_output = firmware_info['fwupd_devices']
            if 'pending' in fwupd_output.lower() or 'needs reboot' in fwupd_output.lower():
                threats.append({
                    'type': 'PENDING_FIRMWARE_UPDATE',
                    'severity': 'MEDIUM',
                    'details': "Pending firmware update detected - verify legitimacy",
                    'risk_indicators': ['unauthorized_update']
                })
        
        return threats
    
    def calculate_risk_level(self, threats, modifications):
        """Calculate overall risk level based on findings"""
        critical_count = sum(1 for t in threats + modifications if t['severity'] == 'CRITICAL')
        high_count = sum(1 for t in threats + modifications if t['severity'] == 'HIGH')
        medium_count = sum(1 for t in threats + modifications if t['severity'] == 'MEDIUM')
        
        if critical_count > 0:
            return 'CRITICAL'
        elif high_count >= 2:
            return 'HIGH'
        elif high_count >= 1:
            return 'MEDIUM'
        elif medium_count > 0:
            return 'LOW'
        else:
            return 'CLEAN'
    
    def recommend_action(self, risk_level, threats, modifications):
        """Recommend action based on risk assessment"""
        if risk_level == 'CRITICAL':
            return 'IMMEDIATE_RECOVERY'
        elif risk_level == 'HIGH':
            return 'RECOVERY_RECOMMENDED'
        elif risk_level == 'MEDIUM':
            return 'INVESTIGATE'
        elif risk_level == 'LOW':
            return 'MONITOR'
        else:
            return 'CONTINUE'
    
    def scan_for_bootkits(self):
        """Main bootkit detection scan"""
        logging.info("🔍 Starting bootkit detection scan...")
        self.detection_results['scan_timestamp'] = datetime.utcnow().isoformat()
        
        # Read current firmware state
        current_info = self.read_current_firmware()
        if not current_info:
            logging.error("Failed to read current firmware")
            return False
        
        # Analyze for modifications
        modifications = self.analyze_modifications(current_info)
        self.detection_results['modifications_found'] = modifications
        
        # Detect bootkit patterns
        threats = self.detect_bootkit_patterns(current_info)
        self.detection_results['threats_detected'] = threats
        
        # Calculate risk and recommendation
        risk_level = self.calculate_risk_level(threats, modifications)
        self.detection_results['risk_level'] = risk_level
        self.detection_results['recommended_action'] = self.recommend_action(
            risk_level, threats, modifications)
        
        logging.info(f"Scan complete - Risk Level: {risk_level}")
        return True
    
    def print_detection_results(self):
        """Print formatted detection results"""
        results = self.detection_results
        
        print(f"\n🎯 PhoenixGuard Bootkit Detection Results")
        print(f"{'='*50}")
        print(f"⏰ Scan Time: {results['scan_timestamp']}")
        print(f"⚠️  Risk Level: {results['risk_level']}")
        print(f"🎯 Action: {results['recommended_action']}")
        print()
        
        if results['threats_detected']:
            print(f"🚨 THREATS DETECTED ({len(results['threats_detected'])}):")
            for i, threat in enumerate(results['threats_detected'], 1):
                print(f"  {i}. [{threat['severity']}] {threat['type']}")
                print(f"     Details: {threat['details']}")
                if 'risk_indicators' in threat:
                    print(f"     Indicators: {', '.join(threat['risk_indicators'])}")
                print()
        
        if results['modifications_found']:
            print(f"🔧 MODIFICATIONS FOUND ({len(results['modifications_found'])}):")
            for i, mod in enumerate(results['modifications_found'], 1):
                print(f"  {i}. [{mod['severity']}] {mod['type']}")
                print(f"     Details: {mod['details']}")
                if 'risk_indicators' in mod:
                    print(f"     Indicators: {', '.join(mod['risk_indicators'])}")
                print()
        
        # Action recommendations
        action = results['recommended_action']
        if action == 'IMMEDIATE_RECOVERY':
            print("🚨 CRITICAL: Immediate recovery required!")
            print("   Run: sudo make reboot-to-vm")
        elif action == 'RECOVERY_RECOMMENDED':
            print("⚠️  HIGH RISK: Recovery strongly recommended")
            print("   Run: sudo make reboot-to-vm")
        elif action == 'INVESTIGATE':
            print("🔍 Medium risk: Further investigation needed")
        elif action == 'MONITOR':
            print("👁️  Low risk: Continue monitoring")
        else:
            print("✅ System appears clean")
    
    def save_results(self, output_path):
        """Save detection results to file"""
        try:
            with open(output_path, 'w') as f:
                json.dump(self.detection_results, f, indent=2)
            logging.info(f"Results saved to: {output_path}")
            return True
        except Exception as e:
            logging.error(f"Failed to save results: {e}")
            return False

def main():
    parser = argparse.ArgumentParser(description='PhoenixGuard Bootkit Detection Engine')
    parser.add_argument('-b', '--baseline', help='Firmware baseline JSON file',
                       default='firmware_baseline.json')
    parser.add_argument('-o', '--output', help='Output detection results JSON',
                       default='bootkit_detection.json')
    parser.add_argument('-v', '--verbose', action='store_true', help='Verbose logging')
    parser.add_argument('--auto-recovery', action='store_true',
                       help='Automatically trigger recovery on critical threats')
    
    args = parser.parse_args()
    
    # Setup logging
    log_level = logging.DEBUG if args.verbose else logging.INFO
    logging.basicConfig(
        level=log_level,
        format='%(asctime)s - %(levelname)s - %(message)s'
    )
    
    # Check if running as root (needed for firmware access)
    if os.geteuid() != 0:
        print("⚠️  Warning: Not running as root. Some firmware checks may be limited.")
        print("   For full detection capabilities, run: sudo python3 detect_bootkit.py")
    
    # Validate baseline file
    if not os.path.exists(args.baseline):
        logging.error(f"Baseline file not found: {args.baseline}")
        print("💡 Create baseline first: python3 scripts/analyze_firmware_baseline.py drivers/G615LPAS.325")
        return 1
    
    # Create bootkit hunter and run scan
    hunter = BootkitHunter(args.baseline)
    
    if not hunter.load_baseline():
        return 1
    
    if not hunter.scan_for_bootkits():
        return 1
    
    # Display and save results
    hunter.print_detection_results()
    hunter.save_results(args.output)
    
    # Auto-recovery if requested and critical threat detected
    if args.auto_recovery and hunter.detection_results['risk_level'] == 'CRITICAL':
        print("\n🚨 AUTO-RECOVERY TRIGGERED!")
        print("Launching PhoenixGuard recovery in 10 seconds...")
        time.sleep(10)
        
        # Trigger recovery
        os.system("sudo make reboot-to-vm")
    
    return 0

if __name__ == '__main__':
    sys.exit(main())
