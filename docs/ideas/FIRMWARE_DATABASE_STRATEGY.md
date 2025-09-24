# 🗄️ PhoenixGuard Firmware Database Strategy

## Overview

PhoenixGuard needs a comprehensive database of **known-clean firmware images** to enable effective bootkit detection and recovery. This document outlines a strategy for automatically discovering, collecting, and verifying firmware from multiple sources.

## 🎯 Database Architecture

### Core Schema
```sql
-- SQLite/PostgreSQL schema for firmware database
CREATE TABLE firmware_images (
    id INTEGER PRIMARY KEY,
    vendor TEXT NOT NULL,                    -- 'ASUS', 'Intel', 'AMI', etc.
    model TEXT NOT NULL,                     -- 'ROG Strix X570-E', 'NUC10i7FNH', etc.
    part_number TEXT,                        -- Specific part/model number
    version TEXT NOT NULL,                   -- BIOS version (e.g., '0704', '2021.1')
    cpu_family TEXT,                         -- 'Coffee Lake', 'Zen 3', etc.
    chipset TEXT,                           -- 'Z590', 'X570', 'H470', etc.
    size INTEGER NOT NULL,                   -- File size in bytes
    sha256 TEXT UNIQUE NOT NULL,            -- Primary integrity check
    sha1 TEXT NOT NULL,                     -- Legacy compatibility  
    md5 TEXT NOT NULL,                      -- Additional verification
    crc32 TEXT NOT NULL,                    -- Quick validation
    file_type TEXT NOT NULL,                -- 'UEFI', 'Legacy', 'Capsule'
    compression TEXT,                       -- 'None', 'LZMA', 'LZ4', etc.
    digital_signature BLOB,                 -- Vendor digital signature
    signature_valid BOOLEAN,               -- Signature verification result
    source_url TEXT,                       -- Where we found it
    source_type TEXT,                      -- 'Vendor', 'Mirror', 'User'
    discovered_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    verified_date TIMESTAMP,
    notes TEXT,
    confidence_score INTEGER DEFAULT 0      -- 0-100, higher = more trusted
);

CREATE TABLE hardware_mappings (
    id INTEGER PRIMARY KEY,
    firmware_id INTEGER REFERENCES firmware_images(id),
    device_id TEXT,                         -- PCI device ID
    subsystem_id TEXT,                      -- PCI subsystem ID  
    smbios_strings TEXT,                    -- JSON array of SMBIOS identifiers
    dmidecode_match TEXT,                   -- dmidecode pattern matching
    chipset_registers TEXT,                 -- JSON of register signatures
    cpu_signature TEXT,                     -- CPU signature from CPUID
    platform_id TEXT,                      -- Platform-specific identifier
    compatibility_score INTEGER DEFAULT 100 -- How well this firmware matches
);

CREATE TABLE verification_results (
    id INTEGER PRIMARY KEY,
    firmware_id INTEGER REFERENCES firmware_images(id),
    verification_type TEXT,                 -- 'signature', 'hash', 'structure'
    result BOOLEAN,
    details TEXT,                          -- JSON with verification specifics
    verified_by TEXT,                      -- Tool/person that verified
    verified_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for performance
CREATE INDEX idx_firmware_vendor_model ON firmware_images(vendor, model);
CREATE INDEX idx_firmware_sha256 ON firmware_images(sha256);
CREATE INDEX idx_hardware_device ON hardware_mappings(device_id, subsystem_id);
```

## 🕷️ Automated Collection System

