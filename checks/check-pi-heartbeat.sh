#!/bin/bash
# check-pi-heartbeat — always pushes UP. Carries cpu_temp as ping= so the
# Kuma history graph becomes a CPU-temp sparkline. Goes DOWN in Kuma only
# when the cron itself stops running (heartbeat timeout).

set -euo pipefail
NAME=check-pi-heartbeat
LIB="$(dirname "$0")/../lib/pi-health.sh"
[[ -r /usr/local/lib/pi-health/pi-health.sh ]] && LIB=/usr/local/lib/pi-health/pi-health.sh
# shellcheck source=../lib/pi-health.sh
. "$LIB"

load_env "$NAME"

temp=$(read_cpu_temp_c)
msg="alive temp=${temp:-?}C"

log "$NAME" "OK: $msg"
kuma_push up "$msg" "${temp:-}"
echo "OK: $msg"
exit 0
