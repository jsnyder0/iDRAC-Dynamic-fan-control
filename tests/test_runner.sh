#!/bin/bash

# Minimal pure-bash test runner. No external dependencies.

PASS=0
FAIL=0
ERRORS=()

assert_equals() {
  local actual="$1"
  local expected="$2"
  local description="$3"
  if [ "$actual" = "$expected" ]; then
    ((PASS++))
    printf "  PASS  %s\n" "$description"
  else
    ((FAIL++))
    ERRORS+=("FAIL: $description")
    printf "  FAIL  %s\n    expected: %s\n    actual:   %s\n" "$description" "$expected" "$actual"
  fi
}

assert_exit_code() {
  local actual="$1"
  local expected="$2"
  local description="$3"
  assert_equals "$actual" "$expected" "$description"
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local description="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    ((PASS++))
    printf "  PASS  %s\n" "$description"
  else
    ((FAIL++))
    ERRORS+=("FAIL: $description")
    printf "  FAIL  %s\n    expected to contain: %s\n    actual: %s\n" "$description" "$needle" "$haystack"
  fi
}

print_summary() {
  printf "\n──────────────────────────────────────\n"
  printf "  Results: %d passed, %d failed\n" "$PASS" "$FAIL"
  printf "──────────────────────────────────────\n"
  if [ $FAIL -gt 0 ]; then
    exit 1
  fi
}
