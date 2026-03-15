#!/bin/bash

# Enable strict bash mode to stop the script if an uninitialized variable is used, if a command fails, or if a command with a pipe fails
# Not working in some setups : https://github.com/tigerblue77/Dell_iDRAC_fan_controller/issues/48
# set -euo pipefail

source functions.sh
source constants.sh

# Trap signals for container exit and restore Dell fan control before stopping
trap 'graceful_exit' SIGINT SIGQUIT SIGTERM

# Validate all environment variables before doing anything else
validate_env_vars

set_iDRAC_login_string "$IDRAC_HOST" "$IDRAC_USERNAME" "$IDRAC_PASSWORD"

# Optionally apply Dell default fan control before the first temp read (fail-safe startup)
if [ "$ENABLE_DELL_CONTROL_ON_STARTUP" = "true" ]; then
  echo "Applying Dell default fan control before first temperature read..."
  apply_Dell_default_fan_control_profile
fi

get_Dell_server_model

if [[ ! $SERVER_MANUFACTURER == "DELL" ]]; then
  print_error_and_exit "Your server isn't a Dell product"
fi

# Detect server generation — used to determine whether PCIe cooling response commands apply
if [[ $SERVER_MODEL =~ .*[RT][[:space:]]?[0-9][4-9]0.* ]]; then
  readonly DELL_POWEREDGE_GEN_14_OR_NEWER=true
else
  readonly DELL_POWEREDGE_GEN_14_OR_NEWER=false
fi

init_colors
print_banner "$SERVER_MANUFACTURER" "$SERVER_MODEL" "$IDRAC_HOST"
echo "Fan speed range:        ${FAN_SPEED_MIN}% - ${FAN_SPEED_MAX}%"
echo "Temperature thresholds: ${CPU_TEMPERATURE_LOWER_THRESHOLD}°C (lower) / ${CPU_TEMPERATURE_UPPER_THRESHOLD}°C (upper)"
echo "Check interval:         ${CHECK_INTERVAL}s"
echo ""

TABLE_HEADER_PRINT_COUNTER=$TABLE_HEADER_PRINT_INTERVAL
CONSECUTIVE_IPMI_FAILURES=0

# Current fan control state: "min", "dynamic", or "dell"
# Start as "dell" so hysteresis logic doesn't assume we were already at min speed
CURRENT_STATE="dell"

# Main monitoring loop
while true; do
  sleep "$CHECK_INTERVAL" &
  SLEEP_PROCESS_PID=$!

  # Retrieve all sensor data in a single IPMI call
  if ! retrieve_sensor_data; then
    ((CONSECUTIVE_IPMI_FAILURES++))
    echo "IPMI failure $CONSECUTIVE_IPMI_FAILURES/$MAX_CONSECUTIVE_IPMI_FAILURES"

    if [ $CONSECUTIVE_IPMI_FAILURES -ge $MAX_CONSECUTIVE_IPMI_FAILURES ]; then
      apply_Dell_default_fan_control_profile
      print_error_and_exit "Too many consecutive IPMI failures, Dell default fan control restored"
    fi

    wait $SLEEP_PROCESS_PID
    continue
  fi

  CONSECUTIVE_IPMI_FAILURES=0

  # Use the highest CPU temperature as input to the control logic
  MAX_CPU_TEMPERATURE=$CPU1_TEMPERATURE
  if [ -n "$CPU2_TEMPERATURE" ] && [ "$CPU2_TEMPERATURE" != "-" ] && [ "$CPU2_TEMPERATURE" -gt "$MAX_CPU_TEMPERATURE" ]; then
    MAX_CPU_TEMPERATURE=$CPU2_TEMPERATURE
  fi

  # Determine the new fan control state
  determine_fan_control_state "$MAX_CPU_TEMPERATURE" "$CURRENT_STATE"
  NEW_STATE="$FAN_CONTROL_STATE"

  COMMENT=" -"
  TARGET_FAN_SPEED="-"

  case "$NEW_STATE" in
    min)
      TARGET_FAN_SPEED=$FAN_SPEED_MIN
      if ! apply_static_fan_speed "$TARGET_FAN_SPEED"; then
        apply_Dell_default_fan_control_profile
        print_error_and_exit "Failed to apply fan speed, Dell default fan control restored"
      fi
      CURRENT_FAN_CONTROL_PROFILE="User static (${TARGET_FAN_SPEED}%)"
      if [ "$CURRENT_STATE" != "min" ]; then
        COMMENT="Temp at or below ${CPU_TEMPERATURE_LOWER_THRESHOLD}°C, minimum fan speed applied"
      fi
      ;;
    dynamic)
      TARGET_FAN_SPEED=$(calculate_dynamic_fan_speed "$MAX_CPU_TEMPERATURE")
      if ! apply_static_fan_speed "$TARGET_FAN_SPEED"; then
        apply_Dell_default_fan_control_profile
        print_error_and_exit "Failed to apply fan speed, Dell default fan control restored"
      fi
      CURRENT_FAN_CONTROL_PROFILE="Dynamic (${TARGET_FAN_SPEED}%)"
      if [ "$CURRENT_STATE" != "dynamic" ]; then
        COMMENT="Temp between thresholds, dynamic fan control applied"
      fi
      ;;
    dell)
      if ! apply_Dell_default_fan_control_profile; then
        print_error_and_exit "Failed to apply Dell default fan control"
      fi
      if [ "$CURRENT_STATE" != "dell" ]; then
        COMMENT="Temp reached ${CPU_TEMPERATURE_UPPER_THRESHOLD}°C, Dell default fan control restored"
      fi
      ;;
  esac

  CURRENT_STATE="$NEW_STATE"

  # Gen 13 and older: handle third-party PCIe card cooling response
  THIRD_PARTY_PCIE_CARD_DELL_DEFAULT_COOLING_RESPONSE_STATUS="-"
  if ! $DELL_POWEREDGE_GEN_14_OR_NEWER; then
    if "$DISABLE_THIRD_PARTY_PCIE_CARD_DELL_DEFAULT_COOLING_RESPONSE"; then
      disable_third_party_PCIe_card_Dell_default_cooling_response
      THIRD_PARTY_PCIE_CARD_DELL_DEFAULT_COOLING_RESPONSE_STATUS="Disabled"
    else
      enable_third_party_PCIe_card_Dell_default_cooling_response
      THIRD_PARTY_PCIE_CARD_DELL_DEFAULT_COOLING_RESPONSE_STATUS="Enabled"
    fi
  fi

  # Print table header periodically
  if [ $TABLE_HEADER_PRINT_COUNTER -eq $TABLE_HEADER_PRINT_INTERVAL ]; then
    print_table_header "$NUMBER_OF_DETECTED_CPUS"
    TABLE_HEADER_PRINT_COUNTER=0
  fi

  print_table_row "$INLET_TEMPERATURE" "$CPUS_TEMPERATURES" "$EXHAUST_TEMPERATURE" \
    "$TARGET_FAN_SPEED" "$POWER_CONSUMPTION" "$CURRENT_FAN_CONTROL_PROFILE" "$COMMENT"

  ((TABLE_HEADER_PRINT_COUNTER++))
  wait $SLEEP_PROCESS_PID
done
