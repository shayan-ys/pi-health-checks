#!/bin/bash
# check-meshnet-routing — every NordVPN Meshnet peer can reach this host's
# Docker-published services.
#
# Why this exists: a published Docker port is DNAT'd to the bridge subnet (e.g.
# 172.18.0.0/16) and then *forwarded*, which NordVPN's firewall only permits for
# peers that have been granted "routing" permission. NordVPN has no
# "default routing permission for new peers" setting, and new devices joining the
# account default to routing DISABLED. So a freshly-added peer can ping this host
# yet silently cannot open ANY Dockerised service — a confusing, recurring trap.
#
# This check surfaces that (DOWN if any peer lacks routing) and, when
# ALLOW_ALL_PEERS_ROUTING=true, self-heals by granting routing to every peer that
# lacks it — so any device added to the account starts working within one cron tick.
#
#   ALLOW_ALL_PEERS_ROUTING  true => grant routing to peers missing it.
#                            Default false => report-only (DOWN if any lack it).
#   KUMA_PUSH_URL            optional
#
# Requires the invoking user to have NordVPN CLI access (the nordvpnd unix socket
# / `nordvpn` group). That socket can transiently vanish on daemon restart; an
# unavailable/empty peer list is reported as UP-with-skip, not a false DOWN
# (mirrors check-nordvpn's data-plane-vs-control-plane reasoning).

set -euo pipefail
NAME=check-meshnet-routing
LIB="$(dirname "$0")/../lib/pi-health.sh"
[[ -r /usr/local/lib/pi-health/pi-health.sh ]] && LIB=/usr/local/lib/pi-health/pi-health.sh
# shellcheck source=../lib/pi-health.sh
. "$LIB"

load_env "$NAME"
ALLOW_ALL_PEERS_ROUTING="${ALLOW_ALL_PEERS_ROUTING:-false}"

if ! command -v nordvpn >/dev/null 2>&1; then
  report_and_exit "$NAME" 1 "nordvpn CLI not found"
fi

list="$(nordvpn meshnet peer list 2>/dev/null || true)"
if [[ -z "$list" ]]; then
  report_and_exit "$NAME" 0 "skipped: peer list unavailable (daemon down?)"
fi

# Associate each "Hostname:" with its "Allow Routing:" flag. The singular
# "Allow Routing" is OUR grant to the peer; "Allows Routing" is the peer's grant
# to us — the anchored regex matches only the former. The "This device" block
# has a Hostname but no Allow Routing line, so it is naturally skipped.
disabled=()
host=""
while IFS= read -r line; do
  line="${line%$'\r'}"
  if [[ "$line" =~ ^Hostname:[[:space:]]+(.*)$ ]]; then
    host="${BASH_REMATCH[1]}"
  elif [[ "$line" =~ ^Allow[[:space:]]Routing:[[:space:]]+disabled ]]; then
    [[ -n "$host" ]] && disabled+=("$host")
  fi
done <<<"$list"

if [[ "${#disabled[@]}" -eq 0 ]]; then
  report_and_exit "$NAME" 0 "all peers routing-enabled"
fi

if [[ "$ALLOW_ALL_PEERS_ROUTING" != "true" ]]; then
  report_and_exit "$NAME" 1 \
    "${#disabled[@]} peer(s) missing routing: ${disabled[*]} (set ALLOW_ALL_PEERS_ROUTING=true to auto-grant)"
fi

# Self-heal: grant routing to every peer that lacked it.
failed=()
for h in "${disabled[@]}"; do
  if nordvpn meshnet peer routing allow "$h" >/dev/null 2>&1; then
    log "$NAME" "granted routing to $h"
  else
    failed+=("$h")
  fi
done

if [[ "${#failed[@]}" -gt 0 ]]; then
  report_and_exit "$NAME" 1 "failed to grant routing to: ${failed[*]}"
fi
report_and_exit "$NAME" 0 "granted routing to ${#disabled[@]} peer(s): ${disabled[*]}"
