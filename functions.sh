# Define global functions

# Validate all required environment variables at startup
# Exits with a clear error message if any value is invalid
function validate_env_vars() {
  local errors=0

  # Required vars
  local required_vars=("IDRAC_HOST" "FAN_SPEED_MIN" "FAN_SPEED_MAX" "CPU_TEMPERATURE_LOWER_THRESHOLD" "CPU_TEMPERATURE_UPPER_THRESHOLD" "CHECK_INTERVAL")
  for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
      print_error "$var is not set"
      ((errors++))
    fi
  done

  # If any required vars are missing, exit now before further checks dereference them
  if [ $errors -gt 0 ]; then
    printf " Exiting.\n" >&2
    exit 1
  fi

  # FAN_SPEED_MIN must be an integer >= FAN_SPEED_HARD_FLOOR
  if ! [[ "$FAN_SPEED_MIN" =~ ^[0-9]+$ ]]; then
    print_error "FAN_SPEED_MIN must be a positive integer, got: $FAN_SPEED_MIN"
    ((errors++))
  elif [ "$FAN_SPEED_MIN" -lt "$FAN_SPEED_HARD_FLOOR" ]; then
    print_error "FAN_SPEED_MIN ($FAN_SPEED_MIN) must be >= hard floor ($FAN_SPEED_HARD_FLOOR)"
    ((errors++))
  fi

  # FAN_SPEED_MAX must be an integer <= 100
  if ! [[ "$FAN_SPEED_MAX" =~ ^[0-9]+$ ]]; then
    print_error "FAN_SPEED_MAX must be a positive integer, got: $FAN_SPEED_MAX"
    ((errors++))
  elif [ "$FAN_SPEED_MAX" -gt 100 ]; then
    print_error "FAN_SPEED_MAX ($FAN_SPEED_MAX) must be <= 100"
    ((errors++))
  fi

  # FAN_SPEED_MIN must be < FAN_SPEED_MAX (only check if both are valid integers)
  if [[ "$FAN_SPEED_MIN" =~ ^[0-9]+$ ]] && [[ "$FAN_SPEED_MAX" =~ ^[0-9]+$ ]]; then
    if [ "$FAN_SPEED_MIN" -ge "$FAN_SPEED_MAX" ]; then
      print_error "FAN_SPEED_MIN ($FAN_SPEED_MIN) must be less than FAN_SPEED_MAX ($FAN_SPEED_MAX)"
      ((errors++))
    fi
  fi

  # CPU_TEMPERATURE_LOWER_THRESHOLD must be a positive integer
  if ! [[ "$CPU_TEMPERATURE_LOWER_THRESHOLD" =~ ^[0-9]+$ ]]; then
    print_error "CPU_TEMPERATURE_LOWER_THRESHOLD must be a positive integer, got: $CPU_TEMPERATURE_LOWER_THRESHOLD"
    ((errors++))
  fi

  # CPU_TEMPERATURE_UPPER_THRESHOLD must be a positive integer
  if ! [[ "$CPU_TEMPERATURE_UPPER_THRESHOLD" =~ ^[0-9]+$ ]]; then
    print_error "CPU_TEMPERATURE_UPPER_THRESHOLD must be a positive integer, got: $CPU_TEMPERATURE_UPPER_THRESHOLD"
    ((errors++))
  fi

  # LOWER must be < UPPER (only check if both are valid integers)
  if [[ "$CPU_TEMPERATURE_LOWER_THRESHOLD" =~ ^[0-9]+$ ]] && [[ "$CPU_TEMPERATURE_UPPER_THRESHOLD" =~ ^[0-9]+$ ]]; then
    if [ "$CPU_TEMPERATURE_LOWER_THRESHOLD" -ge "$CPU_TEMPERATURE_UPPER_THRESHOLD" ]; then
      print_error "CPU_TEMPERATURE_LOWER_THRESHOLD ($CPU_TEMPERATURE_LOWER_THRESHOLD) must be less than CPU_TEMPERATURE_UPPER_THRESHOLD ($CPU_TEMPERATURE_UPPER_THRESHOLD)"
      ((errors++))
    fi
  fi

  # CHECK_INTERVAL must be a positive integer
  if ! [[ "$CHECK_INTERVAL" =~ ^[0-9]+$ ]] || [ "$CHECK_INTERVAL" -lt 1 ]; then
    print_error "CHECK_INTERVAL must be a positive integer, got: $CHECK_INTERVAL"
    ((errors++))
  fi

  # ENABLE_DELL_CONTROL_ON_STARTUP must be true or false
  if [[ "$ENABLE_DELL_CONTROL_ON_STARTUP" != "true" && "$ENABLE_DELL_CONTROL_ON_STARTUP" != "false" ]]; then
    print_error "ENABLE_DELL_CONTROL_ON_STARTUP must be 'true' or 'false', got: $ENABLE_DELL_CONTROL_ON_STARTUP"
    ((errors++))
  fi

  if [ $errors -gt 0 ]; then
    printf " Exiting.\n" >&2
    exit 1
  fi
}

