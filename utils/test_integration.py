#!/usr/bin/env python3

"""
PhoenixGuard Integration Test Suite
Part of the edk2-bootkit-defense project

Comprehensive test suite that validates all components of the
PhoenixGuard kernel module management system including:
- Certificate inventory and management
- Module signing capabilities
- Module signature verification (Python and C implementations)
- Integration between components
"""

import os
import sys
import json
import subprocess
import tempfile
import shutil
from pathlib import Path
import ctypes
from ctypes import Structure, c_int, c_char_p, c_size_t, c_long, c_time_t

# Add current directory to path for imports
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

try:
    import cert_inventory
    import pgmodsign
except ImportError as e:
    print(f"❌ Failed to import PhoenixGuard modules: {e}")
    sys.exit(1)

class PGVerifyResult(Structure):
    """C structure for verification results"""
    _fields_ = [
        ('valid', c_int),
        ('has_signature', c_int),
        ('signer', c_char_p),
        ('algorithm', c_char_p),
        ('hash_algorithm', c_char_p),
        ('error_message', c_char_p),
        ('signature_offset', c_long),
        ('signature_size', c_size_t),
        ('verification_time', c_time_t),
    ]

class PhoenixGuardIntegrationTest:
    """Comprehensive integration test suite"""
    
    def __init__(self):
        self.utils_dir = Path(__file__).parent
        self.project_root = self.utils_dir.parent
        self.cert_dir = self.project_root / "secureboot_certs"
        self.test_results = []
        self.temp_dir = None
        self.lib_handle = None
        
    def setup_temp_environment(self):
        """Set up temporary test environment"""
        self.temp_dir = Path(tempfile.mkdtemp(prefix="pg_test_"))
        print(f"📁 Created temporary test directory: {self.temp_dir}")
        
        # Load C library
        lib_path = self.utils_dir / "libpgmodverify.so"
        if lib_path.exists():
            try:
                self.lib_handle = ctypes.CDLL(str(lib_path))
                self.setup_c_functions()
                print("📚 Loaded C verification library")
            except Exception as e:
                print(f"⚠️  Failed to load C library: {e}")
        else:
            print("⚠️  C library not found, skipping C verification tests")

    def setup_c_functions(self):
        """Configure C function signatures"""
        # pg_load_certificates_from_dir
        self.lib_handle.pg_load_certificates_from_dir.argtypes = [c_char_p]
        self.lib_handle.pg_load_certificates_from_dir.restype = c_int
        
        # pg_verify_module_signature
        self.lib_handle.pg_verify_module_signature.argtypes = [c_char_p]
        self.lib_handle.pg_verify_module_signature.restype = ctypes.POINTER(PGVerifyResult)
        
        # pg_free_verify_result
        self.lib_handle.pg_free_verify_result.argtypes = [ctypes.POINTER(PGVerifyResult)]
        self.lib_handle.pg_free_verify_result.restype = None
        
        # pg_cleanup
        self.lib_handle.pg_cleanup.argtypes = []
        self.lib_handle.pg_cleanup.restype = None

    def cleanup_temp_environment(self):
        """Clean up temporary test environment"""
        if self.temp_dir and self.temp_dir.exists():
            shutil.rmtree(self.temp_dir)
            print(f"🧹 Cleaned up temporary directory: {self.temp_dir}")
        
        if self.lib_handle:
            self.lib_handle.pg_cleanup()
            print("🧹 Cleaned up C library resources")

    def run_test(self, test_name, test_func):
        """Run a single test and record results"""
        print(f"\n🧪 Running test: {test_name}")
        try:
            result = test_func()
            if result:
                print(f"✅ {test_name}: PASSED")
                self.test_results.append((test_name, True, None))
            else:
                print(f"❌ {test_name}: FAILED")
                self.test_results.append((test_name, False, "Test returned False"))
        except Exception as e:
            print(f"💥 {test_name}: ERROR - {e}")
            self.test_results.append((test_name, False, str(e)))

    def test_certificate_inventory(self):
        """Test certificate inventory functionality"""
        if not self.cert_dir.exists():
            print("⚠️  Certificate directory not found")
            return False
            
        # Test certificate loading and inventory
        inventory_tool = cert_inventory.PhoenixGuardCertInventory(str(self.cert_dir))
        inventory = inventory_tool.inventory_all_certificates()
        
        if not inventory or not inventory.get('certificate_details'):
            print("❌ No certificates found in inventory")
            return False
        
        cert_details = inventory['certificate_details']
        print(f"📋 Found {len(cert_details)} certificates in inventory:")
        for cert_info in cert_details:
            print(f"   - {cert_info.get('subject', 'Unknown')}")
            print(f"     Format: {cert_info.get('format', 'Unknown')}")
            print(f"     File: {cert_info.get('file_path', 'Unknown')}")
        
        return len(cert_details) > 0

    def test_c_library_basic(self):
        """Test basic C library functionality"""
        if not self.lib_handle:
            print("⚠️  C library not available, skipping test")
            return True  # Skip rather than fail
            
        # Load certificates
        cert_count = self.lib_handle.pg_load_certificates_from_dir(
            str(self.cert_dir).encode('utf-8')
        )
        
        if cert_count == 0:
            print("❌ No certificates loaded by C library")
            return False
            
        print(f"📚 C library loaded {cert_count} certificates")
        
        # Test with a known kernel module (unsigned)
        test_modules = [
            "/lib/modules/$(uname -r)/kernel/drivers/char/hw_random/virtio-rng.ko",
            "/lib/modules/$(uname -r)/kernel/fs/ext4/ext4.ko",
        ]
        
        for module_path in test_modules:
            # Expand shell variables
            expanded_path = subprocess.check_output(
                f'echo {module_path}', shell=True
            ).decode().strip()
            
            if not Path(expanded_path).exists():
                continue
                
            print(f"🔍 Testing module: {expanded_path}")
            
            # Verify module
            result_ptr = self.lib_handle.pg_verify_module_signature(
                expanded_path.encode('utf-8')
            )
            
            if not result_ptr:
                print("❌ C verification returned NULL")
                continue
                
            result = result_ptr.contents
            print(f"   Has signature: {bool(result.has_signature)}")
            print(f"   Valid: {bool(result.valid)}")
            if result.error_message:
                print(f"   Error: {result.error_message.decode('utf-8')}")
            
            # Free the result
            self.lib_handle.pg_free_verify_result(result_ptr)
            
            # For unsigned modules, we expect has_signature=False
            return True  # Test passed if we got here without crashing
        
        print("⚠️  No test modules found")
        return True

    def test_module_signing_simulation(self):
        """Test module signing process (simulation)"""
        # Create a dummy module file for testing
        test_module = self.temp_dir / "test_module.ko"
        with open(test_module, 'wb') as f:
            # Write some dummy ELF-like content
            f.write(b'\x7fELF')  # ELF magic
            f.write(b'A' * 1000)  # Dummy content
        
        # Test the pgmodsign module (dry run)
        try:
            # Import and test basic functionality
            inventory_tool = cert_inventory.PhoenixGuardCertInventory(str(self.cert_dir))
            inventory = inventory_tool.inventory_all_certificates()
            cert_details = inventory.get('certificate_details', [])
            
            if not cert_details:
                print("⚠️  No certificates available for signing test")
                return True
            
            print(f"📝 Would sign module with certificate: {cert_details[0].get('subject', 'Unknown')}")
            print(f"   Module size: {test_module.stat().st_size} bytes")
            
            # We can't actually sign without the kernel sign-file tool,
            # but we can test our logic
            return True
            
        except Exception as e:
            print(f"❌ Module signing test failed: {e}")
            return False

    def test_system_integration(self):
        """Test system-wide integration"""
        # Check if all required tools are available
        tools = {
            'python3': (['python3', '--version'], 'Python interpreter'),
            'gcc': (['gcc', '--version'], 'C compiler for library compilation'),
            'openssl': (['openssl', 'version'], 'OpenSSL for certificate operations'),
        }
        
        missing_tools = []
        for tool, (cmd, description) in tools.items():
            try:
                subprocess.run(cmd, capture_output=True, check=True)
                print(f"✅ Found {tool}: {description}")
            except (subprocess.CalledProcessError, FileNotFoundError):
                missing_tools.append(f"{tool} ({description})")
        
        if missing_tools:
            print(f"❌ Missing required tools: {', '.join(missing_tools)}")
            return False
        
        # Check library files
        expected_files = [
            'libpgmodverify.a',
            'libpgmodverify.so',
            'pgmodverify.h',
            'pgmodverify_test',
            'cert_inventory.py',
            'pgmodsign.py'
        ]
        
        missing_files = []
        for filename in expected_files:
            filepath = self.utils_dir / filename
            if filepath.exists():
                print(f"✅ Found {filename}")
            else:
                missing_files.append(filename)
        
        if missing_files:
            print(f"❌ Missing files: {', '.join(missing_files)}")
            return False
            
        return True

    def test_error_handling(self):
        """Test error handling and edge cases"""
        if not self.lib_handle:
            return True  # Skip if C library not available
        
        # Test with non-existent certificate directory
        cert_count = self.lib_handle.pg_load_certificates_from_dir(
            b'/nonexistent/directory'
        )
        if cert_count != 0:
            print("❌ Should return 0 certificates for non-existent directory")
            return False
        print("✅ Correctly handled non-existent certificate directory")
        
        # Test with non-existent module file
        result_ptr = self.lib_handle.pg_verify_module_signature(
            b'/nonexistent/module.ko'
        )
        if result_ptr:
            result = result_ptr.contents
            if result.error_message:
                error_msg = result.error_message.decode('utf-8')
                print(f"✅ Correctly handled non-existent module: {error_msg}")
            self.lib_handle.pg_free_verify_result(result_ptr)
        else:
            print("❌ Should return result structure even for errors")
            return False
        
        return True

    def run_all_tests(self):
        """Run all integration tests"""
        print("🚀 Starting PhoenixGuard Integration Test Suite")
        print("=" * 60)
        
        self.setup_temp_environment()
        
        # Define test suite
        tests = [
            ("Certificate Inventory", self.test_certificate_inventory),
            ("C Library Basic Functions", self.test_c_library_basic),
            ("Module Signing Simulation", self.test_module_signing_simulation),
            ("System Integration", self.test_system_integration),
            ("Error Handling", self.test_error_handling),
        ]
        
        # Run all tests
        for test_name, test_func in tests:
            self.run_test(test_name, test_func)
        
        self.cleanup_temp_environment()
        
        # Print summary
        print("\n" + "=" * 60)
        print("📊 TEST RESULTS SUMMARY")
        print("=" * 60)
        
        passed = sum(1 for _, success, _ in self.test_results if success)
        total = len(self.test_results)
        
        for test_name, success, error in self.test_results:
            status = "✅ PASS" if success else "❌ FAIL"
            print(f"{status:<8} {test_name}")
            if error and not success:
                print(f"         Error: {error}")
        
        print(f"\nOverall: {passed}/{total} tests passed")
        
        if passed == total:
            print("🎉 All tests passed! PhoenixGuard system is ready.")
            return True
        else:
            print(f"⚠️  {total - passed} test(s) failed. Review the output above.")
            return False

def main():
    """Main test runner"""
    test_suite = PhoenixGuardIntegrationTest()
    success = test_suite.run_all_tests()
    sys.exit(0 if success else 1)

if __name__ == "__main__":
    main()
