#!/bin/bash
# scan-bootkits.sh - Hunt for bootkit infections using firmware baseline analysis
# This performs comprehensive bootkit detection against clean firmware baseline

set -euo pipefail
cd "$(dirname "$0")/.."

# Prefer central venv when available
if [ -x "/home/punk/.venv/bin/python3" ]; then
  PY="/home/punk/.venv/bin/python3"
else
  PY="python3"
fi

echo "🎯 PhoenixGuard Bootkit Detection Engine"
echo "Hunting for firmware-level malware..."
echo

# Paths
OUT_BASELINE_DIR="out/baseline"
OUT_LOGS_DIR="out/logs"
BASELINE_JSON="${BASELINE_JSON:-${OUT_BASELINE_DIR}/firmware_baseline.json}"
CLEAN_FW="${CLEAN_FIRMWARE:-drivers/G615LPAS.325}"
SCAN_OUT="${SCAN_OUT:-${OUT_LOGS_DIR}/bootkit_scan_results.json}"

mkdir -p "${OUT_BASELINE_DIR}" "${OUT_LOGS_DIR}"

# Locate baseline analyzer
ANALYZER=""
if [ -f dev/tools/analyze_firmware_baseline.py ]; then
  ANALYZER="dev/tools/analyze_firmware_baseline.py"
elif [ -f scripts/analyze_firmware_baseline.py ]; then
  ANALYZER="scripts/analyze_firmware_baseline.py"
fi

# Check or create baseline
if [ ! -f "${BASELINE_JSON}" ]; then
  echo "📊 Creating firmware baseline from clean BIOS dump..."
  if [ -z "${ANALYZER}" ]; then
    echo "ERROR: Baseline analyzer not found (expected dev/tools/analyze_firmware_baseline.py or scripts/analyze_firmware_baseline.py)"
    echo "       Please add the analyzer or specify BASELINE_JSON pointing to an existing baseline."
    exit 1
  fi
  if [ -f "${CLEAN_FW}" ]; then
    "${PY}" "${ANALYZER}" "${CLEAN_FW}" -o "${BASELINE_JSON}"
  else
    echo "ERROR: Clean BIOS dump not found at ${CLEAN_FW}"
    echo "       Place your clean firmware dump in drivers/ or set CLEAN_FIRMWARE=/path/to.bin"
    exit 1
  fi
else
  echo "✅ Using existing baseline: ${BASELINE_JSON}"
fi

# Run bootkit detection
echo "🔍 Scanning system for bootkit infections..."
"${PY}" scripts/detect_bootkit.py -v -b "${BASELINE_JSON}" --output "${SCAN_OUT}"

echo
echo "📊 Scan complete! Check ${SCAN_OUT} for detailed results."

# Check risk level and recommend actions
if [ -f "${SCAN_OUT}" ]; then
  RISK=$("${PY}" - "$SCAN_OUT" << 'PY'
import sys,json
p=sys.argv[1]
try:
  with open(p) as f:
    d=json.load(f)
  print(d.get('risk_level','UNKNOWN'))
except Exception:
  print('UNKNOWN')
PY
  )
  case "$RISK" in
    "CRITICAL")
      echo
      echo "🚨 CRITICAL THREAT DETECTED!"
      echo "   Consider running: just nuke level4-kvm"
      ;;
    "HIGH")
      echo
      echo "⚠️  HIGH RISK detected - recovery recommended"
      echo "   Consider running: just nuke level4-kvm"
      ;;
    "MEDIUM")
      echo
      echo "⚠️  MEDIUM RISK - monitoring recommended"
      ;;
    "LOW")
      echo
      echo "✅ LOW RISK - system appears clean"
      ;;
    *)
      echo
      echo "ℹ️  Risk assessment: $RISK"
      ;;
  esac
fi
