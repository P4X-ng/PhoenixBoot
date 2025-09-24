#!/usr/bin/env python3
"""
AUTONUKE Interactive Test
========================

Quick interactive testing script for validating AUTONUKE workflow
without needing a full VM setup. This simulates various scenarios
and user interactions to test the complete escalation ladder.

Usage:
    python3 test-autonuke-interactive.py [scenario]

Scenarios:
    clean       - System appears clean (should stop at SCAN level)
    infected    - System shows bootkit infection (escalates to SOFT)
    locked      - Firmware is locked by bootkit (escalates to HARD)  
    nuclear     - Everything fails, needs CH341A (escalates to NUKE)
    full        - Interactive test allowing user to control escalation
"""

import sys
import os
import tempfile
import json
from pathlib import Path

# Add the current directory to path so we can import autonuke
sys.path.insert(0, str(Path(__file__).parent))

from autonuke import AutoNuke, Colors

class MockAutoNuke(AutoNuke):
    """Mock version of AutoNuke for testing different scenarios"""
    
    def __init__(self, scenario="full"):
        super().__init__()
        self.scenario = scenario
        self.log(f"🧪 Testing scenario: {scenario.upper()}", "INFO")
        
    def run_command(self, cmd, shell=True):
        """Mock command runner that simulates different scenarios"""
        self.log(f"[MOCK] Would execute: {cmd}")
        
        # Simulate different scenarios based on the test mode
        if "make scan-bootkits" in cmd:
            return self._mock_bootkit_scan()
        elif "make build-nuclear-cd" in cmd:
            return self._mock_build_cd()
        elif "make deploy-esp-iso" in cmd:
            return self._mock_deploy_esp()
        elif "make hardware-recovery" in cmd:
            return self._mock_hardware_recovery()
        elif cmd.startswith("which"):
            return 0, "/usr/bin/fake", ""  # All tools "available"
        else:
            return 0, "Mock command executed successfully", ""
    
    def _mock_bootkit_scan(self):
        """Mock bootkit scan results based on scenario"""
        if self.scenario == "clean":
            # Create mock results showing clean system
            results = {
                "scan_timestamp": "2025-08-20T10:15:00Z",
                "threats_detected": False,
                "risk_level": "LOW",
                "detected_threats": [],
                "system_status": "CLEAN"
            }
        elif self.scenario in ["infected", "locked", "nuclear"]:
            # Create mock results showing infection
            results = {
                "scan_timestamp": "2025-08-20T10:15:00Z", 
                "threats_detected": True,
                "risk_level": "HIGH",
                "detected_threats": [
                    "Suspicious UEFI modification detected",
                    "Unknown bootloader signature",
                    "Modified firmware variables"
                ],
                "system_status": "INFECTED"
            }
        else:
            # Interactive - let user decide
            print(f"\n{Colors.CYAN}🧪 MOCK: Bootkit scan running...{Colors.END}")
            choice = input(f"{Colors.YELLOW}Simulate threats found? [y/N]: {Colors.END}").strip().lower()
            if choice in ['y', 'yes']:
                results = {
                    "threats_detected": True,
                    "risk_level": "HIGH", 
                    "detected_threats": ["Test threat simulation"]
                }
            else:
                results = {
                    "threats_detected": False,
                    "risk_level": "LOW",
                    "detected_threats": []
                }
        
        # Write mock results file
        with open(self.project_root / "bootkit_scan_results.json", 'w') as f:
            json.dump(results, f, indent=2)
        
        return 0, "Bootkit scan completed", ""
    
    def _mock_build_cd(self):
        """Mock Nuclear Boot CD creation"""
        if self.scenario == "nuclear":
            return 1, "", "Failed to build Nuclear Boot CD - missing dependencies"
        
        # Create fake ISO file
        fake_iso = self.project_root / "PhoenixGuard-Nuclear-Recovery.iso"
        with open(fake_iso, 'w') as f:
            f.write("# Fake ISO file for testing\n" * 1000)
        
        return 0, "Nuclear Boot CD created successfully", ""
    
    def _mock_deploy_esp(self):
        """Mock ESP deployment"""
        if self.scenario == "locked":
            return 1, "", "ESP deployment failed - filesystem is read-only"
        
        return 0, "ISO deployed to ESP successfully", ""
    
    def _mock_hardware_recovery(self):
        """Mock hardware recovery"""
        if self.scenario == "nuclear":
            return 1, "", "Hardware recovery failed - FLOCKDN protection active"
        
        return 0, "Hardware recovery completed successfully", ""
    
    def confirm_action(self, message, danger_level="LOW"):
        """Override confirmation to provide automatic responses or ask user"""
        if self.scenario == "full":
            # Interactive mode - ask user
            return super().confirm_action(message, danger_level)
        elif self.scenario == "clean":
            # Auto-decline everything after first scan
            return message.startswith("🔍")
        elif self.scenario == "infected": 
            # Auto-accept up to SOFT level
            return not message.startswith("⚡") and not message.startswith("💥")
        elif self.scenario == "locked":
            # Auto-accept up to HARD level
            return not message.startswith("💥")
        elif self.scenario == "nuclear":
            # Auto-accept everything (will fail at hardware steps)
            return True
        else:
            return super().confirm_action(message, danger_level)

def run_scenario_test(scenario):
    """Run a specific test scenario"""
    print(f"\n{Colors.BOLD}🧪 AUTONUKE TEST - {scenario.upper()} SCENARIO{Colors.END}\n")
    
    descriptions = {
        "clean": "System appears clean, should stop at SCAN level",
        "infected": "Bootkit detected, should escalate to SOFT recovery", 
        "locked": "ESP locked, should escalate to HARD recovery",
        "nuclear": "All methods fail, should escalate to NUKE level",
        "full": "Interactive test - you control the escalation"
    }
    
    print(f"{Colors.CYAN}Scenario: {descriptions.get(scenario, 'Unknown scenario')}{Colors.END}\n")
    
    # Create mock AutoNuke instance
    autonuke = MockAutoNuke(scenario)
    
    # Run the recovery process
    try:
        autonuke.run_recovery()
    except KeyboardInterrupt:
        print(f"\n{Colors.YELLOW}Test interrupted by user{Colors.END}")
    except Exception as e:
        print(f"\n{Colors.RED}Test error: {e}{Colors.END}")
    
    print(f"\n{Colors.GREEN}🧪 Test scenario '{scenario}' completed!{Colors.END}")

def main():
    """Main test runner"""
    if len(sys.argv) > 1:
        scenario = sys.argv[1].lower()
    else:
        # Show available scenarios
        print(f"{Colors.BOLD}AUTONUKE Interactive Test{Colors.END}\n")
        print("Available test scenarios:")
        print(f"  {Colors.GREEN}clean{Colors.END}    - System appears clean (stops at SCAN)")
        print(f"  {Colors.YELLOW}infected{Colors.END} - Bootkit detected (escalates to SOFT)")
        print(f"  {Colors.MAGENTA}locked{Colors.END}   - ESP locked (escalates to HARD)")  
        print(f"  {Colors.RED}nuclear{Colors.END}  - All methods fail (escalates to NUKE)")
        print(f"  {Colors.CYAN}full{Colors.END}     - Interactive (you control escalation)")
        print()
        
        scenario = input("Select scenario [full]: ").strip().lower() or "full"
    
    if scenario not in ["clean", "infected", "locked", "nuclear", "full"]:
        print(f"{Colors.RED}Unknown scenario: {scenario}{Colors.END}")
        sys.exit(1)
    
    run_scenario_test(scenario)

if __name__ == "__main__":
    main()
