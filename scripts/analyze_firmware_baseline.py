#!/usr/bin/env python3
"""
Minimal production baseline analyzer

Creates a firmware baseline JSON from a provided firmware image. This is a
fallback analyzer to enable scanning even when a richer analyzer is not
available. It records file metadata and a small set of text patterns.

Usage:
  python3 scripts/analyze_firmware_baseline.py <firmware.bin> -o out/baseline/firmware_baseline.json
"""
import argparse
import hashlib
import json
import os
import sys
from datetime import datetime


def sha256_file(path: str) -> str:
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def guess_bios_version(path: str) -> str:
    # Minimal heuristic: try to detect version-like substrings in the filename
    base = os.path.basename(path)
    for token in base.replace('.', '_').split('_'):
        if any(c.isdigit() for c in token) and any(c.isalpha() for c in token):
            return token
    return "unknown"


def main() -> int:
    ap = argparse.ArgumentParser(description='Create firmware baseline JSON')
    ap.add_argument('firmware', help='Path to clean firmware image')
    ap.add_argument('-o', '--output', default='out/baseline/firmware_baseline.json', help='Output JSON path')
    args = ap.parse_args()

    fw_path = os.path.abspath(args.firmware)
    if not os.path.exists(fw_path):
        print(f"ERROR: firmware not found: {fw_path}", file=sys.stderr)
        return 1

    os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)

    baseline = {
        "metadata": {
            "created_utc": datetime.utcnow().isoformat() + "Z",
            "firmware_file": fw_path,
            "firmware_sha256": sha256_file(fw_path),
            "firmware_size": os.path.getsize(fw_path),
            "bios_version": guess_bios_version(fw_path),
            "generator": "scripts/analyze_firmware_baseline.py"
        },
        # Minimal pattern set; extend as needed or replaced by richer analyzer
        "bootkit_indicators": {
            "suspicious_patterns": [
                "bootkit", "rootkit", "backdoor", "hook", "infect", "smram", "smm"
            ]
        }
    }

    with open(args.output, 'w') as f:
        json.dump(baseline, f, indent=2)

    print(f"Baseline written: {args.output}")
    return 0


if __name__ == '__main__':
    sys.exit(main())
