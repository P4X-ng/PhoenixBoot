#!/usr/bin/env python3
"""
Test script for baseline loading functionality
"""
import sys
import json
from pathlib import Path

# Add scripts directory to path to import the hardware recovery module
sys.path.append('scripts')
from hardware_firmware_recovery import HardwareFirmwareRecovery

def test_baseline_loading():
    """Test the baseline loading functionality"""
    print("🔍 Testing baseline loading functionality...")
    
    # Create minimal recovery instance just for testing baseline loading
    recovery = HardwareFirmwareRecovery('/dev/null', verify_only=True)
    
    # Test baseline loading
    print("\n📚 Loading baseline database...")
    baselines = recovery.load_firmware_baselines()
    
    if baselines:
        print(f"✅ Loaded {len(baselines)} baseline entries:")
        for key, data in baselines.items():
            print(f"   - {key}")
            if isinstance(data, dict) and 'hashes' in data:
                print(f"     Hashes: {len(data['hashes'])}")
                if 'metadata' in data:
                    metadata = data['metadata']
                    print(f"     Model: {metadata.get('hardware_model', 'Unknown')}")
                    print(f"     BIOS: {metadata.get('bios_version', 'Unknown')}")
            print()
    else:
        print("❌ No baselines loaded!")
        return False
        
    # Test verification against a known hash
    print("🔍 Testing baseline verification...")
    
    # Get the first baseline entry to test with
    if baselines:
        first_key = list(baselines.keys())[0]
        first_baseline = baselines[first_key]
        
        if isinstance(first_baseline, dict) and 'hashes' in first_baseline:
            test_hash = first_baseline['hashes'][0]  # Use first hash (SHA256)
            print(f"Testing with hash: {test_hash}")
            
            # Create mock hardware info
            hardware_info = {
                'manufacturer': 'ASUS',
                'product': 'ROG G615LP'
            }
            
            verification_result = recovery.verify_against_baseline(test_hash, hardware_info)
            print(f"Verification result: {verification_result}")
            
            if verification_result.get('verified'):
                print("✅ Baseline verification working correctly!")
                return True
            else:
                print("❌ Baseline verification failed")
                return False
    
    return False

if __name__ == '__main__':
    success = test_baseline_loading()
    sys.exit(0 if success else 1)
