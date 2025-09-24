#!/usr/bin/env python3
"""
PhoenixGuard UEFI Variable Discovery Engine
==========================================

This tool discovers ALL UEFI variables used by your specific hardware,
categorizes them, and builds a complete configuration profile.

The goal: 100% hardware support by reverse engineering every variable!
"""

import os
import json
import struct
import re
from pathlib import Path
from collections import defaultdict
from datetime import datetime
from typing import Dict, List, Tuple, Optional

class UEFIVariableDiscovery:
    def __init__(self):
        self.efi_vars_path = Path("/sys/firmware/efi/efivars")
        self.variables = {}
        self.categories = defaultdict(list)
        self.hardware_profile = {
            "timestamp": datetime.now().isoformat(),
            "hardware_id": self._get_hardware_id(),
            "variables": {},
            "categories": {},
            "vendor_specific": {},
            "critical_config": {}
        }
    
    def _get_hardware_id(self) -> str:
        """Get unique hardware identifier"""
        try:
            with open("/sys/class/dmi/id/product_name") as f:
                product = f.read().strip()
            with open("/sys/class/dmi/id/board_name") as f:
                board = f.read().strip()
            return f"{product}_{board}"
        except:
            return "unknown_hardware"
    
    def discover_all_variables(self) -> Dict:
        """Discover and categorize all EFI variables"""
        print("🔍 Discovering ALL UEFI variables...")
        
        if not self.efi_vars_path.exists():
            print("❌ EFI variables not accessible - need UEFI system")
            return {}
        
        var_files = list(self.efi_vars_path.glob("*"))
        print(f"📊 Found {len(var_files)} EFI variables")
        
        for var_file in var_files:
            try:
                var_info = self._parse_variable(var_file)
                if var_info:
                    self.variables[var_info['name']] = var_info
                    self._categorize_variable(var_info)
            except Exception as e:
                print(f"⚠️  Failed to parse {var_file.name}: {e}")
        
        return self.variables
    
    def _parse_variable(self, var_file: Path) -> Optional[Dict]:
        """Parse individual EFI variable"""
        try:
            # Parse filename: VariableName-GUID
            filename = var_file.name
            if '-' not in filename:
                return None
            
            parts = filename.rsplit('-', 1)
            if len(parts) != 2:
                return None
                
            var_name, guid = parts
            
            # Try to read variable data (many require root)
            var_data = None
            var_size = 0
            try:
                var_data = var_file.read_bytes()
                var_size = len(var_data)
            except PermissionError:
                # Try to get size from stat
                try:
                    var_size = var_file.stat().st_size
                except:
                    pass
            
            return {
                'name': var_name,
                'guid': guid,
                'size': var_size,
                'data': var_data,
                'path': str(var_file),
                'readable': var_data is not None
            }
        except Exception as e:
            return None
    
    def _categorize_variable(self, var_info: Dict):
        """Categorize variables by function"""
        name = var_info['name'].lower()
        guid = var_info['guid'].lower()
        
        # Boot configuration
        if re.match(r'boot\d{4}', name) or name in ['bootorder', 'bootcurrent', 'bootnext']:
            self.categories['boot_config'].append(var_info)
        
        # Security variables  
        elif name in ['pk', 'kek', 'db', 'dbx', 'secureboot', 'setupmode']:
            self.categories['security'].append(var_info)
        
        # ASUS-specific
        elif 'asus' in name.lower():
            self.categories['asus_specific'].append(var_info)
            
        # Setup/Configuration
        elif 'setup' in name or 'config' in name:
            self.categories['setup_config'].append(var_info)
            
        # Memory/Performance
        elif any(keyword in name for keyword in ['memory', 'overclock', 'perf', 'cpu']):
            self.categories['performance'].append(var_info)
            
        # Thermal/Power
        elif any(keyword in name for keyword in ['thermal', 'power', 'fan', 'temp']):
            self.categories['thermal_power'].append(var_info)
            
        # Hardware-specific
        elif any(keyword in name for keyword in ['pci', 'usb', 'sata', 'nvme']):
            self.categories['hardware_config'].append(var_info)
            
        # Vendor-specific GUIDs
        elif self._is_vendor_guid(guid):
            self.categories['vendor_specific'].append(var_info)
            
        # Everything else
        else:
            self.categories['unknown'].append(var_info)
    
    def _is_vendor_guid(self, guid: str) -> bool:
        """Check if GUID is vendor-specific (not standard UEFI)"""
        # Standard UEFI GUIDs
        standard_guids = [
            '8be4df61-93ca-11d2-aa0d-00e098032b8c',  # Global Variable
            'd719b2cb-3d3a-4596-a3bc-dad00e67656f',  # Security Database
            '77fa9abd-0359-4d32-bd60-28f4e78f784b',  # Windows
        ]
        return guid not in standard_guids
    
    def analyze_asus_variables(self):
        """Deep analysis of ASUS-specific variables"""
        print("\n🎯 ANALYZING ASUS-SPECIFIC VARIABLES:")
        print("=" * 50)
        
        asus_vars = self.categories.get('asus_specific', [])
        if not asus_vars:
            print("No ASUS variables found")
            return
            
        for var in asus_vars:
            print(f"\n📱 {var['name']}")
            print(f"   GUID: {var['guid']}")
            print(f"   Size: {var['size']} bytes")
            
            # Try to guess purpose from name
            purpose = self._guess_variable_purpose(var['name'])
            if purpose:
                print(f"   Likely Purpose: {purpose}")
                
            # If we have data, analyze it
            if var['readable'] and var['data']:
                analysis = self._analyze_variable_data(var['data'])
                if analysis:
                    print(f"   Data Analysis: {analysis}")
    
    def _guess_variable_purpose(self, var_name: str) -> str:
        """Guess variable purpose from name"""
        name_lower = var_name.lower()
        
        if 'animation' in name_lower:
            return "BIOS UI animations/graphics"
        elif 'camera' in name_lower:
            return "Camera/webcam configuration"
        elif 'gnvs' in name_lower:
            return "Global NVS (ACPI variables)"
        elif 'version' in name_lower:
            return "Version information"
        elif 'manufacture' in name_lower:
            return "Manufacturing/OEM data"
        elif 'retrain' in name_lower:
            return "Memory training configuration"
        else:
            return f"Unknown - analysis needed"
    
    def _analyze_variable_data(self, data: bytes) -> str:
        """Basic analysis of variable data"""
        if len(data) < 4:
            return f"Small data: {data.hex()}"
        
        # Check for common patterns
        if data[:4] == b'\x00\x00\x00\x00':
            return "Likely disabled/zero configuration"
        elif data[:4] == b'\x01\x00\x00\x00':
            return "Likely enabled/boolean true"
        elif len(data) > 100:
            return "Large configuration blob - complex settings"
        else:
            return f"Data pattern: {data[:8].hex()}..."
    
    def build_hardware_profile(self):
        """Build complete hardware configuration profile"""
        print("\n🚀 BUILDING COMPLETE G615LP HARDWARE PROFILE:")
        print("=" * 60)
        
        self.hardware_profile['total_variables'] = len(self.variables)
        self.hardware_profile['categories'] = {
            cat: len(vars_list) for cat, vars_list in self.categories.items()
        }
        
        # Extract critical configuration variables
        critical_vars = []
        
        # Boot configuration
        for var in self.categories.get('boot_config', []):
            critical_vars.append({
                'name': var['name'],
                'purpose': 'Boot order and configuration',
                'critical_level': 'HIGH'
            })
        
        # ASUS-specific hardware config
        for var in self.categories.get('asus_specific', []):
            critical_vars.append({
                'name': var['name'],
                'purpose': self._guess_variable_purpose(var['name']),
                'critical_level': 'MEDIUM'
            })
        
        # Performance variables
        for var in self.categories.get('performance', []):
            critical_vars.append({
                'name': var['name'],
                'purpose': 'CPU/Memory performance settings',
                'critical_level': 'MEDIUM'
            })
        
        self.hardware_profile['critical_config'] = critical_vars
        
        return self.hardware_profile
    
    def generate_universal_config_template(self):
        """Generate template for universal BIOS config"""
        print("\n🎯 GENERATING UNIVERSAL CONFIG TEMPLATE:")
        print("=" * 50)
        
        template = {
            "hardware_id": self.hardware_profile['hardware_id'],
            "config_version": "1.0",
            "generated": datetime.now().isoformat(),
            
            # Boot configuration
            "boot_config": {
                "default_boot_order": ["Boot0000", "Boot0001", "Boot0002"],
                "boot_timeout": 5,
                "secure_boot": True
            },
            
            # Hardware-specific ASUS variables
            "asus_specific": {},
            
            # Performance settings  
            "performance_config": {
                "memory_training": "auto",
                "cpu_overclocking": "disabled",
                "power_profile": "balanced"
            },
            
            # All discovered variables for reference
            "all_variables": list(self.variables.keys())
        }
        
        # Add ASUS-specific variables to template
        for var in self.categories.get('asus_specific', []):
            template['asus_specific'][var['name']] = {
                'guid': var['guid'],
                'size': var['size'],
                'purpose': self._guess_variable_purpose(var['name']),
                'default_value': 'NEEDS_DISCOVERY'
            }
        
        return template
    
    def save_discovery_results(self, output_path: str = "g615lp_uefi_profile.json"):
        """Save complete discovery results"""
        profile = self.build_hardware_profile()
        template = self.generate_universal_config_template()
        
        results = {
            'hardware_profile': profile,
            'universal_config_template': template,
            'raw_variables': {name: {
                'guid': var['guid'],
                'size': var['size'],
                'readable': var['readable']
            } for name, var in self.variables.items()}
        }
        
        with open(output_path, 'w') as f:
            json.dump(results, f, indent=2)
        
        print(f"\n✅ Complete discovery results saved to: {output_path}")
        return output_path

