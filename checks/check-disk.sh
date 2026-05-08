#!/bin/bash
# check-disk — warn at WARN_PCT, crit at CRIT_PCT for MOUNTPOINT.
#   MOUNTPOINT  default /
#   WARN_PCT    default 70
#   CRIT_PCT    default 90
#   KUMA_PUSH_URL  optional Kuma push monitor URL

set -euo pipefail
NAME=check-disk
LIB="$(dirname "$0")/../lib/pi-health.sh"
[[ -r /usr/local/lib/pi-health/pi-health.sh ]] && LIB=/usr/local/lib/pi-health/pi-health.sh
# shellcheck source=../lib/pi-health.sh
. "$LIB"

load_env "$NAME"
MOUNTPOINT="${MOUNTPOINT:-/}"
WARN_PCT="${WARN_PCT:-70}"
CRIT_PCT="${CRIT_PCT:-90}"

if ! pct=$(df --output=pcent "$MOUNTPOINT" 2>/dev/null | tail -1 | tr -d ' %'); then
  report_and_exit "$NAME" 1 "df failed for $MOUNTPOINT"
fi

if [[ "$pct" -ge "$CRIT_PCT" ]]; then
  report_and_exit "$NAME" 1 "${MOUNTPOINT} ${pct}% >= crit ${CRIT_PCT}%"
elif [[ "$pct" -ge "$WARN_PCT" ]]; then
  # Warn maps to "down" for Kuma — Kuma has no warn state.
  report_and_exit "$NAME" 1 "${MOUNTPOINT} ${pct}% >= warn ${WARN_PCT}%"
else
  report_and_exit "$NAME" 0 "${MOUNTPOINT} ${pct}%"
fi
