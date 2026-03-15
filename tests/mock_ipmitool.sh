#!/bin/bash

# Mock ipmitool for testing. Parses the same argument patterns as the real tool
# and returns fixture data. Records calls to MOCK_CALLS_LOG if set.
#
# Usage: override run_ipmitool() in tests to call this script instead of the real ipmitool.

FIXTURE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/fixtures" && pwd)"

# Log this call if a log file is specified
if [ -n "$MOCK_CALLS_LOG" ]; then
  echo "$*" >> "$MOCK_CALLS_LOG"
fi

# Simulate a configurable failure mode
if [ "${MOCK_IPMITOOL_FAIL:-false}" = "true" ]; then
  echo "Error: mock forced failure" >&2
  exit 1
fi

# Parse arguments to determine what to return
while [[ $# -gt 0 ]]; do
  case "$1" in
    sdr)
      shift
      case "$1" in
        list)
          cat "$FIXTURE_DIR/sdr_list_full.txt"
          exit 0
          ;;
        type)
          # sdr type temperature — filter the full list to temperature lines
          grep "degrees" "$FIXTURE_DIR/sdr_list_full.txt"
          exit 0
          ;;
      esac
      ;;
    fru)
      cat "$FIXTURE_DIR/fru.txt" 2>/dev/null || echo "Product Manufacturer  : DELL
Product Name          : PowerEdge R740"
      exit 0
      ;;
    raw)
      # Fan control commands — just succeed silently
      exit 0
      ;;
  esac
  shift
done

exit 0
