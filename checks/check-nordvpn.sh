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

# `nordvpn meshnet status` returns "Meshnet is enabled" / "Meshnet is disabled".
status=$(nordvpn meshnet status 2>/dev/null || true)
if ! echo "$status" | grep -qi "enabled"; then
  report_and_exit "$NAME" 1 "Meshnet not enabled"
fi

# Peer count: each peer prints a "Hostname:" line in `peer list`.
peers=$(nordvpn meshnet peer list 2>/dev/null | grep -c -i '^Hostname:' || true)
if [[ "$peers" -lt "$MIN_PEERS" ]]; then
  report_and_exit "$NAME" 1 "peers=${peers} < min=${MIN_PEERS}"
fi
report_and_exit "$NAME" 0 "Meshnet up, peers=${peers}"
