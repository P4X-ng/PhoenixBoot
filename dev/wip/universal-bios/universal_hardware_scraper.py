#!/usr/bin/env python3
"""
PhoenixGuard Universal Hardware Discovery & Configuration Database
=================================================================

This system discovers hardware configurations across different machines
and builds a comprehensive database of UEFI variables, firmware features,
and hidden configuration options.

GOAL: Map EVERY hardware configuration and expose hidden features!

Usage:
1. Run on different machines to collect hardware profiles
2. Submit profiles to central database
3. Download configurations for specific hardware
4. Deploy universal BIOS with proper hardware support
"""

import os
import json
import subprocess
import requests
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional
from dataclasses import dataclass

@dataclass
class HardwareProfile:
    """Hardware profile data structure"""
    hardware_id: str
    manufacturer: str
    model: str
    bios_version: str
    cpu_info: Dict
    uefi_variables: Dict
    hidden_features: List[str]
    configuration_options: Dict
    timestamp: str

class UniversalHardwareScraper:
    def __init__(self):
        self.profile = None
        self.database_url = "https://phoenixguard.example.com/api/hardware"  # Future API
        self.local_db_path = Path("hardware_database")
        self.local_db_path.mkdir(exist_ok=True)
        
    def detect_hardware(self) -> Dict:
        """Detect current hardware configuration"""
        print("🔍 DETECTING HARDWARE CONFIGURATION...")
        
        hardware_info = {}
        
        try:
            # System information
            hardware_info['manufacturer'] = self._run_dmidecode("system-manufacturer") 
            hardware_info['product_name'] = self._run_dmidecode("system-product-name")
            hardware_info['version'] = self._run_dmidecode("system-version")
            hardware_info['serial'] = self._run_dmidecode("system-serial-number")
            hardware_info['uuid'] = self._run_dmidecode("system-uuid")
            
            # Motherboard info
            hardware_info['board_manufacturer'] = self._run_dmidecode("baseboard-manufacturer")
            hardware_info['board_product'] = self._run_dmidecode("baseboard-product-name")
            hardware_info['board_version'] = self._run_dmidecode("baseboard-version")
            
            # BIOS info
            hardware_info['bios_vendor'] = self._run_dmidecode("bios-vendor")
            hardware_info['bios_version'] = self._run_dmidecode("bios-version")
            hardware_info['bios_date'] = self._run_dmidecode("bios-release-date")
            
            # CPU info
            hardware_info['cpu_info'] = self._get_cpu_info()
            
            # Memory info
            hardware_info['memory_info'] = self._get_memory_info()
            
            # Generate unique hardware ID
            hardware_info['hardware_id'] = self._generate_hardware_id(hardware_info)
            
        except Exception as e:
            print(f"⚠️  Error detecting hardware: {e}")
            
        return hardware_info
    
    def _run_dmidecode(self, field: str) -> str:
        """Run dmidecode command safely"""
        try:
            result = subprocess.run(['dmidecode', '-s', field], 
                                  capture_output=True, text=True, timeout=10)
            return result.stdout.strip() if result.returncode == 0 else "Unknown"
        except Exception:
            return "Unknown"
    
    def _get_cpu_info(self) -> Dict:
        """Get detailed CPU information"""
        cpu_info = {}
        try:
            with open('/proc/cpuinfo', 'r') as f:
                lines = f.readlines()
                
            for line in lines:
                if ':' in line:
                    key, value = line.strip().split(':', 1)
                    key = key.strip()
                    value = value.strip()
                    
                    if key == 'model name':
                        cpu_info['model'] = value
                        break
            
            # Get CPU features
            result = subprocess.run(['lscpu'], capture_output=True, text=True)
            if result.returncode == 0:
                for line in result.stdout.split('\\n'):
                    if 'Flags:' in line:
                        cpu_info['features'] = line.split(':', 1)[1].strip()
                        break
                        
        except Exception as e:
            cpu_info['error'] = str(e)
            
        return cpu_info
    
    def _get_memory_info(self) -> Dict:
        """Get memory configuration"""
        memory_info = {}
        try:
            # Get memory from /proc/meminfo
            with open('/proc/meminfo', 'r') as f:
                lines = f.readlines()
                
            for line in lines:
                if line.startswith('MemTotal:'):
                    memory_info['total'] = line.split()[1] + " kB"
                    break
            
            # Get memory modules via dmidecode
            result = subprocess.run(['dmidecode', '--type', 'memory'], 
                                  capture_output=True, text=True)
            if result.returncode == 0:
                memory_info['modules'] = self._parse_memory_modules(result.stdout)
                
        except Exception as e:
            memory_info['error'] = str(e)
            
        return memory_info
    
    def _parse_memory_modules(self, dmidecode_output: str) -> List[Dict]:
        """Parse memory module information"""
        modules = []
        current_module = {}
        
        for line in dmidecode_output.split('\\n'):
            line = line.strip()
            
            if line.startswith('Memory Device'):
                if current_module:
                    modules.append(current_module)
                current_module = {}
                
            elif ':' in line:
                key, value = line.split(':', 1)
                key = key.strip()
                value = value.strip()
                
                if key in ['Size', 'Speed', 'Manufacturer', 'Part Number', 'Type']:
                    current_module[key.lower().replace(' ', '_')] = value
        
        if current_module:
            modules.append(current_module)
            
        return modules
    
    def _generate_hardware_id(self, hardware_info: Dict) -> str:
        """Generate unique hardware identifier"""
        components = [
            hardware_info.get('manufacturer', 'Unknown'),
            hardware_info.get('product_name', 'Unknown'),
            hardware_info.get('board_product', 'Unknown'),
            hardware_info.get('cpu_info', {}).get('model', 'Unknown')[:50]  # Truncate long CPU names
        ]
        
        # Clean and join
        clean_components = []
        for comp in components:
            clean = ''.join(c for c in comp if c.isalnum() or c in ['-', '_', ' '])
            clean = clean.replace(' ', '_')
            clean_components.append(clean)
            
        return '_'.join(clean_components)
    
    def discover_uefi_variables(self) -> Dict:
        """Discover all UEFI variables (reuse from previous discovery)"""
        print("🔍 DISCOVERING UEFI VARIABLES...")
        
        variables = {}
        efi_vars_path = Path("/sys/firmware/efi/efivars")
        
        if not efi_vars_path.exists():
            print("❌ UEFI variables not accessible")
            return variables
        
        var_files = list(efi_vars_path.glob("*"))
        print(f"📊 Found {len(var_files)} UEFI variables")
        
        # Categorize variables
        categories = {
            'boot': [],
            'security': [],
            'vendor_specific': [],
            'performance': [],
            'hardware': [],
            'unknown': []
        }
        
        for var_file in var_files:
            try:
                var_name = var_file.name.split('-')[0]
                var_info = {
                    'name': var_name,
                    'full_name': var_file.name,
                    'size': var_file.stat().st_size,
                    'category': self._categorize_variable(var_name)
                }
                
                variables[var_name] = var_info
                categories[var_info['category']].append(var_info)
                
            except Exception as e:
                continue
        
        return {
            'total_count': len(variables),
            'variables': variables,
            'categories': {k: len(v) for k, v in categories.items()}
        }
    
    def _categorize_variable(self, var_name: str) -> str:
        """Categorize UEFI variable by name"""
        name_lower = var_name.lower()
        
        if 'boot' in name_lower or var_name.startswith('Boot'):
            return 'boot'
        elif any(x in name_lower for x in ['secure', 'pk', 'kek', 'db']):
            return 'security'  
        elif any(x in name_lower for x in ['asus', 'dell', 'hp', 'lenovo', 'intel', 'amd']):
            return 'vendor_specific'
        elif any(x in name_lower for x in ['cpu', 'memory', 'perf', 'overclock']):
            return 'performance'
        elif any(x in name_lower for x in ['pci', 'usb', 'sata', 'nvme', 'device']):
            return 'hardware'
        else:
            return 'unknown'
    
    def analyze_hidden_features(self, hardware_info: Dict, uefi_vars: Dict) -> List[str]:
        """Analyze potentially hidden features"""
        print("🕵️  ANALYZING HIDDEN FEATURES...")
        
        hidden_features = []
        
        # Check for vendor-specific variables that might indicate hidden features
        vendor_vars = uefi_vars.get('variables', {})
        vendor_count = uefi_vars.get('categories', {}).get('vendor_specific', 0)
        
        if vendor_count > 5:
            hidden_features.append(f"Extensive vendor customization ({vendor_count} variables)")
        
        # Check for gaming-specific features
        gaming_indicators = ['asus', 'rog', 'armoury', 'crate', 'gaming', 'performance']
        gaming_vars = [name for name in vendor_vars.keys() 
                      if any(indicator in name.lower() for indicator in gaming_indicators)]
        
        if gaming_vars:
            hidden_features.append(f"Gaming optimizations ({len(gaming_vars)} variables)")
        
        # Check for overclocking features
        oc_indicators = ['overclock', 'boost', 'turbo', 'frequency', 'voltage']
        oc_vars = [name for name in vendor_vars.keys()
                  if any(indicator in name.lower() for indicator in oc_indicators)]
        
        if oc_vars:
            hidden_features.append(f"Overclocking controls ({len(oc_vars)} variables)")
        
        # Check for security features
        security_count = uefi_vars.get('categories', {}).get('security', 0)
        if security_count > 10:
            hidden_features.append(f"Advanced security features ({security_count} variables)")
        
        # Check for hardware-specific features
        hw_count = uefi_vars.get('categories', {}).get('hardware', 0)
        if hw_count > 15:
            hidden_features.append(f"Extensive hardware controls ({hw_count} variables)")
        
        return hidden_features
    
    def generate_configuration_options(self, hardware_info: Dict, uefi_vars: Dict) -> Dict:
        """Generate available configuration options"""
        print("⚙️  GENERATING CONFIGURATION OPTIONS...")
        
        config_options = {
            'boot_options': {
                'fast_boot': 'Available',
                'secure_boot': 'Configurable',
                'boot_order': 'Full control',
                'recovery_boot': 'PhoenixGuard integration'
            },
            
            'performance_options': {
                'cpu_boost': 'Hardware dependent',
                'memory_timing': 'Advanced controls available',
                'thermal_management': 'Vendor optimizations',
                'power_profiles': 'Multiple profiles supported'
            },
            
            'security_options': {
                'secure_boot_keys': 'Custom key support',
                'firmware_protection': 'Configurable levels',
                'device_encryption': 'TPM integration',
                'privacy_controls': 'Camera/microphone management'
            },
            
            'hardware_options': {
                'usb_configuration': 'Per-port control',
                'pcie_settings': 'Lane configuration',
                'storage_modes': 'AHCI/RAID/NVMe options',
                'connectivity': 'WiFi/Bluetooth fine-tuning'
            }
        }
        
        # Customize based on detected hardware
        if 'rog' in hardware_info.get('product_name', '').lower():
            config_options['gaming_options'] = {
                'game_mode': 'Automatic detection',
                'rgb_lighting': 'Full spectrum control',
                'performance_profiles': 'Gaming-optimized presets',
                'overclocking': 'Safe overclocking profiles'
            }
        
        return config_options
    
    def create_hardware_profile(self) -> HardwareProfile:
        """Create complete hardware profile"""
        print("🔥 CREATING COMPLETE HARDWARE PROFILE...")
        print("=" * 60)
        
        # Collect all data
        hardware_info = self.detect_hardware()
        uefi_vars = self.discover_uefi_variables()
        hidden_features = self.analyze_hidden_features(hardware_info, uefi_vars)
        config_options = self.generate_configuration_options(hardware_info, uefi_vars)
        
        # Create profile
        profile = HardwareProfile(
            hardware_id=hardware_info.get('hardware_id', 'unknown'),
            manufacturer=hardware_info.get('manufacturer', 'Unknown'),
            model=hardware_info.get('product_name', 'Unknown'),
            bios_version=hardware_info.get('bios_version', 'Unknown'),
            cpu_info=hardware_info.get('cpu_info', {}),
            uefi_variables=uefi_vars,
            hidden_features=hidden_features,
            configuration_options=config_options,
            timestamp=datetime.now().isoformat()
        )
        
        self.profile = profile
        return profile
    
    def save_profile_locally(self, profile: HardwareProfile):
        """Save profile to local database"""
        profile_file = self.local_db_path / f"{profile.hardware_id}.json"
        
        profile_data = {
            'hardware_id': profile.hardware_id,
            'manufacturer': profile.manufacturer,
            'model': profile.model,
            'bios_version': profile.bios_version,
            'cpu_info': profile.cpu_info,
            'uefi_variables': profile.uefi_variables,
            'hidden_features': profile.hidden_features,
            'configuration_options': profile.configuration_options,
            'timestamp': profile.timestamp
        }
        
        with open(profile_file, 'w') as f:
            json.dump(profile_data, f, indent=2)
        
        print(f"✅ Profile saved locally: {profile_file}")
        
    def submit_to_database(self, profile: HardwareProfile):
        """Submit profile to central database (future feature)"""
        print("📡 SUBMITTING TO CENTRAL DATABASE...")
        
        # This would submit to a central PhoenixGuard database
        print("🔮 Central database not yet implemented")
        print("📝 Future: Crowdsourced hardware configuration database")
        print("🎯 Goal: Build comprehensive hardware support database")
        
    def list_supported_hardware(self):
        """List locally supported hardware"""
        print("💾 LOCALLY SUPPORTED HARDWARE:")
        print("=" * 40)
        
        profiles = list(self.local_db_path.glob("*.json"))
        
        if not profiles:
            print("No hardware profiles found locally.")
            return
            
        for profile_file in profiles:
            try:
                with open(profile_file, 'r') as f:
                    data = json.load(f)
                
                print(f"🖥️  {data['manufacturer']} {data['model']}")
                print(f"    Hardware ID: {data['hardware_id']}")
                print(f"    BIOS: {data['bios_version']}")
                print(f"    Variables: {data['uefi_variables'].get('total_count', 0)}")
                print(f"    Hidden Features: {len(data['hidden_features'])}")
                print()
                
            except Exception as e:
                print(f"⚠️  Error reading {profile_file}: {e}")
    
    def generate_universal_config_for_hardware(self, hardware_id: str):
        """Generate universal BIOS config for specific hardware"""
        profile_file = self.local_db_path / f"{hardware_id}.json"
        
        if not profile_file.exists():
            print(f"❌ Hardware profile not found: {hardware_id}")
            return None
            
        with open(profile_file, 'r') as f:
            profile_data = json.load(f)
        
        print(f"🎯 GENERATING UNIVERSAL CONFIG FOR: {profile_data['model']}")
        print("=" * 60)
        
        # Generate hardware-specific configuration
        universal_config = {
            'target_hardware': profile_data['hardware_id'],
            'manufacturer': profile_data['manufacturer'],
            'model': profile_data['model'],
            'generated_date': datetime.now().isoformat(),
            
            'uefi_variables': profile_data['uefi_variables'],
            'configuration_options': profile_data['configuration_options'],
            'hidden_features': profile_data['hidden_features'],
            
            'deployment_instructions': {
                'method': 'phoenix_guard_recovery',
                'backup_required': True,
                'rollback_support': True,
                'risk_level': 'medium'
            }
        }
        
        output_file = f"universal_config_{hardware_id}.json"
        with open(output_file, 'w') as f:
            json.dump(universal_config, f, indent=2)
        
        print(f"✅ Universal config generated: {output_file}")
        return output_file

