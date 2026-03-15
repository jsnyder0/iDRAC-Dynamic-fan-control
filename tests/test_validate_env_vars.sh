#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_runner.sh"

source "$SCRIPT_DIR/../constants.sh"
source "$SCRIPT_DIR/../functions.sh"

# Override run_ipmitool AFTER sourcing functions.sh — real ipmitool is never called
function run_ipmitool() { echo "mock_ipmitool_called_unexpectedly: $*" >&2; return 1; }

printf "\n=== validate_env_vars ===\n"

# Helper: run validate_env_vars with a given set of env vars, capture output and exit code
run_validation() {
  # Export all vars passed as "KEY=VALUE" arguments
  local env_vars=("$@")
  (
    # Clear relevant vars first
    unset IDRAC_HOST FAN_SPEED_MIN FAN_SPEED_MAX CPU_TEMPERATURE_LOWER_THRESHOLD \
          CPU_TEMPERATURE_UPPER_THRESHOLD CHECK_INTERVAL ENABLE_DELL_CONTROL_ON_STARTUP

    for pair in "${env_vars[@]}"; do
      export "${pair?}"
    done

    source "$SCRIPT_DIR/../constants.sh" 2>/dev/null
    source "$SCRIPT_DIR/../functions.sh"
    function run_ipmitool() { echo "mock_ipmitool_called_unexpectedly: $*" >&2; return 1; }
    validate_env_vars 2>&1
  )
  echo "$?"
}

# Valid config — should pass
output_and_exit=$(run_validation \
  "IDRAC_HOST=192.168.1.100" \
  "FAN_SPEED_MIN=10" \
  "FAN_SPEED_MAX=80" \
  "CPU_TEMPERATURE_LOWER_THRESHOLD=45" \
  "CPU_TEMPERATURE_UPPER_THRESHOLD=75" \
  "CHECK_INTERVAL=60" \
  "ENABLE_DELL_CONTROL_ON_STARTUP=false")
exit_code="${output_and_exit##*$'\n'}"
assert_exit_code "$exit_code" "0" "valid config passes validation"

# Missing IDRAC_HOST
output_and_exit=$(run_validation \
  "FAN_SPEED_MIN=10" "FAN_SPEED_MAX=80" \
  "CPU_TEMPERATURE_LOWER_THRESHOLD=45" "CPU_TEMPERATURE_UPPER_THRESHOLD=75" \
  "CHECK_INTERVAL=60" "ENABLE_DELL_CONTROL_ON_STARTUP=false")
exit_code="${output_and_exit##*$'\n'}"
assert_exit_code "$exit_code" "1" "missing IDRAC_HOST fails validation"

# FAN_SPEED_MIN below hard floor
output_and_exit=$(run_validation \
  "IDRAC_HOST=192.168.1.100" \
  "FAN_SPEED_MIN=2" "FAN_SPEED_MAX=80" \
  "CPU_TEMPERATURE_LOWER_THRESHOLD=45" "CPU_TEMPERATURE_UPPER_THRESHOLD=75" \
  "CHECK_INTERVAL=60" "ENABLE_DELL_CONTROL_ON_STARTUP=false")
exit_code="${output_and_exit##*$'\n'}"
assert_exit_code "$exit_code" "1" "FAN_SPEED_MIN below hard floor fails validation"

# FAN_SPEED_MAX above 100
output_and_exit=$(run_validation \
  "IDRAC_HOST=192.168.1.100" \
  "FAN_SPEED_MIN=10" "FAN_SPEED_MAX=101" \
  "CPU_TEMPERATURE_LOWER_THRESHOLD=45" "CPU_TEMPERATURE_UPPER_THRESHOLD=75" \
  "CHECK_INTERVAL=60" "ENABLE_DELL_CONTROL_ON_STARTUP=false")
exit_code="${output_and_exit##*$'\n'}"
assert_exit_code "$exit_code" "1" "FAN_SPEED_MAX above 100 fails validation"

# FAN_SPEED_MIN >= FAN_SPEED_MAX
output_and_exit=$(run_validation \
  "IDRAC_HOST=192.168.1.100" \
  "FAN_SPEED_MIN=80" "FAN_SPEED_MAX=80" \
  "CPU_TEMPERATURE_LOWER_THRESHOLD=45" "CPU_TEMPERATURE_UPPER_THRESHOLD=75" \
  "CHECK_INTERVAL=60" "ENABLE_DELL_CONTROL_ON_STARTUP=false")
exit_code="${output_and_exit##*$'\n'}"
assert_exit_code "$exit_code" "1" "FAN_SPEED_MIN equal to FAN_SPEED_MAX fails validation"

# LOWER_THRESHOLD >= UPPER_THRESHOLD
output_and_exit=$(run_validation \
  "IDRAC_HOST=192.168.1.100" \
  "FAN_SPEED_MIN=10" "FAN_SPEED_MAX=80" \
  "CPU_TEMPERATURE_LOWER_THRESHOLD=75" "CPU_TEMPERATURE_UPPER_THRESHOLD=45" \
  "CHECK_INTERVAL=60" "ENABLE_DELL_CONTROL_ON_STARTUP=false")
exit_code="${output_and_exit##*$'\n'}"
assert_exit_code "$exit_code" "1" "LOWER_THRESHOLD >= UPPER_THRESHOLD fails validation"

# Invalid CHECK_INTERVAL
output_and_exit=$(run_validation \
  "IDRAC_HOST=192.168.1.100" \
  "FAN_SPEED_MIN=10" "FAN_SPEED_MAX=80" \
  "CPU_TEMPERATURE_LOWER_THRESHOLD=45" "CPU_TEMPERATURE_UPPER_THRESHOLD=75" \
  "CHECK_INTERVAL=0" "ENABLE_DELL_CONTROL_ON_STARTUP=false")
exit_code="${output_and_exit##*$'\n'}"
assert_exit_code "$exit_code" "1" "CHECK_INTERVAL of 0 fails validation"

# Invalid ENABLE_DELL_CONTROL_ON_STARTUP
output_and_exit=$(run_validation \
  "IDRAC_HOST=192.168.1.100" \
  "FAN_SPEED_MIN=10" "FAN_SPEED_MAX=80" \
  "CPU_TEMPERATURE_LOWER_THRESHOLD=45" "CPU_TEMPERATURE_UPPER_THRESHOLD=75" \
  "CHECK_INTERVAL=60" "ENABLE_DELL_CONTROL_ON_STARTUP=yes")
exit_code="${output_and_exit##*$'\n'}"
assert_exit_code "$exit_code" "1" "ENABLE_DELL_CONTROL_ON_STARTUP=yes fails validation"

print_summary
