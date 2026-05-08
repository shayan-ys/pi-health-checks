#!/usr/bin/env bats

load ../test_helper/common
load ../test_helper/bats-support/load
load ../test_helper/bats-assert/load

setup() { setup_pi_health; }

@test "passes when usage below WARN_PCT" {
  mock_set df $'Use%\n42%' 0
  MOUNTPOINT=/ run run_check check-disk.sh
  assert_success
}

@test "fails at exactly WARN_PCT" {
  mock_set df $'Use%\n70%' 0
  WARN_PCT=70 CRIT_PCT=90 MOUNTPOINT=/ run run_check check-disk.sh
  assert_failure
  assert_output --partial "warn"
}

@test "fails at CRIT_PCT" {
  mock_set df $'Use%\n95%' 0
  CRIT_PCT=90 MOUNTPOINT=/ run run_check check-disk.sh
  assert_failure
  assert_output --partial "crit"
}

@test "fails when df errors" {
  mock_set df "" 1
  MOUNTPOINT=/nope run run_check check-disk.sh
  assert_failure
  assert_output --partial "df failed"
}
