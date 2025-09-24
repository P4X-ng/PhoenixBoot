#!/usr/bin/env python3
"""
PhoenixGuard Kernel Module Signing Tool (pgmodsign)
Part of the edk2-bootkit-defense project

Signs kernel modules using PhoenixGuard certificates for SecureBoot compliance.
Leverages the Linux kernel's scripts/sign-file utility.
"""

from __future__ import annotations

import os
import sys
import json
import logging
import subprocess
import hashlib
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Any, Optional
import traceback

# Resolve repo root (assumes this file lives in <repo>/utils/)
REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUT_DIR = REPO_ROOT / "out" / "keys" / "mok"
DEFAULT_CERT = DEFAULT_OUT_DIR / "PGMOK.crt"
DEFAULT_KEY = DEFAULT_OUT_DIR / "PGMOK.key"


def _choose_log_file() -> Path:
    """Select a writable log path with sensible fallbacks."""
    candidates = [
        Path("/var/log/phoenixguard/module_signing.log"),
        REPO_ROOT / "out" / "logs" / "module_signing.log",
        Path.home() / ".local/share/phoenixguard/module_signing.log",
    ]
    for p in candidates:
        try:
            p.parent.mkdir(parents=True, exist_ok=True)
            # Touch to test writability
            with open(p, "a"):
                pass
            return p
        except Exception:
            continue
    # Last resort: stdout only
    return None  # type: ignore


_log_path = _choose_log_file()
_handlers: List[logging.Handler] = [logging.StreamHandler(sys.stdout)]
if _log_path is not None:
    _handlers.insert(0, logging.FileHandler(str(_log_path)))

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - [%(filename)s:%(lineno)d] - %(message)s",
    handlers=_handlers,
)
logger = logging.getLogger(__name__)