def main():
    print("🔥 PHOENIXGUARD UNIVERSAL HARDWARE SCRAPER")
    print("=" * 70)
    print("MISSION: Map ALL hardware configurations and expose hidden features!")
    print("=" * 70)
    print()
    
    scraper = UniversalHardwareScraper()
    
    print("🎯 SELECT ACTION:")
    print("1. Discover current hardware and create profile")
    print("2. List supported hardware") 
    print("3. Generate config for specific hardware")
    print("4. Submit profile to database (future)")
    
    choice = input("\\nEnter choice (1-4): ").strip()
    
    if choice == '1':
        # Create and save profile for current hardware
        profile = scraper.create_hardware_profile()
        scraper.save_profile_locally(profile)
        
        print(f"\\n🎉 SUCCESS! Hardware profile created:")
        print(f"   Hardware: {profile.manufacturer} {profile.model}")
        print(f"   UEFI Variables: {profile.uefi_variables.get('total_count', 0)}")
        print(f"   Hidden Features: {len(profile.hidden_features)}")
        print(f"   Profile ID: {profile.hardware_id}")
        
    elif choice == '2':
        scraper.list_supported_hardware()
        
    elif choice == '3':
        hardware_id = input("Enter hardware ID: ").strip()
        config_file = scraper.generate_universal_config_for_hardware(hardware_id)
        
    elif choice == '4':
        print("📡 Database submission not yet implemented")
        print("🔮 Future: Crowdsourced hardware configuration database")
        
    else:
        print("❌ Invalid choice")
        
    print("\\n🚀 PhoenixGuard: Liberating firmware, one machine at a time!")

if __name__ == "__main__":
    main()
