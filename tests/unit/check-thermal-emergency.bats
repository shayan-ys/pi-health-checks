#!/usr/bin/env bats

load ../test_helper/common
load ../test_helper/bats-support/load
load ../test_helper/bats-assert/load

setup() {
  setup_pi_health
  export PI_HEALTH_TEMP_FILE="$BATS_TEST_TMPDIR/temp"
}

set_temp() { echo "${1}000" > "$PI_HEALTH_TEMP_FILE"; }

@test "passes when temp is 70C (below threshold)" {
  set_temp 70
  run run_check check-thermal-emergency.sh
  assert_success
}

@test "passes when temp is 74C (just below 75)" {
  set_temp 74
  run run_check check-thermal-emergency.sh
  assert_success
}

@test "fails when temp is exactly 75C" {
  set_temp 75
  run run_check check-thermal-emergency.sh
  assert_failure
  assert_output --partial "75"
}

@test "fails when temp is 80C (well above)" {
  set_temp 80
  run run_check check-thermal-emergency.sh
  assert_failure
}

@test "respects THRESHOLD_C override via env" {
  set_temp 72
  THRESHOLD_C=70 run run_check check-thermal-emergency.sh
  assert_failure
}

@test "skips with rc 0 when no temp source" {
  rm -f "$PI_HEALTH_TEMP_FILE"
  run run_check check-thermal-emergency.sh
  assert_success
  assert_output --partial "skipped"
}