# Single entry point for all ipmitool calls.
# Overriding this function in tests prevents any real ipmitool calls from reaching the server.
function run_ipmitool() {
  ipmitool "$@"
}

# This function applies Dell's default dynamic fan control profile
function apply_Dell_default_fan_control_profile() {
  run_ipmitool -I $IDRAC_LOGIN_STRING raw 0x30 0x30 0x01 0x01 > /dev/null
  local exit_code=$?
  CURRENT_FAN_CONTROL_PROFILE="Dell default"
  return $exit_code
}

# Apply a static fan speed. Accepts a decimal percentage as $1.
# Usage: apply_static_fan_speed $DECIMAL_SPEED
function apply_static_fan_speed() {
  local -r decimal_speed=$1
  local -r hex_speed=$(convert_decimal_value_to_hexadecimal "$decimal_speed")
  run_ipmitool -I $IDRAC_LOGIN_STRING raw 0x30 0x30 0x01 0x00 > /dev/null || return 1
  run_ipmitool -I $IDRAC_LOGIN_STRING raw 0x30 0x30 0x02 0xff "$hex_speed" > /dev/null || return 1
  return 0
}

# Calculate the target fan speed percentage for a given temperature.
# Uses linear interpolation between FAN_SPEED_MIN and FAN_SPEED_MAX across the
# range [CPU_TEMPERATURE_LOWER_THRESHOLD, CPU_TEMPERATURE_UPPER_THRESHOLD].
# Result is rounded up and clamped to [FAN_SPEED_HARD_FLOOR, FAN_SPEED_MAX].
# Echoes the resulting integer percentage.
# Usage: calculate_dynamic_fan_speed $TEMPERATURE
function calculate_dynamic_fan_speed() {
  local -r temp=$1
  local -r lower=$CPU_TEMPERATURE_LOWER_THRESHOLD
  local -r upper=$CPU_TEMPERATURE_UPPER_THRESHOLD
  local -r min=$FAN_SPEED_MIN
  local -r max=$FAN_SPEED_MAX

  # Interpolate: speed = min + (max - min) * (temp - lower) / (upper - lower)
  # Ceiling division using integer arithmetic: (a + b - 1) / b
  local range_temp=$(( temp - lower ))
  local range_thresh=$(( upper - lower ))
  local speed_range=$(( max - min ))

  # Ceiling: (min * range_thresh + speed_range * range_temp + range_thresh - 1) / range_thresh
  local speed=$(( min + (speed_range * range_temp + range_thresh - 1) / range_thresh ))

  # Clamp to [FAN_SPEED_HARD_FLOOR, FAN_SPEED_MAX]
  if [ $speed -lt $FAN_SPEED_HARD_FLOOR ]; then
    speed=$FAN_SPEED_HARD_FLOOR
  elif [ $speed -gt $max ]; then
    speed=$max
  fi

  echo $speed
}

