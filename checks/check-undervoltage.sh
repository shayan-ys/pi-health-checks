#!/bin/bash
# check-undervoltage — Pi only. vcgencmd get_throttled bit 0 = currently undervolted.
#   FAIL_ON_PAST_UNDERVOLT  set to 1 to also fail on bit 16 (occurred since boot)
#   KUMA_PUSH_URL           optional
# If running on a non-Pi (no vcgencmd), exits 0 with a "skipped" log line.

set -euo pipefail
NAME=check-undervoltage
LIB="$(dirname "$0")/../lib/pi-health.sh"
[[ -r /usr/local/lib/pi-health/pi-health.sh ]] && LIB=/usr/local/lib/pi-health/pi-health.sh
# shellcheck source=../lib/pi-health.sh
. "$LIB"

load_env "$NAME"
FAIL_ON_PAST_UNDERVOLT="${FAIL_ON_PAST_UNDERVOLT:-0}"

if ! command -v vcgencmd >/dev/null 2>&1; then
  log "$NAME" "skipped (vcgencmd not present — not a Pi)"
  exit 0
fi

# Output is "throttled=0xNNNN".
raw=$(vcgencmd get_throttled 2>/dev/null | awk -F= '{print $2}')
[[ -z "$raw" ]] && report_and_exit "$NAME" 1 "vcgencmd returned empty"

# Bit 0: currently throttled by undervoltage. Bit 16: occurred since boot.
val=$(( raw ))
cur=$(( val & 0x1 ))
past=$(( (val >> 16) & 0x1 ))

if [[ "$cur" -eq 1 ]]; then
  report_and_exit "$NAME" 1 "currently undervolted (raw=${raw})"
elif [[ "$FAIL_ON_PAST_UNDERVOLT" -eq 1 && "$past" -eq 1 ]]; then
  report_and_exit "$NAME" 1 "undervolted since boot (raw=${raw})"
else
  report_and_exit "$NAME" 0 "throttled=${raw}"
fi