def main():
    print("🔥 PHOENIXGUARD UEFI VARIABLE DISCOVERY ENGINE")
    print("=" * 60)
    print("Goal: 100% hardware support by discovering EVERY variable!")
    print()
    
    discovery = UEFIVariableDiscovery()
    
    # Step 1: Discover all variables
    variables = discovery.discover_all_variables()
    
    # Step 2: Analyze ASUS-specific variables
    discovery.analyze_asus_variables()
    
    # Step 3: Build complete profile  
    profile = discovery.build_hardware_profile()
    
    # Step 4: Show summary
    print(f"\n🎯 DISCOVERY SUMMARY FOR {profile['hardware_id']}:")
    print("=" * 60)
    print(f"📊 Total Variables: {profile['total_variables']}")
    print(f"📱 ASUS Variables: {profile['categories'].get('asus_specific', 0)}")
    print(f"🔧 Setup Variables: {profile['categories'].get('setup_config', 0)}")  
    print(f"⚡ Performance Variables: {profile['categories'].get('performance', 0)}")
    print(f"🌡️ Thermal Variables: {profile['categories'].get('thermal_power', 0)}")
    
    # Step 5: Save results
    output_file = discovery.save_discovery_results()
    
    print(f"\n🚀 NEXT STEPS:")
    print("=" * 30)
    print("1. Analyze the generated profile")
    print("2. Test variable modifications safely")  
    print("3. Build universal config for G615LP")
    print("4. Contribute to PhoenixGuard universal BIOS!")
    
    return output_file

if __name__ == "__main__":
    main()