class PhoenixGuardModuleSigner:
    def __init__(self, cert_path: Optional[str] = None, key_path: Optional[str] = None):
        # Allow env override, then CLI, then defaults
        env_cert = os.environ.get("KMOD_CERT") or os.environ.get("PG_KMOD_CERT")
        env_key = os.environ.get("KMOD_KEY") or os.environ.get("PG_KMOD_KEY")
        self.cert_path = str(Path(cert_path or env_cert or DEFAULT_CERT))
        self.key_path = str(Path(key_path or env_key or DEFAULT_KEY))

        rel = os.uname().release
        self.sign_file_candidates = [
            f"/usr/src/linux-headers-{rel}/scripts/sign-file",
            f"/lib/modules/{rel}/build/scripts/sign-file",
            f"/usr/src/kernels/{rel}/scripts/sign-file",
        ]
        self.signing_log: List[Dict[str, Any]] = []

        # Pre-resolve certificate paths
        self.cert_file = Path(self.cert_path)
        self.key_file = Path(self.key_path)

    def run_command(self, cmd: List[str], check: bool = True) -> subprocess.CompletedProcess:
        """Run a command with logging (no shell)."""
        logger.debug("Executing command: %s", " ".join(cmd))
        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                check=check,
                timeout=60,
            )
            if result.stdout:
                logger.debug("STDOUT: %s", result.stdout)
            if result.stderr:
                logger.debug("STDERR: %s", result.stderr)
            return result
        except subprocess.CalledProcessError as e:
            logger.error("Command failed (%s): %s", e.returncode, " ".join(cmd))
            logger.error("STDERR: %s", e.stderr)
            raise
        except subprocess.TimeoutExpired:
            logger.error("Command timed out after 60 seconds: %s", " ".join(cmd))
            raise

    def find_sign_file_utility(self) -> Optional[str]:
        """Locate the kernel's sign-file utility."""
        logger.info("Searching for sign-file utility")
        for p in self.sign_file_candidates:
            if Path(p).exists():
                logger.info("Found sign-file utility: %s", p)
                return p
        # Fallback search
        try:
            result = self.run_command([
                "bash", "-lc",
                "find /usr/src /lib/modules -maxdepth 4 -type f -name sign-file 2>/dev/null | head -1",
            ], check=False)
            found = result.stdout.strip()
            if found:
                logger.info("Found sign-file utility via search: %s", found)
                return found
        except Exception:
            pass
        logger.error("Could not locate sign-file utility")
        return None

    @staticmethod
    def calculate_module_hash(module_path: str) -> str:
        """Calculate SHA256 hash of a module file."""
        h = hashlib.sha256()
        with open(module_path, "rb") as f:
            for chunk in iter(lambda: f.read(8192), b""):
                h.update(chunk)
        return h.hexdigest()

    def is_module_signed(self, module_path: str) -> bool:
        """Heuristic: modinfo fields present => signed."""
        try:
            result = self.run_command(["modinfo", "-F", "sig_id", module_path], check=False)
            return bool(result.stdout.strip())
        except Exception as e:
            logger.warning("Could not determine signature status for %s: %s", module_path, e)
            return False

    def sign_kernel_module(self, module_path: str, hash_algo: str = "sha256", force: bool = False) -> Dict[str, Any]:
        """Sign a kernel module with the configured certificate/key."""
        module = Path(module_path).resolve()
        if not module.exists():
            raise FileNotFoundError(f"Module file not found: {module}")
        if module.suffix != ".ko":
            raise ValueError(f"Not a kernel module (.ko): {module}")
        if not Path(self.cert_path).exists():
            raise FileNotFoundError(f"Signing cert not found: {self.cert_path}")
        if not Path(self.key_path).exists():
            raise FileNotFoundError(f"Signing key not found: {self.key_path}")

        logger.info("Starting module signing: %s", module)
        if not force and self.is_module_signed(str(module)):
            logger.info("Already signed; skipping (use --force to re-sign)")
            return {
                "status": "skipped",
                "reason": "already_signed",
                "module_path": str(module),
                "timestamp": datetime.now().isoformat(),
            }

        sign_file = self.find_sign_file_utility()
        if not sign_file:
            raise RuntimeError("Could not locate sign-file utility")

        pre_hash = self.calculate_module_hash(str(module))

        # Backup original
        backup_path = module.with_suffix(".ko.unsigned")
        if not backup_path.exists():
            import shutil
            shutil.copy2(module, backup_path)
            logger.info("Created backup: %s", backup_path)

        cmd = [sign_file, hash_algo, self.key_path, self.cert_path, str(module)]
        try:
            self.run_command(cmd)
            post_hash = self.calculate_module_hash(str(module))
            if self.is_module_signed(str(module)):
                result = {
                    "status": "success",
                    "module_path": str(module),
                    "certificate_used": self.cert_path,
                    "private_key_used": self.key_path,
                    "hash_algorithm": hash_algo,
                    "pre_signing_hash": pre_hash,
                    "post_signing_hash": post_hash,
                    "backup_created": str(backup_path),
                    "timestamp": datetime.now().isoformat(),
                    "sign_file_utility": sign_file,
                    "command_executed": " ".join(cmd),
                }
                logger.info("✅ Module signed successfully")
            else:
                result = {
                    "status": "failed",
                    "reason": "signature_not_detected",
                    "module_path": str(module),
                    "timestamp": datetime.now().isoformat(),
                }
                logger.error("❌ Module signing failed - signature not detected")
        except Exception as e:
            result = {
                "status": "error",
                "error": str(e),
                "module_path": str(module),
                "timestamp": datetime.now().isoformat(),
            }
            logger.error("❌ Module signing error: %s", e)

        self.signing_log.append(result)
        return result

    def sign_multiple_modules(self, module_paths: List[str], **kwargs) -> List[Dict[str, Any]]:
        results: List[Dict[str, Any]] = []
        logger.info("Batch signing %d module(s)", len(module_paths))
        for m in module_paths:
            try:
                results.append(self.sign_kernel_module(m, **kwargs))
            except Exception as e:
                results.append({
                    "status": "error",
                    "error": str(e),
                    "module_path": m,
                    "timestamp": datetime.now().isoformat(),
                })
                logger.error("Failed to sign %s: %s", m, e)
        ok = len([r for r in results if r.get("status") == "success"])
        logger.info("Batch complete: %d/%d signed", ok, len(module_paths))
        return results

    def save_signing_log(self, output_file: Optional[str] = None) -> str:
        if not output_file:
            ts = datetime.now().strftime("%Y%m%d_%H%M%S")
            if _log_path is not None and _log_path.parent.exists():
                output_file = str(_log_path.parent / f"module_signing_log_{ts}.json")
            else:
                output_file = str(REPO_ROOT / "out" / "logs" / f"module_signing_log_{ts}.json")
        Path(output_file).parent.mkdir(parents=True, exist_ok=True)
        data = {
            "signing_session": {
                "timestamp": datetime.now().isoformat(),
                "total_operations": len(self.signing_log),
                "successful_signings": len([r for r in self.signing_log if r.get("status") == "success"]),
                "failed_signings": len([r for r in self.signing_log if r.get("status") == "failed"]),
                "errors": len([r for r in self.signing_log if r.get("status") == "error"]),
            },
            "signing_events": self.signing_log,
            "environment": {
                "hostname": os.uname().nodename,
                "kernel_version": os.uname().release,
                "architecture": os.uname().machine,
            },
        }
        with open(output_file, "w") as f:
            json.dump(data, f, indent=2, sort_keys=True)
        logger.info("Signing log saved: %s", output_file)
        return output_file


