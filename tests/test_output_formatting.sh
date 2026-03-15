#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_runner.sh"

source "$SCRIPT_DIR/../constants.sh" 2>/dev/null
source "$SCRIPT_DIR/../functions.sh"
function run_ipmitool() { echo "unexpected ipmitool call: $*" >&2; return 1; }

export CPU_TEMPERATURE_LOWER_THRESHOLD=45
export CPU_TEMPERATURE_UPPER_THRESHOLD=75
export FAN_SPEED_MIN=10
export FAN_SPEED_MAX=80

# Force colors off so output is predictable in tests
COLOR_RESET="" COLOR_BOLD="" COLOR_GREEN="" COLOR_YELLOW=""
COLOR_RED="" COLOR_CYAN="" COLOR_DIM=""

printf "\n=== print_table_row ===\n"

# Capture a row and check key values appear
row=$(print_table_row "22" "40;38" "38" "30" "224" "Dynamic (30%)" " -")
assert_contains "$row" "22°C" "inlet temp appears in row"
assert_contains "$row" "40°C" "CPU1 temp appears in row"
assert_contains "$row" "38°C" "CPU2 temp appears in row"
assert_contains "$row" "30%" "target fan speed appears in row"
assert_contains "$row" "224W" "power consumption appears in row"
assert_contains "$row" "Dynamic (30%)" "profile appears in row"

# Row with Dell default (no target speed)
row=$(print_table_row "22" "76;74" "45" "-" "285" "Dell default" "Temp reached 75°C")
assert_contains "$row" "76°C" "overheating CPU temp appears in row"
assert_contains "$row" "Dell default" "Dell default profile appears in row"
assert_contains "$row" "Temp reached 75°C" "comment appears in row"

printf "\n=== print_table_header ===\n"

header=$(print_table_header 2)
assert_contains "$header" "CPU1" "CPU1 column in header"
assert_contains "$header" "CPU2" "CPU2 column in header"
assert_contains "$header" "Inlet" "Inlet column in header"
assert_contains "$header" "Target" "Target column in header"
assert_contains "$header" "Power" "Power column in header"

header_single=$(print_table_header 1)
assert_contains "$header_single" "CPU1" "single CPU header contains CPU1"

printf "\n=== temp_color (no color mode) ===\n"

# With colors off, temp_color should return empty string
result=$(temp_color 22)
assert_equals "$result" "" "below threshold returns no color code when colors disabled"

result=$(temp_color 60)
assert_equals "$result" "" "between thresholds returns no color code when colors disabled"

result=$(temp_color 80)
assert_equals "$result" "" "above upper threshold returns no color code when colors disabled"

print_summary
