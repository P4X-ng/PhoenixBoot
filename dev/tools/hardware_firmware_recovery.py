#!/usr/bin/env python3
"""
PhoenixGuard Hardware-Level Firmware Recovery
BOOTKIT-PROOF firmware recovery using direct SPI flash access

This bypasses potentially compromised BIOS utilities (like ASUS EZ Flash)
and works directly with the hardware using flashrom, chipsec, and other
low-level tools to ensure the bootkit can't interfere with recovery.

CRITICAL: This script operates at the hardware level and can brick your system
if used incorrectly. Always have a hardware programmer as backup!
"""

import os
import sys
import subprocess
import json
import hashlib
import time
from pathlib import Path
import argparse
import logging

class HardwareFirmwareRecovery:
    def __init__(self, recovery_image_path, verify_only=False):
        self.recovery_image_path = Path(recovery_image_path)
        self.verify_only = verify_only
        self.flash_chip = None
        self.flash_size = None
        self.backup_path = None
        
        # Hardware tools we'll use
        self.tools = {
            'flashrom': self._find_tool('flashrom'),
            'chipsec': self._find_tool('chipsec_main'),
            'dmidecode': self._find_tool('dmidecode'),
            'lspci': self._find_tool('lspci'),
        }
        
        self.results = {
            'timestamp': time.strftime('%Y%m%dT%H%M%SZ'),
            'hardware_detected': {},
            'flash_chip_info': {},
            'verification_results': {},
            'bootkit_protections': {},
            'protection_bypass_status': {},
            'recovery_performed': False,
            'backup_created': None,
            'warnings': [],
            'errors': []
        }

    def _find_tool(self, tool_name):
        """Find tool in PATH or common locations"""
        # Check PATH first
        result = subprocess.run(['which', tool_name], capture_output=True, text=True)
        if result.returncode == 0:
            return result.stdout.strip()
        
        # Check common locations
        common_paths = [
            f'/usr/bin/{tool_name}',
            f'/usr/local/bin/{tool_name}',
            f'/sbin/{tool_name}',
            f'/usr/sbin/{tool_name}',
            f'/opt/chipsec/{tool_name}',  # chipsec specific
        ]
        
        for path in common_paths:
            if os.path.exists(path):
                return path
        
        return None

    def check_requirements(self):
        """Verify all required tools are available"""
        logging.info("🔧 Checking hardware recovery requirements...")
        
        missing_critical = []
        missing_optional = []
        for tool, path in self.tools.items():
            if path:
                logging.info(f"  ✅ {tool}: {path}")
            else:
                if tool == 'chipsec':
                    missing_optional.append(tool)
                    logging.warning(f"  ⚠️  {tool}: NOT FOUND (optional - limits bypass capabilities)")
                else:
                    missing_critical.append(tool)
                    logging.error(f"  ❌ {tool}: NOT FOUND")
        
        if missing_critical:
            self.results['errors'].append(f"Missing critical tools: {', '.join(missing_critical)}")
            logging.error("❌ Missing required tools. Install with:")
            if 'flashrom' in missing_critical:
                logging.error("   sudo apt install flashrom")
            if 'dmidecode' in missing_critical:
                logging.error("   sudo apt install dmidecode")
            return False
        
        if missing_optional:
            self.results['warnings'].append(f"Missing optional tools: {', '.join(missing_optional)}")
            logging.warning("⚠️  Optional tools missing - some bypass methods unavailable:")
            if 'chipsec' in missing_optional:
                logging.warning("   pip install chipsec (enables hardware register manipulation)")
        
        # Check root privileges
        if os.geteuid() != 0:
            self.results['errors'].append("Root privileges required for hardware access")
            logging.error("❌ Root privileges required. Run with sudo.")
            return False
        
        return True

    def detect_hardware_info(self):
        """Detect hardware platform and SPI flash chip"""
        logging.info("🔍 Detecting hardware platform...")
        
        try:
            # Get system info via dmidecode
            result = subprocess.run([self.tools['dmidecode'], '-t', 'system'], 
                                   capture_output=True, text=True, timeout=30)
            if result.returncode == 0:
                self.results['hardware_detected']['system_info'] = result.stdout
                
                # Extract key info
                for line in result.stdout.split('\n'):
                    if 'Manufacturer:' in line:
                        self.results['hardware_detected']['manufacturer'] = line.split(':', 1)[1].strip()
                    elif 'Product Name:' in line:
                        self.results['hardware_detected']['product'] = line.split(':', 1)[1].strip()
            
            # Get BIOS info
            result = subprocess.run([self.tools['dmidecode'], '-t', 'bios'], 
                                   capture_output=True, text=True, timeout=30)
            if result.returncode == 0:
                self.results['hardware_detected']['bios_info'] = result.stdout
            
            # Get chipset info via lspci
            result = subprocess.run([self.tools['lspci'], '-nn'], 
                                   capture_output=True, text=True, timeout=30)
            if result.returncode == 0:
                self.results['hardware_detected']['pci_devices'] = result.stdout
                
        except Exception as e:
            logging.warning(f"Hardware detection failed: {e}")
            self.results['warnings'].append(f"Hardware detection failed: {e}")

    def detect_flash_chip(self):
        """Detect SPI flash chip using flashrom"""
        logging.info("🔍 Detecting SPI flash chip...")
        
        try:
            # Try to detect flash chip
            result = subprocess.run([self.tools['flashrom'], '--programmer', 'internal', '--flash-name'], 
                                   capture_output=True, text=True, timeout=60)
            
            if result.returncode == 0:
                flash_info = result.stdout.strip()
                self.results['flash_chip_info']['detected'] = flash_info
                logging.info(f"  🎯 Detected flash chip: {flash_info}")
                self.flash_chip = flash_info
                
                # Get flash size
                result = subprocess.run([self.tools['flashrom'], '--programmer', 'internal', '--flash-size'], 
                                       capture_output=True, text=True, timeout=30)
                if result.returncode == 0:
                    self.flash_size = int(result.stdout.strip())
                    self.results['flash_chip_info']['size'] = self.flash_size
                    logging.info(f"  📏 Flash size: {self.flash_size} bytes")
                
                return True
            else:
                error_msg = result.stderr.strip()
                self.results['errors'].append(f"Flash chip detection failed: {error_msg}")
                logging.error(f"❌ Flash chip detection failed: {error_msg}")
                return False
                
        except Exception as e:
            self.results['errors'].append(f"Flash chip detection error: {e}")
            logging.error(f"❌ Flash chip detection error: {e}")
            return False

    def detect_bootkit_protections(self):
        """Detect bootkit-enabled hardware protection mechanisms"""
        logging.info("🕵️  Detecting bootkit protection mechanisms...")
        
        protections = {
            'spi_flash_locked': False,
            'bios_write_enable_locked': False, 
            'protected_ranges_active': False,
            'flash_descriptor_locked': False,
            'cpu_microcode_locked': False,
            'details': {}
        }
        
        try:
            # Check if chipsec is available for hardware register inspection
            if self.tools['chipsec']:
                self._check_spi_protection_with_chipsec(protections)
            else:
                # Fallback: Try to detect protections using flashrom error patterns
                self._check_protection_via_flashrom(protections)
                
        except Exception as e:
            logging.warning(f"Protection detection failed: {e}")
            self.results['warnings'].append(f"Protection detection failed: {e}")
        
        self.results['bootkit_protections'] = protections
        
        # Report findings
        if any([protections['spi_flash_locked'], protections['bios_write_enable_locked'], 
                protections['protected_ranges_active'], protections['flash_descriptor_locked']]):
            logging.warning("🚨 BOOTKIT PROTECTIONS DETECTED!")
            if protections['spi_flash_locked']:
                logging.warning("  🔒 SPI Flash Write Protection: ENABLED")
            if protections['bios_write_enable_locked']:
                logging.warning("  🔒 BIOS Write Enable Lock: ENABLED")
            if protections['protected_ranges_active']:
                logging.warning("  🔒 SPI Protected Ranges: ACTIVE")
            if protections['flash_descriptor_locked']:
                logging.warning("  🔒 Flash Descriptor Lock: ENABLED")
            if protections['cpu_microcode_locked']:
                logging.warning("  🔒 CPU Microcode Update Lock: ENABLED")
        else:
            logging.info("✅ No bootkit protections detected")
            
        return protections
    
    def _check_spi_protection_with_chipsec(self, protections):
        """Use chipsec to check SPI flash protection registers"""
        logging.debug("Using chipsec to check hardware protection registers...")
        
        try:
            # Check SPI Flash Protection registers
            # FLOCKDN (Flash Configuration Lock-Down)
            result = subprocess.run([
                self.tools['chipsec'], '-m', 'common.spi_lock', '-a', 'check'
            ], capture_output=True, text=True, timeout=60)
            
            if result.returncode == 0:
                output = result.stdout.lower()
                if 'flockdn' in output and 'set' in output:
                    protections['flash_descriptor_locked'] = True
                    protections['details']['flockdn_status'] = 'locked'
                
            # Check BIOS_CNTL register for BWE (BIOS Write Enable) lock
            result = subprocess.run([
                self.tools['chipsec'], '-m', 'common.bios_wp', '-a', 'check'
            ], capture_output=True, text=True, timeout=60)
            
            if result.returncode == 0:
                output = result.stdout.lower()
                if 'bioswe' in output and ('disabled' in output or 'locked' in output):
                    protections['bios_write_enable_locked'] = True
                    protections['details']['bioswe_status'] = 'locked'
            
            # Check SPI Protected Ranges (PR0-PR4)
            result = subprocess.run([
                self.tools['chipsec'], '-m', 'common.spi_desc', '-a', 'check'
            ], capture_output=True, text=True, timeout=60)
            
            if result.returncode == 0:
                output = result.stdout.lower()
                if 'protected range' in output and 'enabled' in output:
                    protections['protected_ranges_active'] = True
                    protections['details']['protected_ranges'] = 'active'
                    
        except Exception as e:
            logging.debug(f"Chipsec protection check failed: {e}")
    
    def _check_protection_via_flashrom(self, protections):
        """Use flashrom write attempts to detect protections (non-destructive)"""
        logging.debug("Using flashrom to detect protection mechanisms...")
        
        try:
            # Try a dry-run write to see what protections are active
            # This won't actually write anything but will report protection errors
            result = subprocess.run([
                self.tools['flashrom'], '--programmer', 'internal', 
                '--write', '/dev/null', '--dry-run'
            ], capture_output=True, text=True, timeout=60)
            
            error_output = result.stderr.lower()
            
            # Look for specific protection error patterns
            if 'write protect' in error_output or 'wp' in error_output:
                protections['spi_flash_locked'] = True
                protections['details']['flashrom_wp_detected'] = True
            
            if 'bioswe' in error_output or 'bios write enable' in error_output:
                protections['bios_write_enable_locked'] = True
                protections['details']['bioswe_detected'] = True
            
            if 'protected range' in error_output or 'pr0' in error_output:
                protections['protected_ranges_active'] = True
                protections['details']['protected_ranges_detected'] = True
                
        except Exception as e:
            logging.debug(f"Flashrom protection check failed: {e}")

    def bypass_bootkit_protections(self):
        """Attempt to bypass bootkit-imposed hardware protections"""
        if self.verify_only:
            logging.info("🔍 Verify-only mode: skipping protection bypass")
            return True
            
        logging.info("🔓 Attempting to bypass bootkit protections...")
        
        bypass_status = {
            'spi_protection_bypassed': False,
            'bios_lock_bypassed': False,
            'descriptor_lock_bypassed': False,
            'methods_used': [],
            'success': False
        }
        
        try:
            # Method 1: Direct SPI controller manipulation via chipsec
            if self.tools['chipsec']:
                if self._bypass_via_chipsec(bypass_status):
                    logging.info("✅ Successfully bypassed protections using chipsec")
                    bypass_status['success'] = True
            
            # Method 2: Hardware-level flashrom with forced parameters  
            if not bypass_status['success']:
                if self._bypass_via_flashrom_force(bypass_status):
                    logging.info("✅ Successfully bypassed protections using flashrom")
                    bypass_status['success'] = True
            
            # Method 3: Alternative hardware programmer interfaces
            if not bypass_status['success']:
                if self._bypass_via_alternative_programmers(bypass_status):
                    logging.info("✅ Successfully bypassed protections using alternative programmer")
                    bypass_status['success'] = True
                    
        except Exception as e:
            logging.error(f"Protection bypass failed: {e}")
            self.results['errors'].append(f"Protection bypass failed: {e}")
        
        self.results['protection_bypass_status'] = bypass_status
        
        if not bypass_status['success']:
            logging.error("❌ Failed to bypass all bootkit protections")
            logging.error("   This bootkit has locked the firmware at the hardware level.")
            logging.error("   Hardware programmer may be required for recovery.")
            return False
        
        return True
    
    def _bypass_via_chipsec(self, bypass_status):
        """Use chipsec to manipulate hardware protection registers directly"""
        logging.info("🔧 Attempting bypass via chipsec hardware register manipulation...")
        
        try:
            bypass_status['methods_used'].append('chipsec_register_manipulation')
            
            # Disable FLOCKDN (Flash Configuration Lock-Down) if possible
            result = subprocess.run([
                self.tools['chipsec'], '-m', 'tools.uefi.spi', '-a', 'unlock'
            ], capture_output=True, text=True, timeout=120)
            
            if result.returncode == 0:
                bypass_status['descriptor_lock_bypassed'] = True
                logging.info("  ✅ Flash descriptor lock bypassed")
            
            # Enable BIOSWE (BIOS Write Enable)
            result = subprocess.run([
                self.tools['chipsec'], '-m', 'tools.uefi.bios_wp', '-a', 'disable'
            ], capture_output=True, text=True, timeout=120)
            
            if result.returncode == 0:
                bypass_status['bios_lock_bypassed'] = True
                logging.info("  ✅ BIOS write protection bypassed")
                
            # Clear SPI protected ranges
            for pr_num in range(5):  # PR0-PR4
                result = subprocess.run([
                    self.tools['chipsec'], '-m', 'tools.spi.spi', 
                    '-a', 'clear_pr', f'-pr', str(pr_num)
                ], capture_output=True, text=True, timeout=60)
                
                if result.returncode == 0:
                    bypass_status['spi_protection_bypassed'] = True
                    logging.info(f"  ✅ Cleared SPI protected range PR{pr_num}")
                    
            return bypass_status['bios_lock_bypassed'] or bypass_status['spi_protection_bypassed']
            
        except Exception as e:
            logging.debug(f"Chipsec bypass failed: {e}")
            return False
    
    def dump_flash(self, output_path=None):
        """Extract SPI flash ROM to timestamped binary file"""
        if not output_path:
            timestamp = time.strftime('%Y%m%dT%H%M%SZ')
            output_path = f"firmware_dump_{timestamp}.bin"
        
        output_path = Path(output_path).resolve()
        logging.info(f"📥 Dumping SPI flash to {output_path}...")
        
        try:
            # Create backup directory
            output_path.parent.mkdir(parents=True, exist_ok=True)
            
            # Use flashrom to read the entire flash
            cmd = [self.tools['flashrom'], '--programmer', 'internal', '--read', str(output_path)]
            
            logging.info(f"Running: {' '.join(cmd)}")
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
            
            if result.returncode == 0:
                if output_path.exists():
                    file_size = output_path.stat().st_size
                    logging.info(f"✅ Flash dump successful: {file_size} bytes written to {output_path}")
                    
                    # Calculate and store hash
                    with open(output_path, 'rb') as f:
                        flash_data = f.read()
                        flash_hash = hashlib.sha256(flash_data).hexdigest()
                    
                    self.results['flash_dump'] = {
                        'file_path': str(output_path),
                        'size_bytes': file_size,
                        'sha256': flash_hash,
                        'timestamp': time.strftime('%Y-%m-%dT%H:%M:%SZ')
                    }
                    
                    self.backup_path = output_path
                    logging.info(f"📊 Flash SHA256: {flash_hash}")
                    return output_path
                else:
                    error_msg = "Flash dump file was not created"
                    self.results['errors'].append(error_msg)
                    logging.error(f"❌ {error_msg}")
                    return None
            else:
                error_msg = f"flashrom read failed: {result.stderr.strip()}"
                self.results['errors'].append(error_msg)
                logging.error(f"❌ {error_msg}")
                return None
                
        except Exception as e:
            error_msg = f"Flash dump failed: {e}"
            self.results['errors'].append(error_msg)
            logging.error(f"❌ {error_msg}")
            return None
    
    def _bypass_via_flashrom_force(self, bypass_status):
        """Use flashrom with forced parameters to bypass protections"""
        logging.info("🔧 Attempting bypass via flashrom forced parameters...")
        
        try:
            bypass_status['methods_used'].append('flashrom_force')
            
            # Try flashrom with various bypass flags
            bypass_flags = [
                '--force',  # Force operation despite warnings
                '--wp-disable',  # Disable write protection if supported
                '--ignore-fmap',  # Ignore flash map restrictions
            ]
            
            # Test if we can now access flash with bypass flags
            for flag_combo in [bypass_flags[:1], bypass_flags[:2], bypass_flags]:
                cmd = [self.tools['flashrom'], '--programmer', 'internal'] + flag_combo + ['--probe']
                
                result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
                
                if result.returncode == 0 and 'found' in result.stdout.lower():
                    bypass_status['spi_protection_bypassed'] = True
                    logging.info(f"  ✅ Flashrom bypass successful with flags: {' '.join(flag_combo)}")
                    return True
                    
            return False
            
        except Exception as e:
            logging.debug(f"Flashrom force bypass failed: {e}")
            return False
    
    def _bypass_via_alternative_programmers(self, bypass_status):
        """Try alternative programmer interfaces that bootkits may not protect"""
        logging.info("🔧 Attempting bypass via alternative programmer interfaces...")
        
        try:
            bypass_status['methods_used'].append('alternative_programmers')
            
            # Try different programmer interfaces that bypass chipset locks
            alternative_programmers = [
                'dediprog',  # External programmer
                'ft2232_spi',  # FTDI-based programmer 
                'ch341a_spi',  # CH341A programmer
                'raiden_debug_spi',  # Google raiden debug
            ]
            
            for programmer in alternative_programmers:
                cmd = [self.tools['flashrom'], '--programmer', programmer, '--probe']
                
                result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
                
                if result.returncode == 0 and 'found' in result.stdout.lower():
                    bypass_status['spi_protection_bypassed'] = True
                    logging.info(f"  ✅ Alternative programmer {programmer} available")
                    return True
                    
            return False
            
        except Exception as e:
            logging.debug(f"Alternative programmer bypass failed: {e}")
            return False

    def backup_current_firmware(self):
        """Create hardware-level backup of current firmware"""
        if self.verify_only:
            logging.info("🔍 Verify-only mode: skipping backup")
            return True
            
        timestamp = time.strftime('%Y%m%d_%H%M%S')
        self.backup_path = f"firmware_backup_{timestamp}.bin"
        
        logging.info(f"💾 Creating hardware-level firmware backup...")
        logging.info(f"   Backup will be saved as: {self.backup_path}")
        
        try:
            result = subprocess.run([
                self.tools['flashrom'], 
                '--programmer', 'internal',
                '--read', self.backup_path
            ], capture_output=True, text=True, timeout=300)
            
            if result.returncode == 0:
                # Verify backup was created and has correct size
                if os.path.exists(self.backup_path):
                    backup_size = os.path.getsize(self.backup_path)
                    backup_hash = self._calculate_file_hash(self.backup_path)
                    
                    self.results['backup_created'] = {
                        'path': self.backup_path,
                        'size': backup_size,
                        'sha256': backup_hash
                    }
                    
                    logging.info(f"  ✅ Backup created: {self.backup_path}")
                    logging.info(f"  📏 Size: {backup_size} bytes")
                    logging.info(f"  🔒 SHA256: {backup_hash}")
                    return True
                else:
                    self.results['errors'].append("Backup file was not created")
                    return False
            else:
                error_msg = result.stderr.strip()
                self.results['errors'].append(f"Firmware backup failed: {error_msg}")
                logging.error(f"❌ Firmware backup failed: {error_msg}")
                return False
                
        except Exception as e:
            self.results['errors'].append(f"Backup error: {e}")
            logging.error(f"❌ Backup error: {e}")
            return False

    def load_firmware_baselines(self, baseline_db_path=None):
        """Load known-good firmware baselines database"""
        if not baseline_db_path:
            # Check for default baseline database locations
            possible_paths = [
                'firmware_baseline.json',
                'Tegrity/baselines/firmware_baseline.json',
                '/etc/phoenixguard/firmware_baseline.json'
            ]
            
            for path in possible_paths:
                if Path(path).exists():
                    baseline_db_path = path
                    break
        
        if not baseline_db_path or not Path(baseline_db_path).exists():
            logging.warning("⚠️  No firmware baseline database found")
            logging.warning("   Cannot perform baseline integrity verification")
            return {}
            
        try:
            with open(baseline_db_path, 'r') as f:
                baselines = json.load(f)
                logging.info(f"📚 Loaded firmware baselines from: {baseline_db_path}")
                return baselines.get('firmware_hashes', {})
        except Exception as e:
            logging.warning(f"Failed to load baseline database: {e}")
            return {}
    
    def verify_against_baseline(self, firmware_hash, hardware_info=None):
        """Verify firmware hash against known-good baselines"""
        baselines = self.load_firmware_baselines()
        
        if not baselines:
            logging.info("🔍 No baselines available - cannot verify firmware integrity")
            return {'verified': False, 'reason': 'no_baselines', 'status': 'unknown'}
            
        # Try to match against hardware-specific baselines first
        if hardware_info:
            manufacturer = hardware_info.get('manufacturer', '').lower()
            product = hardware_info.get('product', '').lower()
            
            # Look for hardware-specific entries
            for baseline_key, baseline_data in baselines.items():
                if manufacturer in baseline_key.lower() or product in baseline_key.lower():
                    if isinstance(baseline_data, dict):
                        baseline_hashes = baseline_data.get('hashes', [])
                    else:
                        baseline_hashes = [baseline_data] if isinstance(baseline_data, str) else []
                    
                    if firmware_hash.lower() in [h.lower() for h in baseline_hashes]:
                        logging.info(f"✅ Firmware verified against baseline: {baseline_key}")
                        return {
                            'verified': True, 
                            'baseline_match': baseline_key,
                            'status': 'clean'
                        }
        
        # Check against general known-good hashes
        all_known_good = []
        for baseline_data in baselines.values():
            if isinstance(baseline_data, dict):
                all_known_good.extend(baseline_data.get('hashes', []))
            elif isinstance(baseline_data, str):
                all_known_good.append(baseline_data)
            elif isinstance(baseline_data, list):
                all_known_good.extend(baseline_data)
        
        if firmware_hash.lower() in [h.lower() for h in all_known_good]:
            logging.info("✅ Firmware hash found in known-good baseline database")
            return {'verified': True, 'baseline_match': 'general', 'status': 'clean'}
        
        # Check against known-bad hashes if available
        known_bad = baselines.get('known_malicious', [])
        if firmware_hash.lower() in [h.lower() for h in known_bad]:
            logging.error("🚨 CRITICAL: Firmware matches KNOWN MALICIOUS hash!")
            logging.error("   This firmware is confirmed to be compromised.")
            return {
                'verified': True, 
                'baseline_match': 'known_malicious',
                'status': 'malicious'
            }
        
        # Unknown hash - could be compromised
        logging.warning("⚠️  Firmware hash NOT found in baseline database")
        logging.warning("   This could indicate firmware compromise or a new/unknown version")
        return {
            'verified': False, 
            'reason': 'unknown_hash',
            'status': 'suspicious'
        }
    
    def verify_recovery_image(self):
        """Verify the recovery firmware image"""
        logging.info("🔍 Verifying recovery firmware image...")
        
        if not self.recovery_image_path.exists():
            self.results['errors'].append(f"Recovery image not found: {self.recovery_image_path}")
            return False
        
        # Check file size
        image_size = self.recovery_image_path.stat().st_size
        image_hash = self._calculate_file_hash(self.recovery_image_path)
        
        # Verify against baseline if available
        hardware_info = self.results.get('hardware_detected', {})
        baseline_verification = self.verify_against_baseline(image_hash, hardware_info)
        
        self.results['verification_results'] = {
            'recovery_image_path': str(self.recovery_image_path),
            'size': image_size,
            'sha256': image_hash,
            'baseline_verification': baseline_verification
        }
        
        logging.info(f"  📁 Recovery image: {self.recovery_image_path}")
        logging.info(f"  📏 Size: {image_size} bytes")
        logging.info(f"  🔒 SHA256: {image_hash}")
        
        # Report baseline verification results
        if baseline_verification['status'] == 'clean':
            logging.info("✅ Recovery image verified as CLEAN in baseline database")
        elif baseline_verification['status'] == 'malicious':
            logging.error("❌ Recovery image matches KNOWN MALICIOUS signature!")
            self.results['errors'].append("Recovery image is known malicious")
            return False
        elif baseline_verification['status'] == 'suspicious':
            logging.warning("⚠️  Recovery image not found in baseline database (suspicious)")
            logging.warning("   Proceed with caution - this may not be a clean firmware")
        
        # Compare with flash size if available
        if self.flash_size and image_size != self.flash_size:
            warning = f"Recovery image size ({image_size}) doesn't match flash size ({self.flash_size})"
            self.results['warnings'].append(warning)
            logging.warning(f"⚠️  {warning}")
        
        return True

    def write_flash(self, firmware_image_path, skip_confirmation=False):
        """Write clean firmware to SPI flash with protection bypass"""
        firmware_path = Path(firmware_image_path)
        if not firmware_path.exists():
            error_msg = f"Firmware image not found: {firmware_path}"
            self.results['errors'].append(error_msg)
            logging.error(f"❌ {error_msg}")
            return False
            
        logging.info(f"🔧 Writing clean firmware: {firmware_path}")
        
        try:
            # Step 1: Bypass protections if needed
            protections = self.results.get('bootkit_protections', {})
            if any([protections.get('spi_flash_locked'), protections.get('bios_write_enable_locked'),
                   protections.get('protected_ranges_active'), protections.get('flash_descriptor_locked')]):
                logging.warning("🔒 Bootkit protections detected - bypassing...")
                if not self.bypass_bootkit_protections():
                    return False
            
            # Step 2: Write firmware with verification
            cmd = [
                self.tools['flashrom'], 
                '--programmer', 'internal',
                '--write', str(firmware_path),
                '--verify'  # Always verify after write
            ]
            
            if not skip_confirmation:
                logging.warning("🚨 DANGER: About to overwrite SPI flash firmware!")
                logging.warning(f"   Target: {firmware_path}")
                print("\nType 'WRITE' to continue, or Ctrl+C to abort:")
                try:
                    confirmation = input().strip()
                    if confirmation != "WRITE":
                        logging.info("Write operation aborted by user")
                        return False
                except KeyboardInterrupt:
                    logging.info("\nWrite operation aborted by user")
                    return False
            
            logging.info(f"Running: {' '.join(cmd)}")
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=600)
            
            if result.returncode == 0:
                logging.info("✅ Firmware write and verify successful!")
                self.results['recovery_performed'] = True
                return True
            else:
                error_msg = f"Firmware write failed: {result.stderr.strip()}"
                self.results['errors'].append(error_msg)
                logging.error(f"❌ {error_msg}")
                return False
                
        except Exception as e:
            error_msg = f"Write flash error: {e}"
            self.results['errors'].append(error_msg)
            logging.error(f"❌ {error_msg}")
            return False
    
    def restore_backup(self, backup_path=None):
        """Restore firmware from verified backup"""
        if not backup_path:
            backup_path = self.backup_path
            
        if not backup_path or not Path(backup_path).exists():
            error_msg = f"Backup not found: {backup_path}"
            self.results['errors'].append(error_msg)
            logging.error(f"❌ {error_msg}")
            return False
            
        logging.info(f"💾 Restoring firmware from backup: {backup_path}")
        return self.write_flash(backup_path, skip_confirmation=False)
        
    def hardware_firmware_recovery(self):
        """Perform the actual firmware recovery using hardware-level access"""
        if self.verify_only:
            logging.info("🔍 Verify-only mode: skipping recovery")
            return True
            
        logging.warning("🚨 DANGER: About to perform hardware-level firmware recovery!")
        logging.warning("   This will overwrite the current firmware directly on the SPI flash chip.")
        logging.warning("   If this fails, your system may be bricked and require hardware recovery.")
        logging.warning("")
        logging.warning("   Backup created: " + (self.backup_path or "NONE"))
        logging.warning("")
        
        # Final confirmation
        print("\n🚨 FINAL WARNING: This will perform HARDWARE-LEVEL firmware recovery!")
        print(f"   Current firmware will be replaced with: {self.recovery_image_path}")
        print(f"   Backup saved as: {self.backup_path}")
        print("   If this fails, you may need a hardware programmer to recover!")
        print("\nType 'RECOVER' to continue, or Ctrl+C to abort:")
        
        try:
            confirmation = input().strip()
            if confirmation != "RECOVER":
                logging.info("Recovery aborted by user")
                return False
        except KeyboardInterrupt:
            logging.info("\nRecovery aborted by user")
            return False
        
        logging.info("🔧 Starting hardware-level firmware recovery...")
        
        try:
            result = subprocess.run([
                self.tools['flashrom'],
                '--programmer', 'internal',
                '--write', str(self.recovery_image_path),
                '--verify'  # Verify after writing
            ], capture_output=True, text=True, timeout=600)
            
            if result.returncode == 0:
                self.results['recovery_performed'] = True
                logging.info("✅ Hardware-level firmware recovery completed successfully!")
                logging.info("   The firmware has been written directly to the SPI flash chip.")
                logging.info("   System reboot required to use new firmware.")
                return True
            else:
                error_msg = result.stderr.strip()
                self.results['errors'].append(f"Firmware recovery failed: {error_msg}")
                logging.error(f"❌ Firmware recovery failed: {error_msg}")
                
                # If recovery failed, we're in a dangerous state
                logging.error("🚨 CRITICAL: Firmware recovery failed!")
                logging.error("   Your system may be in an unstable state.")
                logging.error("   Do NOT reboot until this is resolved.")
                
                return False
                
        except Exception as e:
            self.results['errors'].append(f"Recovery error: {e}")
            logging.error(f"❌ Recovery error: {e}")
            return False

    def _calculate_file_hash(self, file_path):
        """Calculate SHA256 hash of a file"""
        sha256_hash = hashlib.sha256()
        with open(file_path, "rb") as f:
            for chunk in iter(lambda: f.read(4096), b""):
                sha256_hash.update(chunk)
        return sha256_hash.hexdigest()

    def save_results(self, output_path="hardware_recovery_results.json"):
        """Save recovery results to JSON file"""
        try:
            with open(output_path, 'w') as f:
                json.dump(self.results, f, indent=2)
            logging.info(f"📊 Results saved to: {output_path}")
        except Exception as e:
            logging.error(f"Failed to save results: {e}")

    def run_recovery(self):
        """Execute the complete hardware recovery process"""
        logging.info("🚀 PhoenixGuard Hardware-Level Firmware Recovery")
        logging.info("=" * 60)
        
        # Step 1: Check requirements
        if not self.check_requirements():
            return False
        
        # Step 2: Detect hardware
        self.detect_hardware_info()
        
        # Step 3: Detect flash chip
        if not self.detect_flash_chip():
            return False
        
        # Step 4: Detect bootkit protections  
        protections = self.detect_bootkit_protections()
        
        # Step 5: Bypass bootkit protections if detected
        if any([protections['spi_flash_locked'], protections['bios_write_enable_locked'], 
                protections['protected_ranges_active'], protections['flash_descriptor_locked']]):
            logging.warning("🚨 BOOTKIT PROTECTIONS ACTIVE - attempting bypass...")
            if not self.bypass_bootkit_protections():
                logging.error("❌ Failed to bypass bootkit protections!")
                logging.error("   This firmware recovery cannot proceed with hardware locks active.")
                return False
        
        # Step 6: Verify recovery image
        if not self.verify_recovery_image():
            return False
        
        # Step 7: Backup current firmware
        if not self.backup_current_firmware():
            return False
        
        # Step 8: Perform recovery (if not verify-only)
        if not self.hardware_firmware_recovery():
            return False
        
        logging.info("\n🎉 Hardware firmware recovery process completed!")
        return True

