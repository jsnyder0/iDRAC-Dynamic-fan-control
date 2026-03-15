#!/bin/bash

# How often the table header is reprinted (rows)
readonly TABLE_HEADER_PRINT_INTERVAL=10

# Hysteresis offset — temp must drop this many degrees below LOWER_THRESHOLD
# before returning to minimum fan speed
readonly HYSTERESIS_OFFSET=2

# Hard floor — fan speed will never be set below this value. FAN_SPEED_MIN must be >= this value (enforced at startup).
readonly FAN_SPEED_HARD_FLOOR=5

# Number of consecutive IPMI failures before the script exits and hands control back to Dell
readonly MAX_CONSECUTIVE_IPMI_FAILURES=3
