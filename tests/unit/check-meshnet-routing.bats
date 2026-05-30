#!/usr/bin/env bats

load ../test_helper/common
load ../test_helper/bats-support/load
load ../test_helper/bats-assert/load

setup() { setup_pi_health; }

# Install an arg-aware `nordvpn` mock. The static mock ignores args, but this
# check calls `nordvpn` two different ways (`meshnet peer list` and
# `meshnet peer routing allow <host>`), so the mock branches on its arguments.
#   $1 peerlist  — what `nordvpn meshnet peer list` prints
#   $2 allow_rc  — exit code for `routing allow` calls (default 0)
# Hosts passed to `routing allow` are appended to $MOCK_BIN/.nordvpn.allowed.
mock_nordvpn() {
  printf '%s' "$1" > "$MOCK_BIN/.nordvpn.peerlist"
  echo "${2:-0}" > "$MOCK_BIN/.nordvpn.allow_rc"
  : > "$MOCK_BIN/.nordvpn.allowed"
  cat > "$MOCK_BIN/nordvpn" <<'EOF'
#!/bin/bash
dir="$(dirname "$0")"
if [[ "$1 $2 $3" == "meshnet peer list" ]]; then
  cat "$dir/.nordvpn.peerlist" 2>/dev/null
  exit 0
fi
if [[ "$1 $2 $3 $4" == "meshnet peer routing allow" ]]; then
  echo "$5" >> "$dir/.nordvpn.allowed"
  exit "$(cat "$dir/.nordvpn.allow_rc" 2>/dev/null || echo 0)"
fi
exit 0
EOF
  chmod +x "$MOCK_BIN/nordvpn"
}

# Realistic peer-list fixture. The "This device" block has a Hostname but no
# Allow Routing line (must be skipped). $1/$2 are the routing flags for the two
# peers (mac, phone).
peerlist() {
  cat <<EOF
This device:
Nickname: self
Hostname: self.nord
IP: 100.99.117.13

Local Peers:
Nickname: mac
Hostname: mac.nord
Allow Incoming Traffic: enabled
Allow Routing: ${1:-enabled}
Allows Routing: disabled

Nickname: phone
Hostname: phone.nord
Allow Incoming Traffic: enabled
Allow Routing: ${2:-enabled}
Allows Routing: disabled
EOF
}

@test "fails when nordvpn CLI is missing" {
  rm -f "$MOCK_BIN/nordvpn"
  PATH="$MOCK_BIN:/usr/bin:/bin" run run_check check-meshnet-routing.sh
  assert_failure
  assert_output --partial "nordvpn CLI not found"
}

@test "skips (up) when peer list is unavailable" {
  mock_nordvpn ""
  run run_check check-meshnet-routing.sh
  assert_success
  assert_output --partial "skipped"
}

@test "passes when all peers are routing-enabled" {
  mock_nordvpn "$(peerlist enabled enabled)"
  run run_check check-meshnet-routing.sh
  assert_success
  assert_output --partial "all peers routing-enabled"
}

@test "fails (report-only default) when a peer lacks routing" {
  mock_nordvpn "$(peerlist enabled disabled)"
  run run_check check-meshnet-routing.sh
  assert_failure
  assert_output --partial "missing routing: phone.nord"
  # report-only must NOT have attempted any grant
  run cat "$MOCK_BIN/.nordvpn.allowed"
  assert_output ""
}

@test "self-heals and passes when ALLOW_ALL_PEERS_ROUTING=true" {
  mock_nordvpn "$(peerlist disabled disabled)"
  ALLOW_ALL_PEERS_ROUTING=true run run_check check-meshnet-routing.sh
  assert_success
  assert_output --partial "granted routing to 2 peer(s)"
  # both disabled peers must have been granted
  run cat "$MOCK_BIN/.nordvpn.allowed"
  assert_line "mac.nord"
  assert_line "phone.nord"
}

@test "fails when a grant attempt errors under self-heal" {
  mock_nordvpn "$(peerlist enabled disabled)" 1
  ALLOW_ALL_PEERS_ROUTING=true run run_check check-meshnet-routing.sh
  assert_failure
  assert_output --partial "failed to grant routing to: phone.nord"
}
