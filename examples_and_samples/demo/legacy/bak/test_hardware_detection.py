#!/usr/bin/env python3
"""
Test script for hardware detection and tool verification
"""
import sys
import subprocess
import os
from pathlib import Path

# Add scripts directory to path
sys.path.append('scripts')
from hardware_firmware_recovery import HardwareFirmwareRecovery

def test_hardware_detection():
    """Test the hardware detection functionality"""
    print("🔍 Testing hardware detection...")
    
    recovery = HardwareFirmwareRecovery('/dev/null', verify_only=True)
    
    # Test hardware detection
    recovery.detect_hardware_info()
    hardware_info = recovery.results.get('hardware_detected', {})
    print(f"Hardware detected: {hardware_info}")
    
    return hardware_info

def test_tool_verification():
    """Test tool detection and availability"""
    print("\n🛠️  Testing tool verification...")
    
    recovery = HardwareFirmwareRecovery('/dev/null', verify_only=True)
    
    # Check each tool in the tools dictionary
    all_tools_available = True
    for tool_name, tool_path in recovery.tools.items():
        if Path(tool_path).exists():
            print(f"✅ {tool_name}: {tool_path}")
        else:
            print(f"❌ {tool_name}: {tool_path} (not found)")
            all_tools_available = False
            
    return all_tools_available

def test_flashrom_access():
    """Test flashrom access and permissions"""
    print("\n🔧 Testing flashrom access...")
    
    try:
        # Test flashrom probe (default operation when no operation is specified)
        result = subprocess.run(
            ['flashrom', '-p', 'internal'],
            capture_output=True, text=True, timeout=30
        )
        
        print(f"Flashrom return code: {result.returncode}")
        if result.stdout:
            print(f"Stdout: {result.stdout[:200]}...")
        if result.stderr:
            print(f"Stderr: {result.stderr[:200]}...")
        
        # Check for expected patterns in output
        # Return code 1 with permission error is expected for non-root users
        # Return code 1 with lockdown restrictions is expected in secure environments
        output_combined = result.stdout + result.stderr
        if result.returncode == 1 and "I/O privileges" in output_combined:
            if "root" in output_combined and os.getuid() != 0:
                print("✅ Flashrom available but needs root privileges (expected)")
            else:
                print("✅ Flashrom available but blocked by kernel lockdown (expected in secure boot)")
                print("   Use 'sudo ./scripts/flashrom-alternatives.sh' for secure alternatives")
            return True
        elif result.returncode == 0:
            print("✅ Flashrom working with current privileges")
            return True
        else:
            print("❌ Unexpected flashrom error")
            return False
            
    except Exception as e:
        print(f"❌ Flashrom test failed: {e}")
        return False

def test_chipsec_access():
    """Test chipsec module availability"""
    print("\n💻 Testing chipsec access...")
    
    try:
        # Try to import chipsec modules
        import chipsec
        print(f"✅ Chipsec version: {chipsec.__version__ if hasattr(chipsec, '__version__') else 'unknown'}")
        
        from chipsec.hal import hal_base
        print("✅ Chipsec HAL available")
        
        return True
        
    except ImportError as e:
        print(f"❌ Chipsec not available: {e}")
        return False
    except Exception as e:
        print(f"❌ Chipsec access failed: {e}")
        return False

if __name__ == '__main__':
    print("🧪 Hardware Detection and Tool Verification Test")
    print("=" * 50)
    
    results = {}
    
    # Test hardware detection
    hardware_info = test_hardware_detection()
    results['hardware_detection'] = bool(hardware_info)
    
    # Test tool verification 
    tools_available = test_tool_verification()
    results['tools_available'] = tools_available
    
    # Test flashrom access
    flashrom_works = test_flashrom_access()
    results['flashrom_access'] = flashrom_works
    
    # Test chipsec access
    chipsec_works = test_chipsec_access()
    results['chipsec_access'] = chipsec_works
    
    print("\n📊 Test Results Summary:")
    print("=" * 30)
    for test, passed in results.items():
        status = "✅ PASS" if passed else "❌ FAIL"
        print(f"{test}: {status}")
        
    overall_success = all(results.values())
    print(f"\nOverall: {'✅ ALL TESTS PASSED' if overall_success else '❌ SOME TESTS FAILED'}")
    
    sys.exit(0 if overall_success else 1)
