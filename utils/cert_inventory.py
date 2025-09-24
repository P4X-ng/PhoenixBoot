#!/usr/bin/env python3
"""
PhoenixGuard Certificate Inventory Tool
Part of the edk2-bootkit-defense project

Scans and prepares PhoenixGuard SecureBoot certificates for kernel module signing.
Converts certificates to PEM format and provides certificate metadata.
"""

import os
import sys
import json
import logging
import subprocess
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Any, Optional

# Set up logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/log/phoenixguard/cert_inventory.log'),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

class PhoenixGuardCertInventory:
    def __init__(self, cert_dir: str = None):
        self.cert_dir = cert_dir or "/home/punk/Projects/edk2-bootkit-defense/PhoenixGuard/secureboot_certs"
        self.cert_data = {}
        self.conversion_log = []
        
        # Ensure log directory exists
        os.makedirs("/var/log/phoenixguard", exist_ok=True)
        
    def run_command(self, cmd: str, check: bool = True) -> subprocess.CompletedProcess:
        """Run shell command with logging"""
        logger.info(f"Running command: {cmd}")
        try:
            result = subprocess.run(cmd, shell=True, capture_output=True, text=True, check=check)
            if result.stdout:
                logger.debug(f"STDOUT: {result.stdout}")
            if result.stderr:
                logger.debug(f"STDERR: {result.stderr}")
            return result
        except subprocess.CalledProcessError as e:
            logger.error(f"Command failed with exit code {e.returncode}: {e.stderr}")
            raise
    
    def scan_certificates(self) -> Dict[str, Any]:
        """Scan the certificate directory and catalog all certificates"""
        logger.info(f"Scanning certificate directory: {self.cert_dir}")
        
        if not Path(self.cert_dir).exists():
            logger.error(f"Certificate directory not found: {self.cert_dir}")
            return {}
        
        cert_files = {
            'private_keys': [],
            'certificates': [],
            'auth_files': [],
            'der_files': [],
            'pem_files': [],
            'other_files': []
        }
        
        # Scan directory
        for file_path in Path(self.cert_dir).iterdir():
            if not file_path.is_file():
                continue
                
            file_ext = file_path.suffix.lower()
            file_name = file_path.name
            
            if file_ext in ['.key', '.pem'] and 'key' in file_name.lower():
                cert_files['private_keys'].append(str(file_path))
            elif file_ext in ['.crt', '.cert', '.pem']:
                cert_files['certificates'].append(str(file_path))
            elif file_ext == '.der':
                cert_files['der_files'].append(str(file_path))
            elif file_ext == '.auth':
                cert_files['auth_files'].append(str(file_path))
            elif file_ext == '.esl':
                cert_files['other_files'].append(str(file_path))
            else:
                cert_files['other_files'].append(str(file_path))
        
        logger.info(f"Found {len(cert_files['certificates'])} certificates, "
                   f"{len(cert_files['private_keys'])} private keys, "
                   f"{len(cert_files['der_files'])} DER files")
        
        return cert_files
    
    def convert_der_to_pem(self, der_file: str) -> Optional[str]:
        """Convert DER certificate to PEM format"""
        der_path = Path(der_file)
        pem_path = der_path.with_suffix('.pem')
        
        if pem_path.exists():
            logger.info(f"PEM file already exists: {pem_path}")
            return str(pem_path)
        
        try:
            cmd = f"openssl x509 -inform der -in '{der_file}' -outform pem -out '{pem_path}'"
            self.run_command(cmd)
            
            self.conversion_log.append({
                'timestamp': datetime.now().isoformat(),
                'source': der_file,
                'target': str(pem_path),
                'status': 'success'
            })
            
            logger.info(f"Converted DER to PEM: {der_file} -> {pem_path}")
            return str(pem_path)
            
        except Exception as e:
            logger.error(f"Failed to convert {der_file} to PEM: {e}")
            self.conversion_log.append({
                'timestamp': datetime.now().isoformat(),
                'source': der_file,
                'target': str(pem_path),
                'status': 'failed',
                'error': str(e)
            })
            return None
    
    def extract_cert_info(self, cert_file: str) -> Dict[str, Any]:
        """Extract certificate information using OpenSSL"""
        try:
            # Determine input format
            file_ext = Path(cert_file).suffix.lower()
            inform = 'der' if file_ext == '.der' else 'pem'
            
            # Get certificate text info
            cmd = f"openssl x509 -inform {inform} -in '{cert_file}' -text -noout"
            result = self.run_command(cmd)
            cert_text = result.stdout
            
            # Get subject
            cmd = f"openssl x509 -inform {inform} -in '{cert_file}' -subject -noout"
            result = self.run_command(cmd)
            subject = result.stdout.strip().replace('subject=', '')
            
            # Get issuer
            cmd = f"openssl x509 -inform {inform} -in '{cert_file}' -issuer -noout"
            result = self.run_command(cmd)
            issuer = result.stdout.strip().replace('issuer=', '')
            
            # Get fingerprint
            cmd = f"openssl x509 -inform {inform} -in '{cert_file}' -fingerprint -noout"
            result = self.run_command(cmd)
            fingerprint = result.stdout.strip().replace('SHA1 Fingerprint=', '')
            
            # Get validity dates
            cmd = f"openssl x509 -inform {inform} -in '{cert_file}' -dates -noout"
            result = self.run_command(cmd)
            dates = result.stdout.strip()
            
            return {
                'file_path': cert_file,
                'format': inform,
                'subject': subject,
                'issuer': issuer,
                'fingerprint': fingerprint,
                'validity': dates,
                'text_dump': cert_text,
                'scan_time': datetime.now().isoformat()
            }
            
        except Exception as e:
            logger.error(f"Failed to extract info from {cert_file}: {e}")
            return {
                'file_path': cert_file,
                'error': str(e),
                'scan_time': datetime.now().isoformat()
            }
    
    def inventory_all_certificates(self) -> Dict[str, Any]:
        """Complete certificate inventory with conversion and analysis"""
        logger.info("Starting complete certificate inventory")
        
        # Scan files
        cert_files = self.scan_certificates()
        
        # Convert DER files to PEM
        converted_files = []
        for der_file in cert_files['der_files']:
            pem_file = self.convert_der_to_pem(der_file)
            if pem_file:
                converted_files.append(pem_file)
                cert_files['pem_files'].append(pem_file)
        
        # Extract info from all certificate files
        certificate_info = []
        all_cert_files = cert_files['certificates'] + cert_files['pem_files']
        
        for cert_file in all_cert_files:
            if cert_file not in [info.get('file_path') for info in certificate_info]:
                cert_info = self.extract_cert_info(cert_file)
                certificate_info.append(cert_info)
        
        # Identify signing keys and certificates
        signing_candidates = []
        for cert_info in certificate_info:
            subject = cert_info.get('subject', '')
            if 'phoenixguard' in subject.lower():
                # Look for corresponding private key
                cert_path = Path(cert_info['file_path'])
                possible_key_paths = [
                    cert_path.with_suffix('.key'),
                    cert_path.parent / f"{cert_path.stem}_key.pem",
                    cert_path.parent / "user_secureboot.key"
                ]
                
                for key_path in possible_key_paths:
                    if key_path.exists():
                        signing_candidates.append({
                            'certificate': cert_info['file_path'],
                            'private_key': str(key_path),
                            'subject': subject,
                            'fingerprint': cert_info.get('fingerprint', ''),
                            'suitable_for_signing': True
                        })
                        break
        
        # Compile final inventory
        inventory = {
            'scan_info': {
                'timestamp': datetime.now().isoformat(),
                'cert_directory': self.cert_dir,
                'total_files_scanned': sum(len(files) for files in cert_files.values()),
            },
            'file_catalog': cert_files,
            'certificate_details': certificate_info,
            'signing_candidates': signing_candidates,
            'conversion_log': self.conversion_log,
            'recommendations': self._generate_recommendations(signing_candidates)
        }
        
        logger.info(f"Inventory complete: {len(certificate_info)} certificates analyzed, "
                   f"{len(signing_candidates)} signing candidates found")
        
        return inventory
    
    def _generate_recommendations(self, signing_candidates: List[Dict]) -> List[str]:
        """Generate recommendations based on certificate analysis"""
        recommendations = []
        
        if not signing_candidates:
            recommendations.append("No suitable signing certificates found. Generate PhoenixGuard signing keys.")
        elif len(signing_candidates) == 1:
            recommendations.append("Single signing certificate found - good for consistent module signing.")
        else:
            recommendations.append(f"Multiple signing certificates found ({len(signing_candidates)}). "
                                 "Consider using the most recent for module signing.")
        
        return recommendations
    
    def save_inventory(self, inventory: Dict, output_file: str = None) -> str:
        """Save inventory to JSON file"""
        if not output_file:
            timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
            output_file = f"/home/punk/Projects/edk2-bootkit-defense/PhoenixGuard/cert_inventory_{timestamp}.json"
        
        with open(output_file, 'w') as f:
            json.dump(inventory, f, indent=2, sort_keys=True)
        
        logger.info(f"Certificate inventory saved to: {output_file}")
        return output_file

