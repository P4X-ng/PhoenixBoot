#!/usr/bin/env python3
"""
PhoenixGuard Advanced UEFI Variable Value Analyzer
==================================================

This tool reads the actual values of ASUS-specific variables and attempts
to decode their meaning for universal BIOS configuration.
"""

import os
import json
import struct
from pathlib import Path
from typing import Dict, List, Optional, Union

class UEFIVariableAnalyzer:
    def __init__(self):
        self.efi_vars_path = Path("/sys/firmware/efi/efivars")
        self.asus_guid = "85ba66797a3e"  # Main ASUS GUID
        self.analysis_results = {}
        
    def read_variable_raw(self, var_name: str, guid: str) -> Optional[bytes]:
        """Read raw variable data"""
        var_file = self.efi_vars_path / f"{var_name}-{guid}"
        try:
            # First 4 bytes are attributes, rest is data
            raw_data = var_file.read_bytes()
            if len(raw_data) < 4:
                return None
            return raw_data[4:]  # Skip EFI variable attributes
        except Exception as e:
            print(f"⚠️  Cannot read {var_name}: {e}")
            return None
    
    def analyze_asus_variables(self):
        """Analyze all ASUS-specific variables in detail"""
        print("🎯 DEEP ANALYSIS OF ASUS VARIABLES")
        print("=" * 50)
        
        # Key ASUS variables to analyze
        asus_variables = [
            ("AsusGnvsVariable", "d763220a-8214-4f10-8658-de40ef1769e1"),
            ("MyasusAutoInstall", f"607005d5-3f75-4b2e-98f0-{self.asus_guid}"),
            ("AsusGpnvVersion", f"607005d5-3f75-4b2e-98f0-{self.asus_guid}"),
            ("AsusAnimationSetupConfig", f"607005d5-3f75-4b2e-98f0-{self.asus_guid}"),
            ("AsusCameraHashValueUpdate", "0e0bd45b-349a-4e49-a402-d4b8819c7d10"),
            ("PreviousAsusTouchPadDevice", f"607005d5-3f75-4b2e-98f0-{self.asus_guid}"),
            ("PreviousAsusCameraDevice", f"607005d5-3f75-4b2e-98f0-{self.asus_guid}"),
            ("AsusManufactureVersion", f"607005d5-3f75-4b2e-98f0-{self.asus_guid}"),
            ("ArmouryCrateStaticField", f"607005d5-3f75-4b2e-98f0-{self.asus_guid}"),
            ("CloudRecoverySupport", f"607005d5-3f75-4b2e-98f0-{self.asus_guid}"),
        ]
        
        for var_name, full_guid in asus_variables:
            print(f"\n🔍 Analyzing: {var_name}")
            print("-" * 40)
            
            # Extract just the GUID part
            guid = full_guid.split('-')[-1] if '-' in full_guid else full_guid
            
            data = self.read_variable_raw(var_name, full_guid)
            if data:
                analysis = self.decode_variable_data(var_name, data)
                self.analysis_results[var_name] = analysis
                self.print_analysis(var_name, data, analysis)
            else:
                print(f"❌ Could not read variable data")
    
    def decode_variable_data(self, var_name: str, data: bytes) -> Dict:
        """Decode variable data based on variable name and data patterns"""
        analysis = {
            "size": len(data),
            "hex_data": data.hex(),
            "interpretation": "unknown",
            "possible_values": [],
            "structure": None
        }
        
        # Version variables
        if "version" in var_name.lower():
            analysis["interpretation"] = "version_info"
            if len(data) >= 2:
                analysis["possible_values"] = [
                    f"Version: {data[0]}.{data[1]}" if len(data) >= 2 else "Invalid"
                ]
        
        # Animation/UI variables
        elif "animation" in var_name.lower():
            analysis["interpretation"] = "animation_config"
            if len(data) >= 1:
                enabled = data[0] != 0
                analysis["possible_values"] = [f"Animations: {'Enabled' if enabled else 'Disabled'}"]
        
        # Camera variables
        elif "camera" in var_name.lower():
            analysis["interpretation"] = "camera_security"
            if len(data) == 32:  # Hash value
                analysis["possible_values"] = [f"Camera Hash: {data.hex()[:16]}..."]
            elif len(data) < 10:
                analysis["possible_values"] = [f"Camera Device ID: {data.hex()}"]
        
        # Touchpad variables
        elif "touchpad" in var_name.lower():
            analysis["interpretation"] = "touchpad_device"
            analysis["possible_values"] = [f"Touchpad ID: {data.hex()}"]
        
        # MyASUS variables
        elif "myasus" in var_name.lower():
            analysis["interpretation"] = "myasus_integration"
            if len(data) >= 1:
                enabled = data[0] != 0
                analysis["possible_values"] = [f"MyASUS Auto Install: {'Enabled' if enabled else 'Disabled'}"]
        
        # Armoury Crate
        elif "armoury" in var_name.lower() or "crate" in var_name.lower():
            analysis["interpretation"] = "armoury_crate_config"
            analysis["possible_values"] = [f"Config Size: {len(data)} bytes", "Complex configuration blob"]
        
        # Cloud Recovery
        elif "cloud" in var_name.lower():
            analysis["interpretation"] = "cloud_recovery"
            if len(data) >= 1:
                enabled = data[0] != 0
                analysis["possible_values"] = [f"Cloud Recovery: {'Supported' if enabled else 'Not Supported'}"]
        
        # Manufacturing data
        elif "manufacture" in var_name.lower():
            analysis["interpretation"] = "manufacturing_data"
            analysis["possible_values"] = [f"Manufacture Version: {data.hex()}"]
        
        # GNVS Variables (ACPI Global NVS)
        elif "gnvs" in var_name.lower():
            analysis["interpretation"] = "acpi_global_nvs"
            if len(data) >= 4:
                # Try to interpret as structured data
                values = struct.unpack('<L', data[:4])[0] if len(data) >= 4 else 0
                analysis["possible_values"] = [f"ACPI Value: 0x{values:08x}"]
        
        # Try to detect common patterns
        self.detect_data_patterns(data, analysis)
        
        return analysis
    
    def detect_data_patterns(self, data: bytes, analysis: Dict):
        """Detect common data patterns"""
        patterns = []
        
        if len(data) == 1:
            if data[0] == 0:
                patterns.append("Disabled/False/Zero")
            elif data[0] == 1:
                patterns.append("Enabled/True/One")
            else:
                patterns.append(f"Single byte value: {data[0]}")
        
        elif len(data) == 2:
            value = struct.unpack('<H', data)[0]
            patterns.append(f"16-bit value: {value} (0x{value:04x})")
        
        elif len(data) == 4:
            value = struct.unpack('<L', data)[0]
            patterns.append(f"32-bit value: {value} (0x{value:08x})")
        
        elif len(data) == 8:
            value = struct.unpack('<Q', data)[0]
            patterns.append(f"64-bit value: {value} (0x{value:016x})")
        
        # Check for text/strings
        try:
            if all(32 <= b <= 126 for b in data if b != 0):  # Printable ASCII
                text = data.decode('ascii').rstrip('\x00')
                if text:
                    patterns.append(f"ASCII String: '{text}'")
        except:
            pass
        
        # Check for UTF-16 strings
        try:
            if len(data) % 2 == 0 and len(data) > 2:
                text = data.decode('utf-16le').rstrip('\x00')
                if text and all(ord(c) < 256 for c in text):
                    patterns.append(f"UTF-16 String: '{text}'")
        except:
            pass
        
        if patterns:
            analysis["possible_values"].extend(patterns)
    
    def print_analysis(self, var_name: str, data: bytes, analysis: Dict):
        """Print variable analysis in a readable format"""
        print(f"📊 Size: {analysis['size']} bytes")
        print(f"🔧 Type: {analysis['interpretation']}")
        print(f"📱 Raw: {analysis['hex_data']}")
        
        if analysis['possible_values']:
            print("🎯 Decoded Values:")
            for value in analysis['possible_values']:
                print(f"   • {value}")
    
    def generate_config_recommendations(self):
        """Generate configuration recommendations based on analysis"""
        print("\n🚀 UNIVERSAL BIOS CONFIG RECOMMENDATIONS")
        print("=" * 60)
        
        recommendations = {
            "boot_optimization": [],
            "hardware_features": [],
            "security_settings": [],
            "performance_tuning": [],
        }
        
        for var_name, analysis in self.analysis_results.items():
            if "animation" in var_name.lower():
                recommendations["boot_optimization"].append({
                    "variable": var_name,
                    "recommendation": "Disable BIOS animations for faster boot",
                    "current_state": "unknown",
                    "optimal_value": "0x00"
                })
            
            elif "camera" in var_name.lower():
                recommendations["security_settings"].append({
                    "variable": var_name,
                    "recommendation": "Maintain camera security hash for privacy",
                    "current_state": "hash_protected",
                    "optimal_value": "preserve_current"
                })
            
            elif "myasus" in var_name.lower():
                recommendations["performance_tuning"].append({
                    "variable": var_name,
                    "recommendation": "Disable MyASUS auto-install for cleaner boot",
                    "current_state": "unknown",
                    "optimal_value": "0x00"
                })
        
        for category, recs in recommendations.items():
            if recs:
                print(f"\n🎯 {category.replace('_', ' ').title()}:")
                for rec in recs:
                    print(f"   • {rec['variable']}: {rec['recommendation']}")
                    print(f"     Optimal: {rec['optimal_value']}")
    
    def save_analysis_results(self, output_file: str = "g615lp_variable_analysis.json"):
        """Save detailed analysis results"""
        results = {
            "hardware_id": "ROG Strix G16 G615LP",
            "analysis_timestamp": "2025-01-23T02:49:00Z",
            "variable_analysis": self.analysis_results,
            "recommendations": "See generate_config_recommendations output"
        }
        
        with open(output_file, 'w') as f:
            json.dump(results, f, indent=2)
        
        print(f"\n✅ Detailed analysis saved to: {output_file}")
        return output_file

def main():
    print("🔥 PHOENIXGUARD ADVANCED UEFI VARIABLE ANALYZER")
    print("=" * 60)
    print("Reading and decoding ASUS variable VALUES...")
    print()
    
    analyzer = UEFIVariableAnalyzer()
    
    # Perform deep analysis
    analyzer.analyze_asus_variables()
    
    # Generate recommendations
    analyzer.generate_config_recommendations()
    
    # Save results
    analyzer.save_analysis_results()
    
    print(f"\n🎯 ANALYSIS COMPLETE!")
    print("This data is GOLD for building universal BIOS support!")
    print("We now know how to configure ROG hardware properly! 🚀")

if __name__ == "__main__":
    main()
