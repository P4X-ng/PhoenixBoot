#!/usr/bin/env python3
import argparse
import json
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser(description="Verify manifest signature and echo key fields")
parser.add_argument('--manifest', required=True)
parser.add_argument('--signature', required=True)
parser.add_argument('--pubkey', required=True)
parser.add_argument('--print', action='store_true', help='Print the parsed manifest JSON on success')
args = parser.parse_args()

man = Path(args.manifest)
sig = Path(args.signature)
pub = Path(args.pubkey)

if not man.exists() or not sig.exists() or not pub.exists():
    raise SystemExit("manifest/signature/pubkey not found")

# Use openssl to verify signature over the manifest
res = subprocess.run([
    'openssl','dgst','-sha256','-verify',str(pub),'-signature',str(sig),str(man)
], capture_output=True, text=True)
if res.returncode != 0:
    print(res.stdout + res.stderr)
    raise SystemExit(3)

with man.open() as f:
    doc = json.load(f)

# Basic sanity checks
for k in ('sha256','size_bytes'):
    if k not in doc:
        raise SystemExit(f"manifest missing field: {k}")

if args.print:
    print(json.dumps(doc))
