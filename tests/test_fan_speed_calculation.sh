#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_runner.sh"

source "$SCRIPT_DIR/../constants.sh" 2>/dev/null
source "$SCRIPT_DIR/../functions.sh"
function run_ipmitool() { echo "unexpected ipmitool call: $*" >&2; return 1; }

# Test config: lower=45, upper=75, min=10, max=80
export CPU_TEMPERATURE_LOWER_THRESHOLD=45
export CPU_TEMPERATURE_UPPER_THRESHOLD=75
export FAN_SPEED_MIN=10
export FAN_SPEED_MAX=80

printf "\n=== calculate_dynamic_fan_speed ===\n"

# At lower threshold — should return min speed
result=$(calculate_dynamic_fan_speed 45)
assert_equals "$result" "10" "at lower threshold returns FAN_SPEED_MIN"

# At upper threshold — should return max speed
result=$(calculate_dynamic_fan_speed 75)
assert_equals "$result" "80" "at upper threshold returns FAN_SPEED_MAX"

# Midpoint (60°C) — 50% of range = 10 + 35 = 45
result=$(calculate_dynamic_fan_speed 60)
assert_equals "$result" "45" "midpoint temperature interpolates correctly"

# Just above lower threshold — should round up, not down
result=$(calculate_dynamic_fan_speed 46)
assert_equals "$result" "13" "just above lower threshold rounds up (ceiling)"

# Hard floor — with a very low min, result should not go below FAN_SPEED_HARD_FLOOR
export FAN_SPEED_MIN=5
result=$(calculate_dynamic_fan_speed 45)
assert_equals "$result" "5" "result respects FAN_SPEED_HARD_FLOOR"
export FAN_SPEED_MIN=10  # restore

printf "\n=== determine_fan_control_state ===\n"

# Below lower threshold (with hysteresis already at min) — stays min
determine_fan_control_state 40 "min"
assert_equals "$FAN_CONTROL_STATE" "min" "well below lower threshold -> min"

# At lower threshold — min (boundary is inclusive for "below or at")
determine_fan_control_state 45 "min"
assert_equals "$FAN_CONTROL_STATE" "min" "at lower threshold -> min"

# Just above lower threshold — dynamic
determine_fan_control_state 46 "min"
assert_equals "$FAN_CONTROL_STATE" "dynamic" "just above lower threshold -> dynamic"

# In the middle — dynamic
determine_fan_control_state 60 "dynamic"
assert_equals "$FAN_CONTROL_STATE" "dynamic" "mid-range -> dynamic"

# At upper threshold — dell
determine_fan_control_state 75 "dynamic"
assert_equals "$FAN_CONTROL_STATE" "dell" "at upper threshold -> dell"

# Above upper threshold — dell
determine_fan_control_state 80 "dell"
assert_equals "$FAN_CONTROL_STATE" "dell" "above upper threshold -> dell"

# Hysteresis: temp dropped to lower threshold but was in dynamic — stays dynamic
# (must drop to lower - HYSTERESIS_OFFSET=2, i.e. 43°C, to return to min)
determine_fan_control_state 45 "dynamic"
assert_equals "$FAN_CONTROL_STATE" "dynamic" "at lower threshold coming from dynamic -> stays dynamic (hysteresis)"

# Hysteresis: temp dropped below hysteresis point — returns to min
determine_fan_control_state 43 "dynamic"
assert_equals "$FAN_CONTROL_STATE" "min" "at hysteresis point coming from dynamic -> min"

# Hysteresis: temp just above hysteresis point, coming from dynamic — stays dynamic
determine_fan_control_state 44 "dynamic"
assert_equals "$FAN_CONTROL_STATE" "dynamic" "just above hysteresis point coming from dynamic -> stays dynamic"

print_summary
