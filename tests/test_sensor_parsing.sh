#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_runner.sh"

source "$SCRIPT_DIR/../constants.sh" 2>/dev/null
source "$SCRIPT_DIR/../functions.sh"

# Override run_ipmitool AFTER sourcing functions.sh — real ipmitool is never called
function run_ipmitool() {
  bash "$SCRIPT_DIR/mock_ipmitool.sh" "$@"
}

# Stub required globals that retrieve_sensor_data depends on
IDRAC_LOGIN_STRING="open"

printf "\n=== retrieve_sensor_data (normal fixture) ===\n"

retrieve_sensor_data
assert_equals "$INLET_TEMPERATURE" "22" "inlet temperature parsed correctly"
assert_equals "$CPU1_TEMPERATURE" "40" "CPU1 temperature parsed correctly"
assert_equals "$CPU2_TEMPERATURE" "38" "CPU2 temperature parsed correctly"
assert_equals "$EXHAUST_TEMPERATURE" "38" "exhaust temperature parsed correctly"
assert_equals "$POWER_CONSUMPTION" "224" "power consumption parsed correctly"
assert_equals "$NUMBER_OF_DETECTED_CPUS" "2" "two CPUs detected"
assert_equals "$CPUS_TEMPERATURES" "40;38" "CPUS_TEMPERATURES semicolon-separated"

printf "\n=== retrieve_sensor_data (IPMI failure) ===\n"

# Override to simulate failure
function run_ipmitool() { return 1; }

retrieve_sensor_data 2>/dev/null
assert_exit_code "$?" "1" "returns 1 on IPMI failure"

printf "\n=== retrieve_sensor_data (missing CPU temp) ===\n"

# Override to return data with no CPU temp lines
function run_ipmitool() {
  echo "Inlet Temp       | 22 degrees C      | ok"
  echo "Exhaust Temp     | 38 degrees C      | ok"
  echo "Pwr Consumption  | 224 Watts         | ok"
}

retrieve_sensor_data 2>/dev/null
assert_exit_code "$?" "1" "returns 1 when CPU temperature is missing"

printf "\n=== retrieve_sensor_data (missing optional sensors) ===\n"

# Single CPU, no exhaust sensor, no power consumption
function run_ipmitool() {
  echo "Inlet Temp       | 22 degrees C      | ok"
  echo "Temp             | 40 degrees C      | ok"
}

retrieve_sensor_data 2>/dev/null
assert_exit_code "$?" "0" "succeeds with only required sensors present"
assert_equals "$CPU1_TEMPERATURE" "40" "CPU1 temperature parsed correctly"
assert_equals "$CPU2_TEMPERATURE" "-" "CPU2 normalised to '-' when absent"
assert_equals "$EXHAUST_TEMPERATURE" "-" "exhaust normalised to '-' when absent"
assert_equals "$POWER_CONSUMPTION" "-" "power normalised to '-' when absent"
assert_equals "$NUMBER_OF_DETECTED_CPUS" "1" "one CPU detected"

print_summary