def main():
    """Main entry point"""
    import argparse
    
    parser = argparse.ArgumentParser(description='PhoenixGuard Certificate Inventory Tool')
    parser.add_argument('--cert-dir', help='Certificate directory path')
    parser.add_argument('--output', '-o', help='Output JSON file path')
    parser.add_argument('--verbose', '-v', action='store_true', help='Verbose logging')
    
    args = parser.parse_args()
    
    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)
    
    try:
        inventory_tool = PhoenixGuardCertInventory(args.cert_dir)
        inventory = inventory_tool.inventory_all_certificates()
        output_file = inventory_tool.save_inventory(inventory, args.output)
        
        print(f"✅ Certificate inventory completed successfully")
        print(f"📄 Results saved to: {output_file}")
        print(f"🔑 Found {len(inventory['signing_candidates'])} signing candidates")
        
        # Print signing candidates
        if inventory['signing_candidates']:
            print("\n🔐 Available signing certificates:")
            for i, candidate in enumerate(inventory['signing_candidates'], 1):
                print(f"  {i}. {Path(candidate['certificate']).name}")
                print(f"     Subject: {candidate['subject']}")
                print(f"     Key: {Path(candidate['private_key']).name}")
                print()
        
        return 0
        
    except Exception as e:
        logger.error(f"Certificate inventory failed: {e}")
        return 1

if __name__ == '__main__':
    sys.exit(main())
