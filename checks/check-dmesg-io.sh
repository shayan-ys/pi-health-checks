#!/bin/bash
# check-dmesg-io — flag NEW dmesg I/O errors on /dev/sd* since last run.
# Uses a state file with the last seen line so repeats don't re-alert.
#   STATE_FILE    default ${PI_HEALTH_STATE_DIR}/dmesg-io.state
#   PATTERN       default 'I/O error.*sd[a-z]'
#   KUMA_PUSH_URL optional

set -euo pipefail
NAME=check-dmesg-io
LIB="$(dirname "$0")/../lib/pi-health.sh"
[[ -r /usr/local/lib/pi-health/pi-health.sh ]] && LIB=/usr/local/lib/pi-health/pi-health.sh
# shellcheck source=../lib/pi-health.sh
. "$LIB"

load_env "$NAME"
STATE_FILE="${STATE_FILE:-${PI_HEALTH_STATE_DIR}/dmesg-io.state}"
PATTERN="${PATTERN:-I/O error.*sd[a-z]}"

mkdir -p "$(dirname "$STATE_FILE")"
prev=""
[[ -r "$STATE_FILE" ]] && prev="$(cat "$STATE_FILE")"

current=$(dmesg --time-format=iso 2>/dev/null | grep -E "$PATTERN" | tail -1 || true)

# Always update state, regardless of result, so the next run compares against
# the latest line (we want NEW errors, not "any error in dmesg buffer").
echo "$current" > "$STATE_FILE"

if [[ -n "$current" && "$current" != "$prev" ]]; then
  report_and_exit "$NAME" 1 "new I/O error: $(echo "$current" | head -c 200)"
fi
report_and_exit "$NAME" 0 "no new I/O errors"