### Multi-Source Spider Architecture
```python
#!/usr/bin/env python3
"""
PhoenixGuard Firmware Collection Spider
Automatically discovers and downloads firmware from multiple sources
"""
import asyncio
import aiohttp
import hashlib
import sqlite3
import json
import re
import subprocess
from pathlib import Path
from dataclasses import dataclass
from typing import List, Dict, Optional
import logging

@dataclass
class FirmwareCandidate:
    vendor: str
    model: str
    version: str
    url: str
    source_type: str
    file_size: Optional[int] = None
    confidence_score: int = 0

class FirmwareSpider:
    def __init__(self, db_path: str = "firmware.db"):
        self.db_path = Path(db_path)
        self.session: Optional[aiohttp.ClientSession] = None
        self.download_dir = Path("firmware_downloads")
        self.download_dir.mkdir(exist_ok=True)
        
        # Initialize database
        self._init_database()
        
        # Configure logging
        logging.basicConfig(level=logging.INFO)
        self.logger = logging.getLogger(__name__)
    
    def _init_database(self):
        """Initialize SQLite database with schema"""
        conn = sqlite3.connect(self.db_path)
        
        # Read and execute schema
        schema_sql = Path(__file__).parent / "schema.sql"
        if schema_sql.exists():
            with open(schema_sql) as f:
                conn.executescript(f.read())
        
        conn.close()
    
    async def discover_all_sources(self) -> List[FirmwareCandidate]:
        """Main discovery method - searches all configured sources"""
        candidates = []
        
        self.logger.info("🕷️ Starting firmware discovery...")
        
        # Vendor official sites
        candidates.extend(await self.discover_asus_firmware())
        candidates.extend(await self.discover_msi_firmware()) 
        candidates.extend(await self.discover_gigabyte_firmware())
        candidates.extend(await self.discover_intel_firmware())
        candidates.extend(await self.discover_amd_firmware())
        
        # BIOS vendor sites
        candidates.extend(await self.discover_ami_firmware())
        candidates.extend(await self.discover_phoenix_firmware())
        candidates.extend(await self.discover_insyde_firmware())
        
        # Mirror sites and archives
        candidates.extend(await self.discover_station_drivers())
        candidates.extend(await self.discover_bios_world())
        candidates.extend(await self.discover_archive_org())
        
        # Research/community sources
        candidates.extend(await self.discover_github_repos())
        candidates.extend(await self.discover_firmware_dumps())
        
        self.logger.info(f"📊 Discovered {len(candidates)} firmware candidates")
        return candidates

    async def discover_asus_firmware(self) -> List[FirmwareCandidate]:
        """Discover firmware from ASUS official sites"""
        candidates = []
        
        # ASUS has multiple regional sites with different firmware
        asus_sites = [
            "https://www.asus.com/support/",
            "https://www.asus.com/us/support/",
            "https://www.asus.com/uk/support/",
            "https://www.asus.com/de/support/"
        ]
        
        for site in asus_sites:
            try:
                # Search for motherboard models
                models = await self._discover_asus_models(site)
                
                for model in models:
                    firmware_list = await self._get_asus_firmware_for_model(site, model)
                    candidates.extend(firmware_list)
                    
            except Exception as e:
                self.logger.warning(f"Failed to discover ASUS firmware from {site}: {e}")
        
        return candidates
    
    async def discover_intel_firmware(self) -> List[FirmwareCandidate]:
        """Discover firmware from Intel official sources"""
        candidates = []
        
        # Intel Download Center API (if available)
        intel_api_base = "https://downloadcenter.intel.com/json/"
        
        # Intel NUC firmware
        nuc_base = "https://www.intel.com/content/www/us/en/support/articles/000005636/intel-nuc/"
        
        # Intel chipset firmware updates
        chipset_base = "https://www.intel.com/content/www/us/en/support/products/1145/chipsets/"
        
        try:
            # Query Intel's API for BIOS updates
            async with self.session.get(f"{intel_api_base}search") as resp:
                if resp.status == 200:
                    data = await resp.json()
                    candidates.extend(self._parse_intel_api_response(data))
                    
        except Exception as e:
            self.logger.warning(f"Intel API discovery failed: {e}")
        
        return candidates
    
    async def discover_github_repos(self) -> List[FirmwareCandidate]:
        """Discover firmware from GitHub repositories"""
        candidates = []
        
        # GitHub API search for firmware repositories
        github_queries = [
            "UEFI+firmware+BIOS",
            "motherboard+BIOS+update", 
            "firmware+dump+ASUS+MSI",
            "bootkit+analysis+samples",
            "coreboot+firmware"
        ]
        
        github_api = "https://api.github.com/search/repositories"
        
        for query in github_queries:
            try:
                params = {
                    'q': query,
                    'sort': 'stars',
                    'order': 'desc',
                    'per_page': 100
                }
                
                async with self.session.get(github_api, params=params) as resp:
                    if resp.status == 200:
                        data = await resp.json()
                        candidates.extend(await self._parse_github_repos(data))
                        
            except Exception as e:
                self.logger.warning(f"GitHub discovery failed for query '{query}': {e}")
        
        return candidates
    
    async def download_and_verify(self, candidate: FirmwareCandidate) -> Optional[str]:
        """Download firmware and perform initial verification"""
        
        # Generate safe filename
        safe_name = re.sub(r'[^\w\-_.]', '_', f"{candidate.vendor}_{candidate.model}_{candidate.version}")
        download_path = self.download_dir / f"{safe_name}.bin"
        
        try:
            self.logger.info(f"⬇️ Downloading {candidate.vendor} {candidate.model} {candidate.version}")
            
            async with self.session.get(candidate.url) as resp:
                if resp.status != 200:
                    self.logger.warning(f"Download failed: HTTP {resp.status}")
                    return None
                
                # Stream download to file
                with open(download_path, 'wb') as f:
                    async for chunk in resp.content.iter_chunked(8192):
                        f.write(chunk)
            
            # Verify downloaded file
            if await self._verify_firmware_file(download_path, candidate):
                return str(download_path)
            else:
                download_path.unlink()  # Delete invalid file
                return None
                
        except Exception as e:
            self.logger.error(f"Download failed for {candidate.url}: {e}")
            if download_path.exists():
                download_path.unlink()
            return None
    
    async def _verify_firmware_file(self, file_path: Path, candidate: FirmwareCandidate) -> bool:
        """Verify downloaded firmware file integrity and structure"""
        
        try:
            # Check file size (basic sanity check)
            file_size = file_path.stat().st_size
            if file_size < 1024 * 1024:  # Less than 1MB is suspicious for BIOS
                self.logger.warning(f"File too small: {file_size} bytes")
                return False
            
            if file_size > 100 * 1024 * 1024:  # Greater than 100MB is suspicious
                self.logger.warning(f"File too large: {file_size} bytes")
                return False
            
            # Calculate hashes
            hashes = await self._calculate_hashes(file_path)
            
            # Check if we already have this file
            if await self._is_duplicate_firmware(hashes['sha256']):
                self.logger.info("Duplicate firmware detected - skipping")
                return False
            
            # Basic structure validation
            if await self._validate_firmware_structure(file_path):
                # Store in database
                await self._store_firmware(file_path, candidate, hashes)
                return True
            else:
                self.logger.warning("Firmware structure validation failed")
                return False
                
        except Exception as e:
            self.logger.error(f"Verification failed: {e}")
            return False
    
    async def _calculate_hashes(self, file_path: Path) -> Dict[str, str]:
        """Calculate multiple hashes for firmware file"""
        
        hashes = {
            'md5': hashlib.md5(),
            'sha1': hashlib.sha1(), 
            'sha256': hashlib.sha256(),
            'crc32': 0
        }
        
        with open(file_path, 'rb') as f:
            while chunk := f.read(65536):  # 64KB chunks
                for hasher in ['md5', 'sha1', 'sha256']:
                    hashes[hasher].update(chunk)
        
        # Calculate CRC32
        import zlib
        with open(file_path, 'rb') as f:
            hashes['crc32'] = zlib.crc32(f.read()) & 0xffffffff
        
        return {
            'md5': hashes['md5'].hexdigest(),
            'sha1': hashes['sha1'].hexdigest(),
            'sha256': hashes['sha256'].hexdigest(), 
            'crc32': f"{hashes['crc32']:08x}"
        }
    
    async def _validate_firmware_structure(self, file_path: Path) -> bool:
        """Validate that file appears to be legitimate firmware"""
        
        with open(file_path, 'rb') as f:
            header = f.read(1024)
        
        # Check for common firmware signatures
        uefi_signatures = [
            b'_FVH',           # UEFI Firmware Volume Header
            b'$FV$',           # Alternative FV signature
            b'BIOS',           # Legacy BIOS signature
            b'\x55\xAA',       # Boot sector signature
            b'AMIBIOS',        # AMI BIOS signature  
            b'PhoenixBIOS',    # Phoenix BIOS signature
            b'Award',          # Award BIOS signature
        ]
        
        # Look for UEFI/BIOS signatures
        for signature in uefi_signatures:
            if signature in header:
                return True
        
        # Check for Intel Flash Descriptor signature
        if len(header) >= 16:
            # Intel flash descriptor has specific signature at offset 0x10
            if header[0:4] == b'\x5A\xA5\xF0\x0F':  # Flash descriptor signature
                return True
        
        # If no signatures found, it might be a compressed/encrypted image
        # Check for common compression signatures
        compression_sigs = [
            header.startswith(b'\x1f\x8b'),      # GZIP
            header.startswith(b'PK'),            # ZIP
            header.startswith(b'\x7fELF'),       # ELF (coreboot)
            header.startswith(b'\xfd7zXZ'),      # XZ compression
        ]
        
        if any(compression_sigs):
            return True
        
        self.logger.warning("No recognized firmware signatures found")
        return False
    
    async def run_discovery(self):
        """Main entry point for firmware discovery and collection"""
        
        async with aiohttp.ClientSession(
            timeout=aiohttp.ClientTimeout(total=300),  # 5 minute timeout
            headers={'User-Agent': 'PhoenixGuard-Spider/1.0'}
        ) as session:
            self.session = session
            
            # Discover all firmware candidates
            candidates = await self.discover_all_sources()
            
            # Download and verify each candidate
            successful_downloads = 0
            
            for i, candidate in enumerate(candidates):
                self.logger.info(f"Processing {i+1}/{len(candidates)}: {candidate.vendor} {candidate.model}")
                
                if await self.download_and_verify(candidate):
                    successful_downloads += 1
                
                # Rate limiting - be nice to servers
                await asyncio.sleep(1)
            
            self.logger.info(f"✅ Discovery complete: {successful_downloads}/{len(candidates)} successful downloads")

# Usage example
async def main():
    spider = FirmwareSpider("phoenixguard_firmware.db")
    await spider.run_discovery()

if __name__ == "__main__":
    asyncio.run(main())
```

