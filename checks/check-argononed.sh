#!/bin/bash
# check-argononed — daemon liveness check via systemctl. Bus-collision-free
# (does NOT probe I²C — that was the previous approach and caused intermittent
# false DOWNs when argononed was mid-transaction with 0x1a).
#
# Skips with rc 0 on non-systemd hosts (e.g. dev machines without argononed
# installed at all — distinct from "installed but failed").

set -euo pipefail
NAME=check-argononed
LIB="$(dirname "$0")/../lib/pi-health.sh"
[[ -r /usr/local/lib/pi-health/pi-health.sh ]] && LIB=/usr/local/lib/pi-health/pi-health.sh
# shellcheck source=../lib/pi-health.sh
. "$LIB"

load_env "$NAME"

# If systemctl isn't on the system at all, this isn't a Pi-with-argononed —
# skip silently (matches the pattern used by check-undervoltage for vcgencmd).
if ! command -v systemctl >/dev/null 2>&1; then
  log "$NAME" "skipped (systemctl not present)"
  exit 0
fi

# `systemctl is-active argononed` prints "active" + rc=0 if running.
# Anything else (inactive, failed, activating, deactivating) → rc != 0.
state=$(systemctl is-active argononed 2>/dev/null || true)

if [[ "$state" == "active" ]]; then
  report_and_exit "$NAME" 0 "argononed active"
else
  report_and_exit "$NAME" 1 "argononed not active (state=${state:-unknown})"
fi
