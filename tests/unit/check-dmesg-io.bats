#!/usr/bin/env bats

load ../test_helper/common
load ../test_helper/bats-support/load
load ../test_helper/bats-assert/load

setup() { setup_pi_health; }

@test "passes when dmesg has no I/O errors" {
  mock_set dmesg "" 0
  run run_check check-dmesg-io.sh
  assert_success
  assert_output --partial "no new"
}

@test "fails on first observation of a new I/O error" {
  mock_set dmesg "[2026-05-08T12:00:00Z] blk_update_request: I/O error, dev sda, sector 12345" 0
  run run_check check-dmesg-io.sh
  assert_failure
  assert_output --partial "new I/O error"
}

@test "second run with same line passes (state-file dedup)" {
  mock_set dmesg "[2026-05-08T12:00:00Z] blk_update_request: I/O error, dev sda, sector 12345" 0
  run run_check check-dmesg-io.sh
  assert_failure
  # Second run, same dmesg output — should NOT re-fire.
  run run_check check-dmesg-io.sh
  assert_success
}