## 🔍 Verification and Validation System

### Multi-Layer Verification
```python
#!/usr/bin/env python3
"""
PhoenixGuard Firmware Verification System
Multi-layer validation of firmware authenticity and integrity
"""
import subprocess
import tempfile
import json
from pathlib import Path
from cryptography import x509
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import rsa, padding

class FirmwareVerifier:
    def __init__(self):
        self.temp_dir = Path(tempfile.mkdtemp(prefix="phoenix_verify_"))
        
        # Load known vendor public keys
        self.vendor_keys = self._load_vendor_keys()
        
        # Initialize verification tools
        self.tools = {
            'uefi_tool': self._find_tool('UEFITool'),
            'binwalk': self._find_tool('binwalk'), 
            'openssl': self._find_tool('openssl'),
            'chipsec': self._find_tool('chipsec_main')
        }
    
    def verify_firmware_comprehensive(self, firmware_path: Path) -> Dict:
        """Comprehensive firmware verification"""
        
        results = {
            'file_path': str(firmware_path),
            'verification_timestamp': datetime.now().isoformat(),
            'overall_confidence': 0,
            'checks': {}
        }
        
        # Layer 1: File integrity and structure
        results['checks']['file_integrity'] = self._verify_file_integrity(firmware_path)
        
        # Layer 2: Digital signature verification
        results['checks']['digital_signature'] = self._verify_digital_signature(firmware_path)
        
        # Layer 3: UEFI structure validation  
        results['checks']['uefi_structure'] = self._verify_uefi_structure(firmware_path)
        
        # Layer 4: Content analysis
        results['checks']['content_analysis'] = self._analyze_firmware_content(firmware_path)
        
        # Layer 5: Vendor-specific validation
        results['checks']['vendor_validation'] = self._verify_vendor_specific(firmware_path)
        
        # Calculate overall confidence score
        results['overall_confidence'] = self._calculate_confidence_score(results['checks'])
        
        return results
    
    def _verify_digital_signature(self, firmware_path: Path) -> Dict:
        """Verify digital signatures in firmware"""
        
        result = {
            'verified': False,
            'signatures_found': [],
            'trusted_signatures': [],
            'details': []
        }
        
        try:
            # Use UEFITool to extract signature information
            if self.tools['uefi_tool']:
                cmd = [self.tools['uefi_tool'], str(firmware_path), '--signatures']
                proc = subprocess.run(cmd, capture_output=True, text=True)
                
                if proc.returncode == 0:
                    # Parse UEFITool output for signatures
                    signatures = self._parse_uefi_signatures(proc.stdout)
                    result['signatures_found'] = signatures
            
            # Use chipsec for additional signature analysis
            if self.tools['chipsec']:
                chipsec_result = self._run_chipsec_signature_check(firmware_path)
                result['details'].append(chipsec_result)
            
            # Verify against known vendor keys
            for signature in result['signatures_found']:
                if self._verify_signature_against_vendors(signature):
                    result['trusted_signatures'].append(signature)
            
            result['verified'] = len(result['trusted_signatures']) > 0
            
        except Exception as e:
            result['details'].append(f"Signature verification failed: {e}")
        
        return result
    
    def _verify_uefi_structure(self, firmware_path: Path) -> Dict:
        """Validate UEFI firmware structure"""
        
        result = {
            'valid_structure': False,
            'firmware_volumes': [],
            'modules_found': [],
            'issues': []
        }
        
        try:
            if self.tools['uefi_tool']:
                # Extract firmware structure
                cmd = [self.tools['uefi_tool'], str(firmware_path), '--extract', str(self.temp_dir)]
                proc = subprocess.run(cmd, capture_output=True, text=True)
                
                if proc.returncode == 0:
                    # Analyze extracted structure
                    result = self._analyze_extracted_uefi(self.temp_dir, result)
                else:
                    result['issues'].append(f"UEFITool extraction failed: {proc.stderr}")
            
            # Additional binwalk analysis
            if self.tools['binwalk']:
                binwalk_result = self._run_binwalk_analysis(firmware_path)
                result['binwalk_analysis'] = binwalk_result
            
        except Exception as e:
            result['issues'].append(f"UEFI structure verification failed: {e}")
        
        return result
    
    def _analyze_firmware_content(self, firmware_path: Path) -> Dict:
        """Analyze firmware content for suspicious elements"""
        
        result = {
            'suspicious_strings': [],
            'embedded_executables': [],
            'entropy_analysis': {},
            'risk_score': 0
        }
        
        try:
            with open(firmware_path, 'rb') as f:
                content = f.read()
            
            # String analysis
            suspicious_patterns = [
                rb'backdoor', rb'keylogger', rb'trojan',
                rb'rootkit', rb'malware', rb'virus',
                rb'payload', rb'exploit', rb'shellcode',
                rb'debug', rb'test', rb'bypass'
            ]
            
            for pattern in suspicious_patterns:
                if pattern in content.lower():
                    result['suspicious_strings'].append(pattern.decode('utf-8', errors='ignore'))
            
            # Entropy analysis (detect encrypted/compressed regions)
            result['entropy_analysis'] = self._calculate_entropy_distribution(content)
            
            # Look for embedded executables
            result['embedded_executables'] = self._find_embedded_executables(content)
            
            # Calculate risk score based on findings
            result['risk_score'] = len(result['suspicious_strings']) * 10 + \
                                  len(result['embedded_executables']) * 5
            
        except Exception as e:
            result['error'] = f"Content analysis failed: {e}"
        
        return result
    
    def _load_vendor_keys(self) -> Dict:
        """Load known vendor public keys for signature verification"""
        
        # This would load actual vendor public keys
        # For now, return placeholder structure
        return {
            'ASUS': [],
            'MSI': [],
            'GIGABYTE': [],
            'Intel': [],
            'AMD': [],
            'AMI': [],
            'Phoenix': [],
            'Insyde': []
        }

# Integration with database
class FirmwareDatabaseManager:
    def __init__(self, db_path: str):
        self.db_path = db_path
        self.verifier = FirmwareVerifier()
    
    def import_and_verify_firmware(self, firmware_path: Path, metadata: Dict) -> bool:
        """Import firmware into database with full verification"""
        
        # Perform comprehensive verification
        verification_result = self.verifier.verify_firmware_comprehensive(firmware_path)
        
        # Only import if confidence score is high enough
        if verification_result['overall_confidence'] >= 70:
            return self._store_verified_firmware(firmware_path, metadata, verification_result)
        else:
            logging.warning(f"Firmware confidence too low: {verification_result['overall_confidence']}")
            return False
    
    def query_firmware_for_hardware(self, device_id: str, subsystem_id: str) -> List[Dict]:
        """Query database for firmware matching specific hardware"""
        
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        query = """
        SELECT f.*, h.compatibility_score
        FROM firmware_images f
        JOIN hardware_mappings h ON f.id = h.firmware_id
        WHERE h.device_id = ? AND h.subsystem_id = ?
        ORDER BY f.confidence_score DESC, h.compatibility_score DESC
        """
        
        cursor.execute(query, (device_id, subsystem_id))
        results = cursor.fetchall()
        conn.close()
        
        return [dict(zip([col[0] for col in cursor.description], row)) for row in results]
```

