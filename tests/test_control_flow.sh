#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_runner.sh"

source "$SCRIPT_DIR/../constants.sh" 2>/dev/null
source "$SCRIPT_DIR/../functions.sh"

# Track which IPMI commands were called
MOCK_CALLS=()
function run_ipmitool() {
  MOCK_CALLS+=("$*")
  return 0
}

export IDRAC_LOGIN_STRING="open"
export CPU_TEMPERATURE_LOWER_THRESHOLD=45
export CPU_TEMPERATURE_UPPER_THRESHOLD=75
export FAN_SPEED_MIN=10
export FAN_SPEED_MAX=80

printf "\n=== apply_static_fan_speed ===\n"

MOCK_CALLS=()
apply_static_fan_speed 30
assert_equals "${#MOCK_CALLS[@]}" "2" "apply_static_fan_speed sends exactly 2 IPMI commands"
assert_contains "${MOCK_CALLS[0]}" "0x30 0x30 0x01 0x00" "first command disables Dell auto control"
assert_contains "${MOCK_CALLS[1]}" "0x30 0x30 0x02 0xff" "second command sets fan speed"
assert_contains "${MOCK_CALLS[1]}" "0x1e" "30% converts to hex 0x1e"

printf "\n=== apply_Dell_default_fan_control_profile ===\n"

MOCK_CALLS=()
apply_Dell_default_fan_control_profile
assert_equals "${#MOCK_CALLS[@]}" "1" "apply_Dell_default_fan_control_profile sends exactly 1 IPMI command"
assert_contains "${MOCK_CALLS[0]}" "0x30 0x30 0x01 0x01" "command enables Dell auto control"

printf "\n=== IPMI failure handling ===\n"

function run_ipmitool() { return 1; }

apply_static_fan_speed 30
assert_exit_code "$?" "1" "apply_static_fan_speed returns 1 on IPMI failure"

apply_Dell_default_fan_control_profile
assert_exit_code "$?" "1" "apply_Dell_default_fan_control_profile returns 1 on IPMI failure"

printf "\n=== retrieve_sensor_data consecutive failure counter ===\n"

function run_ipmitool() { return 1; }
IDRAC_LOGIN_STRING="open"

retrieve_sensor_data 2>/dev/null
assert_exit_code "$?" "1" "retrieve_sensor_data returns 1 on IPMI failure"

print_summary
