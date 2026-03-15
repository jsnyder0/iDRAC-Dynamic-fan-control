#!/bin/bash

# Master test runner — executes all test files and reports overall results.
# Real ipmitool is never called; all tests use the mock via run_ipmitool() overrides.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TOTAL_PASS=0
TOTAL_FAIL=0
FAILED_SUITES=()

run_suite() {
  local file="$1"
  local name
  name=$(basename "$file")
  echo "Running $name..."

  output=$(bash "$file" 2>&1)
  exit_code=$?

  echo "$output"

  local pass fail
  pass=$(echo "$output" | grep -c "^  PASS")
  fail=$(echo "$output" | grep -c "^  FAIL")

  TOTAL_PASS=$((TOTAL_PASS + pass))
  TOTAL_FAIL=$((TOTAL_FAIL + fail))

  if [ $exit_code -ne 0 ]; then
    FAILED_SUITES+=("$name")
  fi
}

for test_file in "$SCRIPT_DIR"/test_*.sh; do
  run_suite "$test_file"
  echo ""
done

echo "══════════════════════════════════════"
echo "  Total: $TOTAL_PASS passed, $TOTAL_FAIL failed"
if [ ${#FAILED_SUITES[@]} -gt 0 ]; then
  echo "  Failed suites: ${FAILED_SUITES[*]}"
  echo "══════════════════════════════════════"
  exit 1
else
  echo "  All suites passed."
  echo "══════════════════════════════════════"
  exit 0
fi