# Determine the fan control state for a given temperature.
# Accounts for hysteresis at the lower threshold.
# Sets global: FAN_CONTROL_STATE — one of: "min", "dynamic", "dell"
# Usage: determine_fan_control_state $TEMPERATURE $CURRENT_STATE
function determine_fan_control_state() {
  local -r temp=$1
  local -r current_state=$2

  if [ "$temp" -ge "$CPU_TEMPERATURE_UPPER_THRESHOLD" ]; then
    FAN_CONTROL_STATE="dell"
  elif [ "$temp" -gt "$CPU_TEMPERATURE_LOWER_THRESHOLD" ]; then
    FAN_CONTROL_STATE="dynamic"
  else
    # Apply hysteresis: only return to "min" if temp is below lower threshold minus offset,
    # OR if we were already in "min" state (avoids oscillation at the boundary)
    local -r hysteresis_point=$(( CPU_TEMPERATURE_LOWER_THRESHOLD - HYSTERESIS_OFFSET ))
    if [ "$temp" -le "$hysteresis_point" ] || [ "$current_state" = "min" ]; then
      FAN_CONTROL_STATE="min"
    else
      FAN_CONTROL_STATE="dynamic"
    fi
  fi
}

# Convert first parameter given ($DECIMAL_NUMBER) to hexadecimal
# Usage : convert_decimal_value_to_hexadecimal $DECIMAL_NUMBER
# Returns : hexadecimal value of DECIMAL_NUMBER
function convert_decimal_value_to_hexadecimal() {
  local -r DECIMAL_NUMBER=$1
  local -r HEXADECIMAL_NUMBER=$(printf '0x%02x' $DECIMAL_NUMBER)
  echo $HEXADECIMAL_NUMBER
}

# Convert first parameter given ($HEXADECIMAL_NUMBER) to decimal
# Usage : convert_hexadecimal_value_to_decimal "$HEXADECIMAL_NUMBER"
# Returns : decimal value of HEXADECIMAL_NUMBER
function convert_hexadecimal_value_to_decimal() {
  local -r HEXADECIMAL_NUMBER=$1
  local -r DECIMAL_NUMBER=$(printf '%d' $HEXADECIMAL_NUMBER)
  echo $DECIMAL_NUMBER
}

# Set the IDRAC_LOGIN_STRING variable based on connection type
# Usage : set_iDRAC_login_string $IDRAC_HOST $IDRAC_USERNAME $IDRAC_PASSWORD
# Returns : IDRAC_LOGIN_STRING
function set_iDRAC_login_string() {
  local IDRAC_HOST="$1"
  local IDRAC_USERNAME="$2"
  local IDRAC_PASSWORD="$3"

  IDRAC_LOGIN_STRING=""

  # Check if the iDRAC host is set to 'local' or not then set the IDRAC_LOGIN_STRING accordingly
  if [[ "$IDRAC_HOST" == "local" ]]; then
    # Check that the Docker host IPMI device (the iDRAC) has been exposed to the Docker container
    if [ ! -e "/dev/ipmi0" ] && [ ! -e "/dev/ipmi/0" ] && [ ! -e "/dev/ipmidev/0" ]; then
      print_error_and_exit "Could not open device at /dev/ipmi0 or /dev/ipmi/0 or /dev/ipmidev/0, check that you added the device to your Docker container or stop using local mode"
    fi
    IDRAC_LOGIN_STRING='open'
  else
    echo "iDRAC/IPMI username: $IDRAC_USERNAME"
    #echo "iDRAC/IPMI password: $IDRAC_PASSWORD"
    IDRAC_LOGIN_STRING="lanplus -H $IDRAC_HOST -U $IDRAC_USERNAME -P $IDRAC_PASSWORD"
  fi
}