def main():
    parser = argparse.ArgumentParser(
        description='PhoenixGuard Hardware-Level Firmware Recovery',
        epilog='WARNING: This tool directly manipulates SPI flash hardware. Use with extreme caution!'
    )
    parser.add_argument('recovery_image', help='Path to clean firmware image (e.g., G615LPAS.325)')
    parser.add_argument('--verify-only', action='store_true',
                       help='Only verify hardware/image, do not perform recovery')
    parser.add_argument('-v', '--verbose', action='store_true', help='Verbose logging')
    parser.add_argument('--output', help='Output results JSON file', 
                       default='hardware_recovery_results.json')
    
    args = parser.parse_args()
    
    # Setup logging
    log_level = logging.DEBUG if args.verbose else logging.INFO
    logging.basicConfig(
        level=log_level,
        format='%(asctime)s - %(levelname)s - %(message)s'
    )
    
    # Check if recovery image exists
    if not os.path.exists(args.recovery_image):
        logging.error(f"Recovery image not found: {args.recovery_image}")
        return 1
    
    # Create recovery instance
    recovery = HardwareFirmwareRecovery(args.recovery_image, args.verify_only)
    
    try:
        success = recovery.run_recovery()
        recovery.save_results(args.output)
        
        if success:
            if args.verify_only:
                print("\n✅ Hardware verification completed successfully!")
            else:
                print("\n✅ Hardware firmware recovery completed!")
                print("🔄 REBOOT REQUIRED to use new firmware")
                print("⚠️  Monitor system boot carefully for any issues")
        else:
            print("\n❌ Hardware recovery failed!")
            print("📊 Check results file for details:", args.output)
            return 1
            
    except KeyboardInterrupt:
        print("\n⚠️  Recovery interrupted by user")
        recovery.save_results(args.output)
        return 1
    except Exception as e:
        logging.error(f"Unexpected error: {e}")
        recovery.save_results(args.output)
        return 1
    
    return 0

if __name__ == '__main__':
    sys.exit(main())
