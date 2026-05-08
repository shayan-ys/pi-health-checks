#!/bin/bash
# check-nordvpn — NordVPN Meshnet enabled and at least MIN_PEERS peers visible.
#   MIN_PEERS      default 1
#   KUMA_PUSH_URL  optional

set -euo pipefail
NAME=check-nordvpn
LIB="$(dirname "$0")/../lib/pi-health.sh"
[[ -r /usr/local/lib/pi-health/pi-health.sh ]] && LIB=/usr/local/lib/pi-health/pi-health.sh
# shellcheck source=../lib/pi-health.sh
. "$LIB"

load_env "$NAME"
MIN_PEERS="${MIN_PEERS:-1}"

if ! command -v nordvpn >/dev/null 2>&1; then
  report_and_exit "$NAME" 1 "nordvpn binary not found"
fi

# Detection: `nordvpn meshnet peer list` succeeds only when Meshnet is on and
# the daemon is reachable. NordVPN 4.x removed the `meshnet status` subcommand,
# so we use peer-list output as a single source of truth.
peer_out=$(nordvpn meshnet peer list 2>&1 || true)
if echo "$peer_out" | grep -qiE 'meshnet is (off|disabled|not enabled)|not logged in|daemon is not'; then
  report_and_exit "$NAME" 1 "Meshnet not enabled"
fi
if ! echo "$peer_out" | grep -qiE '^This device:|^Hostname:'; then
  report_and_exit "$NAME" 1 "nordvpn peer list returned unexpected output"
fi

# Peer count: each peer prints a "Hostname:" line. Subtract 1 for "This device".
total_hosts=$(echo "$peer_out" | grep -ciE '^Hostname:' || true)
peers=$(( total_hosts > 0 ? total_hosts - 1 : 0 ))
if [[ "$peers" -lt "$MIN_PEERS" ]]; then
  report_and_exit "$NAME" 1 "peers=${peers} < min=${MIN_PEERS}"
fi
report_and_exit "$NAME" 0 "Meshnet up, peers=${peers}"
