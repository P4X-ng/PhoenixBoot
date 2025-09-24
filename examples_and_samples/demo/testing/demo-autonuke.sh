#!/bin/bash
#
# AUTONUKE Demo Script
# ===================
#
# Demonstrates the complete AUTONUKE progressive recovery system
# by running through all test scenarios automatically.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[91m'
GREEN='\033[92m'
YELLOW='\033[93m'
BLUE='\033[94m'
CYAN='\033[96m'
MAGENTA='\033[95m'
BOLD='\033[1m'
END='\033[0m'

demo_banner() {
    echo -e "${BOLD}${CYAN}"
    echo "╔═════════════════════════════════════════════════════════════╗"
    echo "║                    AUTONUKE DEMONSTRATION                   ║"
    echo "║          Progressive Bootkit Recovery System                ║"
    echo "╚═════════════════════════════════════════════════════════════╝"
    echo -e "${END}"
    echo
}

run_scenario() {
    local scenario=$1
    local description=$2
    
    echo -e "${BOLD}${BLUE}═══ SCENARIO: ${scenario^^} ═══${END}"
    echo -e "${CYAN}$description${END}"
    echo
    
    # Run the test scenario
    cd "$PROJECT_ROOT"
    python3 scripts/test-autonuke-interactive.py "$scenario" || true
    
    echo
    echo -e "${GREEN}✅ Scenario '$scenario' completed!${END}"
    echo
    read -p "Press Enter to continue to next scenario..." || true
    echo
}

main() {
    demo_banner
    
    echo -e "${YELLOW}This demo will show AUTONUKE's progressive recovery system${END}"
    echo -e "${YELLOW}through different bootkit infection scenarios.${END}"
    echo
    echo -e "${CYAN}AUTONUKE escalates through 4 levels:${END}"
    echo -e "  ${GREEN}🔍 SCAN${END} - Software-level bootkit detection"
    echo -e "  ${BLUE}💿 SOFT${END} - ESP Nuclear Boot ISO recovery"
    echo -e "  ${MAGENTA}⚡ HARD${END} - Direct hardware firmware recovery"
    echo -e "  ${RED}💥 NUKE${END} - External CH341A programmer recovery"
    echo
    
    read -p "Ready to start demo? [y/N]: " confirm || true
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "Demo cancelled."
        exit 0
    fi
    
    clear
    
    # Run through each scenario
    run_scenario "clean" "System appears clean - should stop at SCAN level"
    
    run_scenario "infected" "Bootkit detected - should escalate to SOFT recovery"
    
    run_scenario "locked" "ESP locked by bootkit - should escalate to HARD recovery"
    
    run_scenario "nuclear" "All automated methods fail - shows NUKE instructions"
    
    # Final summary
    echo -e "${BOLD}${GREEN}🎉 AUTONUKE DEMONSTRATION COMPLETE!${END}"
    echo
    echo -e "${CYAN}What we demonstrated:${END}"
    echo -e "  ✅ Progressive escalation through 4 recovery levels"
    echo -e "  ✅ Intelligent stopping when system is clean"
    echo -e "  ✅ Automatic escalation when threats are detected"
    echo -e "  ✅ Safety confirmations at each danger level"
    echo -e "  ✅ Clear instructions for hardware recovery"
    echo -e "  ✅ Complete logging and session tracking"
    echo
    echo -e "${YELLOW}🚀 Ready for real-world testing!${END}"
    echo -e "${CYAN}Try: make autonuke${END}"
    echo
}

main "$@"
