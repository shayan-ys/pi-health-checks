#!/usr/bin/env bats

load ../test_helper/common
load ../test_helper/bats-support/load
load ../test_helper/bats-assert/load

setup() { setup_pi_health; }

# Install an arg-aware `ip` mock. The static mock fakes ignore args, but this
# check calls `ip` twice with different args (`-o link show` and `-4 addr
# show`), so we need a script that branches on its arguments. The two outputs
# are written to side files the mock reads at runtime.
#   $1 link_out  — what `ip -o link show <iface>` prints (empty => exit 1)
#   $2 addr_out  — what `ip -4 addr show <iface>` prints
mock_ip() {
  printf '%s' "$1" > "$MOCK_BIN/.ip.link"
  printf '%s' "$2" > "$MOCK_BIN/.ip.addr"
  cat > "$MOCK_BIN/ip" <<'EOF'
#!/bin/bash
dir="$(dirname "$0")"
if [[ "$1" == "-o" && "$2" == "link" ]]; then
  link="$(cat "$dir/.ip.link" 2>/dev/null)"
  [[ -z "$link" ]] && exit 1
  printf '%s\n' "$link"
  exit 0
fi
if [[ "$1" == "-4" && "$2" == "addr" ]]; then
  printf '%s\n' "$(cat "$dir/.ip.addr" 2>/dev/null)"
  exit 0
fi
exit 0
EOF
  chmod +x "$MOCK_BIN/ip"
}

@test "fails when ip binary is missing" {
  rm -f "$MOCK_BIN/ip"
  # Restrict PATH to the mock bin plus the standard coreutils dirs (which hold
  # dirname/cat/etc.) but NOT the sbin dirs where `ip` normally lives, so the
  # missing-binary branch is exercised without a real `ip` leaking in.
  PATH="$MOCK_BIN:/usr/bin:/bin" run run_check check-nordvpn.sh
  assert_failure
  assert_output --partial "ip binary not found"
}

@test "fails when interface is missing" {
  mock_ip "" ""
  run run_check check-nordvpn.sh
  assert_failure
  assert_output --partial "interface missing"
}

@test "fails when interface is in DOWN state" {
  mock_ip "5: nordlynx: <POINTOPOINT,NOARP> mtu 1420 state DOWN mode DEFAULT" \
          "5: nordlynx    inet 100.96.0.5/32 scope global nordlynx"
  run run_check check-nordvpn.sh
  assert_failure
  assert_output --partial "state DOWN"
}

@test "fails when up but no 100.x address bound" {
  mock_ip "5: nordlynx: <POINTOPOINT,NOARP,UP,LOWER_UP> mtu 1420 state UNKNOWN mode DEFAULT" \
          "5: nordlynx    inet 10.5.0.2/24 scope global nordlynx"
  run run_check check-nordvpn.sh
  assert_failure
  assert_output --partial "no 100.x"
}

@test "passes when interface up (UNKNOWN) with 100.x address" {
  mock_ip "5: nordlynx: <POINTOPOINT,NOARP,UP,LOWER_UP> mtu 1420 state UNKNOWN mode DEFAULT" \
          "5: nordlynx    inet 100.96.0.5/32 scope global nordlynx"
  run run_check check-nordvpn.sh
  assert_success
  assert_output --partial "Meshnet up"
}

@test "operstate UNKNOWN passes (WireGuard quirk regression guard)" {
  # WireGuard interfaces never report state UP, only UNKNOWN. Accepting only
  # UP would be a permanent false-DOWN. This guards that UNKNOWN is healthy.
  mock_ip "7: nordlynx: <POINTOPOINT,NOARP,UP,LOWER_UP> mtu 1420 state UNKNOWN mode DEFAULT group default qlen 1000" \
          "7: nordlynx    inet 100.64.10.20/32 scope global nordlynx"
  run run_check check-nordvpn.sh
  assert_success
  assert_output --partial "Meshnet up"
}
