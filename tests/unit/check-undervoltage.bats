#!/usr/bin/env bats

load ../test_helper/common
load ../test_helper/bats-support/load
load ../test_helper/bats-assert/load

setup() { setup_pi_health; }

@test "skips with rc 0 when vcgencmd missing" {
  rm -f "$MOCK_BIN/vcgencmd"
  run run_check check-undervoltage.sh
  assert_success
}

@test "passes on throttled=0x0" {
  mock_set vcgencmd "throttled=0x0" 0
  run run_check check-undervoltage.sh
  assert_success
}

@test "fails when bit 0 set (currently undervolted)" {
  mock_set vcgencmd "throttled=0x1" 0
  run run_check check-undervoltage.sh
  assert_failure
  assert_output --partial "currently undervolted"
}

@test "passes on bit 16 only when FAIL_ON_PAST_UNDERVOLT=0" {
  mock_set vcgencmd "throttled=0x10000" 0
  FAIL_ON_PAST_UNDERVOLT=0 run run_check check-undervoltage.sh
  assert_success
}

@test "fails on bit 16 when FAIL_ON_PAST_UNDERVOLT=1" {
  mock_set vcgencmd "throttled=0x10000" 0
  FAIL_ON_PAST_UNDERVOLT=1 run run_check check-undervoltage.sh
  assert_failure
  assert_output --partial "since boot"
}
