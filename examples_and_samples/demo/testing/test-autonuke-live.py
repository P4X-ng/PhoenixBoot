#!/usr/bin/env python3
"""
Live AUTONUKE Test - Real Hardware with Simulated Bootkit
=========================================================

This version runs AUTONUKE on real hardware but uses our simulated
bootkit results to test the full escalation ladder. Perfect for
demonstrating the complete recovery workflow safely.
"""

import sys
import json
from pathlib import Path

# Add current directory to path
sys.path.insert(0, str(Path(__file__).parent))

from autonuke import AutoNuke, Colors

class LiveTestAutoNuke(AutoNuke):
    """Live test version that uses simulated bootkit results"""
    
    def level_1_scan(self):
        """Level 1: Use our simulated bootkit scan results"""
        self.log("🔍 LEVEL 1: Starting bootkit detection scan...")
        
        if not self.confirm_action("🔍 Run comprehensive bootkit scan?", "LOW"):
            return False
        
        # Use the existing simulated results file
        scan_results_file = self.project_root / "bootkit_scan_results.json"
        if scan_results_file.exists():
            with open(scan_results_file, 'r') as f:
                results = json.load(f)
            
            if results.get('threats_detected') and results.get('detected_threats'):
                self.log("⚠️  CRITICAL BOOTKIT INFECTION DETECTED!", "WARNING")
                print(f"\n{self.Colors.RED}🚨 CRITICAL BOOTKIT THREATS DETECTED:{self.Colors.END}")
                for threat in results.get('detected_threats', []):
                    print(f"  • {threat}")
                print(f"\n{self.Colors.RED}Risk Level: {results.get('risk_level', 'UNKNOWN')}{self.Colors.END}")
                print(f"{self.Colors.YELLOW}Confidence: {results.get('infection_confidence', 'N/A')}{self.Colors.END}")
                return False  # Escalate immediately
            else:
                self.log("✅ No immediate threats detected", "SUCCESS")
                print(f"{self.Colors.GREEN}✅ System appears clean at software level{self.Colors.END}")
                return True
        else:
            self.log("❌ No scan results file found", "ERROR")
            return False

def main():
    """Run live AUTONUKE test with simulated bootkit"""
    print(f"""
{Colors.RED}{Colors.BOLD}🚨 LIVE AUTONUKE TEST - SIMULATED BOOTKIT ATTACK 🚨{Colors.END}

{Colors.YELLOW}This test uses REAL hardware recovery methods but with simulated
bootkit detection results to safely test the full escalation ladder.{Colors.END}

{Colors.CYAN}Expected behavior:{Colors.END}
  1. Detect simulated CRITICAL bootkit infection  
  2. Escalate to SOFT level (ESP Nuclear Boot ISO)
  3. Escalate to HARD level (Hardware firmware recovery)
  4. Show NUKE level (CH341A programmer instructions)

{Colors.RED}⚠️  This will execute REAL recovery commands on your system!{Colors.END}
""")
    
    confirm = input(f"{Colors.BOLD}Ready to test full escalation? [y/N]: {Colors.END}").strip()
    if confirm.lower() not in ['y', 'yes']:
        print("Test cancelled.")
        return
    
    # Create and run live test version
    autonuke = LiveTestAutoNuke()
    autonuke.run_recovery()

if __name__ == "__main__":
    main()