def main() -> int:
    """CLI entry point."""
    import argparse

    parser = argparse.ArgumentParser(
        description="PhoenixGuard Kernel Module Signing Tool",
        epilog=(
            "Examples:\n"
            "  pgmodsign module.ko                    # Sign single module\n"
            "  pgmodsign *.ko                         # Sign all .ko files\n"
            "  pgmodsign --force module.ko            # Re-sign already signed module\n"
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("modules", nargs="+", help="Kernel module files to sign (.ko)")
    parser.add_argument("--cert-path", help="Path to signing certificate (PEM)")
    parser.add_argument("--key-path", help="Path to signing private key (PEM)")
    parser.add_argument(
        "--hash-algo",
        default="sha256",
        choices=["sha1", "sha224", "sha256", "sha384", "sha512"],
        help="Hash algorithm for signing (default: sha256)",
    )
    parser.add_argument("--force", "-f", action="store_true", help="Force re-signing of already signed modules")
    parser.add_argument("--verbose", "-v", action="store_true", help="Verbose logging")
    parser.add_argument("--output", "-o", help="Output log file path")

    args = parser.parse_args()

    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)

    try:
        signer = PhoenixGuardModuleSigner(args.cert_path, args.key_path)

        # Expand globs
        module_files: List[str] = []
        for pattern in args.modules:
            path_obj = Path(pattern)
            if path_obj.is_absolute():
                module_files.append(pattern)
            else:
                p = list(Path(".").glob(pattern))
                if p:
                    module_files.extend([str(x) for x in p if x.suffix == ".ko"])
                else:
                    module_files.append(pattern)

        if not module_files:
            logger.error("No kernel module files specified")
            return 1

        if len(module_files) == 1:
            results = [
                signer.sign_kernel_module(
                    module_files[0], hash_algo=args.hash_algo, force=args.force
                )
            ]
        else:
            results = signer.sign_multiple_modules(module_files, hash_algo=args.hash_algo, force=args.force)

        log_file = signer.save_signing_log(args.output)

        successful = len([r for r in results if r.get("status") == "success"])
        skipped = len([r for r in results if r.get("status") == "skipped"])
        failed = len([r for r in results if r.get("status") in ("failed", "error")])

        print("\n📊 Signing Summary:")
        print(f"  ✅ Successfully signed: {successful}")
        print(f"  ⏭️  Skipped (already signed): {skipped}")
        print(f"  ❌ Failed: {failed}")
        print(f"  📄 Log file: {log_file}")

        if failed:
            print("\n❌ Some modules failed to sign:")
            for r in results:
                if r.get("status") in ("failed", "error"):
                    mod = Path(r.get("module_path", "?"))
                    print(f"  • {mod.name}: {r.get('error', r.get('reason', 'Unknown error'))}")

        return 0 if not failed else 1

    except Exception as e:
        logger.error("Module signing failed: %s", e)
        logger.error(traceback.format_exc())
        return 1


if __name__ == "__main__":
    sys.exit(main())