# Fetch all sensor data in a single ipmitool call and populate global sensor variables.
# Sets: INLET_TEMPERATURE, CPU1_TEMPERATURE, CPU2_TEMPERATURE, CPUS_TEMPERATURES,
#       NUMBER_OF_DETECTED_CPUS, EXHAUST_TEMPERATURE, POWER_CONSUMPTION
# Returns 1 on IPMI failure or missing critical sensor data, 0 on success.
function retrieve_sensor_data() {
  local raw_data
  raw_data=$(run_ipmitool -I $IDRAC_LOGIN_STRING sdr list full 2>/dev/null)
  local ipmi_exit=$?

  if [ $ipmi_exit -ne 0 ] || [ -z "$raw_data" ]; then
    print_error "Failed to retrieve sensor data from iDRAC"
    return 1
  fi

  # Extract numeric value from a "| NNN degrees C |" formatted line
  # Usage: extract_degrees "line"
  extract_degrees() { echo "$1" | sed -E 's/.*\|[[:space:]]+([0-9]+) degrees.*/\1/'; }

  # Parse inlet temperature
  INLET_TEMPERATURE=$(echo "$raw_data" | grep "Inlet Temp" | { read -r line; extract_degrees "$line"; })

  # Parse exhaust temperature
  EXHAUST_TEMPERATURE=$(echo "$raw_data" | grep "Exhaust Temp" | { read -r line; extract_degrees "$line"; })

  # Parse CPU temperatures — lines containing "degrees" that are not Inlet or Exhaust
  local cpu_temps=()
  while IFS= read -r line; do
    local val
    val=$(extract_degrees "$line")
    [ -n "$val" ] && cpu_temps+=("$val")
  done < <(echo "$raw_data" | grep "degrees" | grep -v "Inlet\|Exhaust")

  NUMBER_OF_DETECTED_CPUS=${#cpu_temps[@]}

  CPU1_TEMPERATURE="${cpu_temps[0]:-}"
  CPU2_TEMPERATURE="${cpu_temps[1]:-}"

  # Build semicolon-separated string for display
  CPUS_TEMPERATURES=""
  for i in "${!cpu_temps[@]}"; do
    [ $i -gt 0 ] && CPUS_TEMPERATURES+=";"
    CPUS_TEMPERATURES+="${cpu_temps[$i]}"
  done

  # Parse power consumption
  POWER_CONSUMPTION=$(echo "$raw_data" | grep "Pwr Consumption" | sed -E 's/.*\|[[:space:]]+([0-9]+) Watts.*/\1/')

  # Validate that we have at least CPU1 and inlet temps
  if [ -z "$CPU1_TEMPERATURE" ] || [ -z "$INLET_TEMPERATURE" ]; then
    print_error "Critical sensor data missing (CPU1 or Inlet temperature not found)"
    return 1
  fi

  return 0
}

# /!\ Use this function only for Gen 13 and older generation servers /!\
function enable_third_party_PCIe_card_Dell_default_cooling_response() {
  # We could check the current cooling response before applying but it's not very useful so let's skip the test and apply directly
  run_ipmitool -I $IDRAC_LOGIN_STRING raw 0x30 0xce 0x00 0x16 0x05 0x00 0x00 0x00 0x05 0x00 0x00 0x00 0x00 > /dev/null
}

# /!\ Use this function only for Gen 13 and older generation servers /!\
function disable_third_party_PCIe_card_Dell_default_cooling_response() {
  # We could check the current cooling response before applying but it's not very useful so let's skip the test and apply directly
  run_ipmitool -I $IDRAC_LOGIN_STRING raw 0x30 0xce 0x00 0x16 0x05 0x00 0x00 0x00 0x05 0x00 0x01 0x00 0x00 > /dev/null
}

# Returns :
# - 0 if third-party PCIe card Dell default cooling response is currently DISABLED
# - 1 if third-party PCIe card Dell default cooling response is currently ENABLED
# - 2 if the current status returned by ipmitool command output is unexpected
# function is_third_party_PCIe_card_Dell_default_cooling_response_disabled() {
#   THIRD_PARTY_PCIE_CARD_COOLING_RESPONSE=$(ipmitool -I $IDRAC_LOGIN_STRING raw 0x30 0xce 0x01 0x16 0x05 0x00 0x00 0x00)

#   if [ "$THIRD_PARTY_PCIE_CARD_COOLING_RESPONSE" == "16 05 00 00 00 05 00 01 00 00" ]; then
#     return 0
#   elif [ "$THIRD_PARTY_PCIE_CARD_COOLING_RESPONSE" == "16 05 00 00 00 05 00 00 00 00" ]; then
#     return 1
#   else
#     print_error "Unexpected output: $THIRD_PARTY_PCIE_CARD_COOLING_RESPONSE"
#     return 2
#   fi
# }

# Prepare traps in case of container exit
function graceful_exit() {
  apply_Dell_default_fan_control_profile

  # Reset third-party PCIe card cooling response to Dell default (Gen 13 and older only)
  if ! $DELL_POWEREDGE_GEN_14_OR_NEWER && ! "$KEEP_THIRD_PARTY_PCIE_CARD_COOLING_RESPONSE_STATE_ON_EXIT"; then
    enable_third_party_PCIe_card_Dell_default_cooling_response
  fi

  print_warning_and_exit "Container stopped, Dell default fan control restored"
}

# Helps debugging when people are posting their output
function get_Dell_server_model() {
  local -r IPMI_FRU_content=$(run_ipmitool -I $IDRAC_LOGIN_STRING fru 2>/dev/null) # FRU stands for "Field Replaceable Unit"

  SERVER_MANUFACTURER=$(echo "$IPMI_FRU_content" | grep "Product Manufacturer" | awk -F ': ' '{print $2}')
  SERVER_MODEL=$(echo "$IPMI_FRU_content" | grep "Product Name" | awk -F ': ' '{print $2}')

  # Check if SERVER_MANUFACTURER is empty, if yes, assign value based on "Board Mfg"
  if [ -z "$SERVER_MANUFACTURER" ]; then
    SERVER_MANUFACTURER=$(echo "$IPMI_FRU_content" | tr -s ' ' | grep "Board Mfg :" | awk -F ': ' '{print $2}')
  fi

  # Check if SERVER_MODEL is empty, if yes, assign value based on "Board Product"
  if [ -z "$SERVER_MODEL" ]; then
    SERVER_MODEL=$(echo "$IPMI_FRU_content" | tr -s ' ' | grep "Board Product :" | awk -F ': ' '{print $2}')
  fi
}

# Color support — only emit ANSI codes when stdout is a TTY and TERM supports color
function init_colors() {
  if [ -t 1 ] && [ "${TERM:-dumb}" != "dumb" ]; then
    COLOR_RESET="\033[0m"
    COLOR_BOLD="\033[1m"
    COLOR_GREEN="\033[32m"
    COLOR_YELLOW="\033[33m"
    COLOR_RED="\033[31m"
    COLOR_CYAN="\033[36m"
    COLOR_DIM="\033[2m"
  else
    COLOR_RESET=""
    COLOR_BOLD=""
    COLOR_GREEN=""
    COLOR_YELLOW=""
    COLOR_RED=""
    COLOR_CYAN=""
    COLOR_DIM=""
  fi
}

# Return a color code for a temperature value relative to thresholds
# Usage: temp_color $TEMP
function temp_color() {
  local temp=$1
  if [ "$temp" -ge "$CPU_TEMPERATURE_UPPER_THRESHOLD" ]; then
    printf "%s" "$COLOR_RED"
  elif [ "$temp" -ge "$CPU_TEMPERATURE_LOWER_THRESHOLD" ]; then
    printf "%s" "$COLOR_YELLOW"
  else
    printf "%s" "$COLOR_GREEN"
  fi
}

# Return a color code for a fan speed percentage
# Usage: fan_color $SPEED
function fan_color() {
  local speed=$1
  if [ "$speed" = "-" ]; then
    printf "%s" "$COLOR_DIM"
  elif [ "$speed" -ge "$FAN_SPEED_MAX" ]; then
    printf "%s" "$COLOR_RED"
  elif [ "$speed" -gt "$FAN_SPEED_MIN" ]; then
    printf "%s" "$COLOR_YELLOW"
  else
    printf "%s" "$COLOR_GREEN"
  fi
}

# Print the startup banner with server info
# Usage: print_banner $SERVER_MANUFACTURER $SERVER_MODEL $IDRAC_HOST
function print_banner() {
  local -r manufacturer="$1"
  local -r model="$2"
  local -r host="$3"
  local -r title="  iDRAC Fan Controller  |  ${manufacturer} ${model}  |  ${host}  "
  local -r width=${#title}
  local border
  border=$(printf '═%.0s' $(seq 1 $width))
  printf "${COLOR_BOLD}╔%s╗\n║%s║\n╚%s╝${COLOR_RESET}\n\n" "$border" "$title" "$border"
}

# Print the table column header
# Usage: print_table_header $NUMBER_OF_DETECTED_CPUS
function print_table_header() {
  local -r num_cpus="$1"
  local header
  header="  ${COLOR_BOLD}${COLOR_DIM}Date & Time           Inlet"
  for ((i=1; i<=num_cpus; i++)); do
    header+="  CPU${i}"
  done
  header+="  Exhaust  Target  Power   Profile              Comment${COLOR_RESET}"
  printf "\n${header}\n"
  # Separator line
  local sep="  ──────────────────────"
  for ((i=1; i<=num_cpus; i++)); do sep+="──────"; done
  sep+="──────────────────────────────────────────────────────────────"
  printf "%s\n" "$sep"
}

# Print a single data row
# Usage: print_table_row $INLET $CPUS_TEMPS $EXHAUST $TARGET_SPEED $POWER $PROFILE $COMMENT
function print_table_row() {
  local -r inlet="$1"
  local -r cpus_temps="$2"
  local -r exhaust="$3"
  local -r target="$4"
  local -r power="$5"
  local -r profile="$6"
  local -r comment="$7"

  local -r cpus_array=(${cpus_temps//;/ })

  # Date & time
  printf "  %s  " "$(date +"%d-%m-%Y %T")"

  # Inlet temp
  printf "$(temp_color $inlet)%3d°C${COLOR_RESET}" "$inlet"

  # CPU temps
  for temp in "${cpus_array[@]}"; do
    printf "  $(temp_color $temp)%3d°C${COLOR_RESET}" "$temp"
  done

  # Exhaust temp
  if [ "$exhaust" = "-" ]; then
    printf "      -  "
  else
    printf "  $(temp_color $exhaust)%3d°C${COLOR_RESET}  " "$exhaust"
  fi

  # Target fan speed
  if [ "$target" = "-" ]; then
    printf "${COLOR_DIM}  -%% ${COLOR_RESET} "
  else
    printf "$(fan_color $target)%3d%%${COLOR_RESET}  " "$target"
  fi

  # Power consumption
  if [ -n "$power" ] && [ "$power" != "-" ]; then
    printf "${COLOR_CYAN}%4dW${COLOR_RESET}  " "$power"
  else
    printf "    -   "
  fi

  # Profile
  printf "%-20s  " "$profile"

  # Comment
  if [ "$comment" != " -" ] && [ -n "$comment" ]; then
    printf "${COLOR_YELLOW}%s${COLOR_RESET}" "$comment"
  fi

  printf "\n"
}

function print_error() {
  local -r ERROR_MESSAGE="$1"
  printf "/!\ Error /!\ %s." "$ERROR_MESSAGE" >&2
}

function print_error_and_exit() {
  local -r ERROR_MESSAGE="$1"
  print_error "$ERROR_MESSAGE"
  printf " Exiting.\n" >&2
  exit 1
}

function print_warning() {
  local -r WARNING_MESSAGE="$1"
  printf "/!\ Warning /!\ %s." "$WARNING_MESSAGE"
}

function print_warning_and_exit() {
  local -r WARNING_MESSAGE="$1"
  print_warning "$WARNING_MESSAGE"
  printf " Exiting.\n"
  exit 0
}
