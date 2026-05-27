#!/bin/bash
# check-nordvpn — NordVPN Meshnet up, verified via the kernel data plane.
#
# Rather than shelling out to `nordvpn meshnet peer list`, this probes the
# WireGuard interface directly. The CLI talks to the nordvpnd daemon over a
# unix control socket (/run/nordvpn/nordvpnd.sock) that can transiently vanish
# when nordvpnd auto-restarts (e.g. a package upgrade), even while the data
# plane — the kernel `nordlynx` interface — stays fully up. Probing the CLI
# therefore produces false-DOWN alerts. We instead assert that the interface
# exists, is up, and carries a Meshnet (100.64.0.0/10) address. This is purely
# local: no external reachability ping, so no external-dependency false alarms.
#
#   IFACE          interface to probe (default nordlynx)
#   KUMA_PUSH_URL  optional

set -euo pipefail
NAME=check-nordvpn
LIB="$(dirname "$0")/../lib/pi-health.sh"
[[ -r /usr/local/lib/pi-health/pi-health.sh ]] && LIB=/usr/local/lib/pi-health/pi-health.sh
# shellcheck source=../lib/pi-health.sh
. "$LIB"

load_env "$NAME"
IFACE="${IFACE:-nordlynx}"

if ! command -v ip >/dev/null 2>&1; then
  report_and_exit "$NAME" 1 "ip binary not found"
fi

# Signal 1: the interface exists and is up. WireGuard interfaces report
# operstate UNKNOWN (never UP), so both UP and UNKNOWN count as healthy.
link_out=$(ip -o link show "$IFACE" 2>/dev/null || true)
if [[ -z "$link_out" ]]; then
  report_and_exit "$NAME" 1 "Meshnet down: $IFACE interface missing"
fi
if ! echo "$link_out" | grep -qE 'state (UP|UNKNOWN)'; then
  state=$(echo "$link_out" | grep -oE 'state [A-Z]+' | awk '{print $2}' | head -n1)
  report_and_exit "$NAME" 1 "Meshnet down: $IFACE state ${state:-unknown}"
fi

# Signal 2: a Meshnet address (100.64.0.0/10) is bound to the interface.
addr_out=$(ip -4 addr show "$IFACE" 2>/dev/null || true)
if ! echo "$addr_out" | grep -qE 'inet 100\.'; then
  report_and_exit "$NAME" 1 "Meshnet down: no 100.x address on $IFACE"
fi

report_and_exit "$NAME" 0 "Meshnet up ($IFACE, 100.x bound)"
