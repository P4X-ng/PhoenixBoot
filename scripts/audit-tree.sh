#!/usr/bin/env bash
# Description: Audits the repository and categorizes code into staging, dev, wip, and demo.

set -euo pipefail

echo '{"staging": [], "dev": [], "wip": [], "demo": []}' > out/audit/report.json
echo "PhoenixGuard Repository Audit Summary" > out/audit/summary.txt
echo "===================================" >> out/audit/summary.txt
echo "" >> out/audit/summary.txt

STAGING_COUNT=0
DEV_COUNT=0
WIP_COUNT=0
DEMO_COUNT=0

for file in $(find . -type f ! -path "./out/*" ! -name ".*"); do
    case "$file" in
        *demo*|*example*|*sample*|*sandbox*|*mock*|*test-*|*bak/*)
            DEMO_COUNT=$((DEMO_COUNT + 1))
            ;;
        *wip*|*proto*|*experimental*|*universal_bios*|*universal-bios*)
            WIP_COUNT=$((WIP_COUNT + 1))
            ;;
        *bringup*|*platform*|*board*|*hardware_*|*flashrom*|*bootstrap*)
            DEV_COUNT=$((DEV_COUNT + 1))
            ;;
        *)
            STAGING_COUNT=$((STAGING_COUNT + 1))
            ;;
    esac
done

echo "STAGING: $STAGING_COUNT files" >> out/audit/summary.txt
echo "DEV: $DEV_COUNT files" >> out/audit/summary.txt
echo "WIP: $WIP_COUNT files" >> out/audit/summary.txt
echo "DEMO: $DEMO_COUNT files" >> out/audit/summary.txt

echo "✅ Audit complete - see out/audit/"

