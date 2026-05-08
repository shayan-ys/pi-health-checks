#!/usr/bin/env bats

load ../test_helper/common
load ../test_helper/bats-support/load
load ../test_helper/bats-assert/load

setup() { setup_pi_health; }

@test "passes when mountpoint -q returns 0" {
  mock_set mountpoint "" 0
  MOUNTPOINT=/data run run_check check-mountpoint.sh
  assert_success
}

@test "fails when mountpoint -q returns nonzero" {
  mock_set mountpoint "" 1
  MOUNTPOINT=/data run run_check check-mountpoint.sh
  assert_failure
  assert_output --partial "NOT mounted"
}
