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

@test "fails on unexpected peer-list output" {
  mock_set nordvpn "some unrelated banner text" 0
  run run_check check-nordvpn.sh
  assert_failure
  assert_output --partial "unexpected output"
}

@test "passes with This device + N remote peers" {
  # Real `nordvpn meshnet peer list` prints "This device:" + Hostname for self,
  # then "Local Peers:" + Hostname per remote peer. Script subtracts self
  # from the Hostname count.
  mock_set nordvpn $'This device:\nHostname: self.nord\n\nLocal Peers:\nHostname: a.nord\nHostname: b.nord' 0
  MIN_PEERS=2 run run_check check-nordvpn.sh
  assert_success
  assert_output --partial "peers=2"
}

@test "fails when remote peers below MIN_PEERS" {
  mock_set nordvpn $'This device:\nHostname: self.nord\n\nLocal Peers:\nHostname: a.nord' 0
  MIN_PEERS=2 run run_check check-nordvpn.sh
  assert_failure
  assert_output --partial "peers=1"
}
