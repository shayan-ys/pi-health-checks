#!/usr/bin/env bats

load ../test_helper/common
load ../test_helper/bats-support/load
load ../test_helper/bats-assert/load

setup() { setup_pi_health; }

@test "fails when nordvpn binary is missing" {
  rm -f "$MOCK_BIN/nordvpn"
  run run_check check-nordvpn.sh
  assert_failure
  assert_output --partial "not found"
}

@test "fails when meshnet not enabled" {
  mock_set nordvpn "Meshnet is disabled" 0
  run run_check check-nordvpn.sh
  assert_failure
  assert_output --partial "not enabled"
}

@test "passes with enabled + N peers (mock returns same for both calls)" {
  # The lone mock returns its programmed output for BOTH `meshnet status`
  # and `meshnet peer list`. We program output that satisfies both:
  # - contains "enabled"
  # - contains 2 lines starting with "Hostname:"
  mock_set nordvpn $'Meshnet is enabled\nHostname: a.nord\nHostname: b.nord' 0
  MIN_PEERS=2 run run_check check-nordvpn.sh
  assert_success
  assert_output --partial "peers=2"
}

@test "fails when peers below MIN_PEERS" {
  mock_set nordvpn $'Meshnet is enabled\nHostname: a.nord' 0
  MIN_PEERS=2 run run_check check-nordvpn.sh
  assert_failure
}