## 🚀 Deployment Strategy

### Containerized Database Service
```dockerfile
# Dockerfile for PhoenixGuard Firmware Database Service
FROM fedora:latest

RUN dnf update -y && \
    dnf install -y python3 python3-pip postgresql postgresql-server \
    openssl binwalk sqlite3 && \
    dnf clean all

# Install Python dependencies
COPY requirements.txt /app/
RUN pip3 install -r /app/requirements.txt

# Copy application
COPY firmware_spider.py firmware_verifier.py /app/
COPY schema.sql /app/

# Setup database
RUN postgresql-setup --initdb
USER postgres
RUN /usr/bin/pg_ctl start -D /var/lib/pgsql/data -s -o "-p 5432" -w -t 300 && \
    /usr/bin/createdb firmware_db && \
    /usr/bin/psql firmware_db < /app/schema.sql

EXPOSE 5432 8080

CMD ["python3", "/app/firmware_spider.py", "--daemon"]
```

### Continuous Collection Service
```python
#!/usr/bin/env python3
"""
PhoenixGuard Firmware Collection Service
Runs continuously to discover and collect new firmware
"""
import asyncio
import schedule
import time
from firmware_spider import FirmwareSpider

class ContinuousFirmwareCollector:
    def __init__(self):
        self.spider = FirmwareSpider()
        
    def schedule_collections(self):
        """Schedule regular firmware collection runs"""
        
        # Daily comprehensive scan
        schedule.every().day.at("02:00").do(self.run_full_collection)
        
        # Weekly vendor-specific scans
        schedule.every().monday.at("10:00").do(self.run_vendor_scan, "ASUS")
        schedule.every().tuesday.at("10:00").do(self.run_vendor_scan, "MSI") 
        schedule.every().wednesday.at("10:00").do(self.run_vendor_scan, "Intel")
        
        # Monthly archive scans
        schedule.every().month.do(self.run_archive_scan)
    
    def run_full_collection(self):
        """Run complete firmware discovery and collection"""
        asyncio.run(self.spider.run_discovery())
    
    async def main_loop(self):
        """Main service loop"""
        self.schedule_collections()
        
        while True:
            schedule.run_pending()
            await asyncio.sleep(60)  # Check every minute

if __name__ == "__main__":
    collector = ContinuousFirmwareCollector()
    asyncio.run(collector.main_loop())
```

This comprehensive firmware database strategy provides PhoenixGuard with:

1. **Automated Discovery** - Continuously finds new firmware from multiple sources
2. **Multi-Layer Verification** - Ensures only legitimate firmware is stored
3. **Hardware Mapping** - Links firmware to specific hardware configurations
4. **Confidence Scoring** - Prioritizes most trusted firmware sources
5. **Scalable Architecture** - Can handle enterprise-scale deployment

The system is designed to be **self-maintaining** and **continuously learning**, building a comprehensive knowledge base that makes PhoenixGuard more effective over time.

<citations>
<document>
    <document_type>RULE</document_type>
    <document_id>BrmerD7AwcAOR2yliMUvBz</document_id>
</document>
<document>
    <document_type>RULE</document_type>
    <document_id>kL1u5uLf2nW8qAvLGJLHQF</document_id>
</document>
<document>
    <document_type>RULE</document_type>
    <document_id>dZtOmTXPCPzFrMXbrX0U9o</document_id>
</document>
<document>
    <document_type>RULE</document_type>
    <document_id>qWu5DH0qJYmsaWbb0u7VGj</document_id>
</document>
</citations>
