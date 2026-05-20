#!/bin/bash
# check-thermal-emergency — fan-agnostic safety net at CPU temp ≥ 75°C.
# Pairs with Kuma Retries=1 (fires after 2 consecutive failures, ~10 min).

set -euo pipefail
NAME=check-thermal-emergency
THRESHOLD_C="${THRESHOLD_C:-75}"
LIB="$(dirname "$0")/../lib/pi-health.sh"
[[ -r /usr/local/lib/pi-health/pi-health.sh ]] && LIB=/usr/local/lib/pi-health/pi-health.sh
# shellcheck source=../lib/pi-health.sh
. "$LIB"

load_env "$NAME"

temp=$(read_cpu_temp_c)
if [[ -z "$temp" ]]; then
  log "$NAME" "skipped (no temp source)"
  echo "skipped (no temp source)"
  exit 0
fi

if (( temp >= THRESHOLD_C )); then
  report_and_exit "$NAME" 1 "emergency: temp=${temp}C >= ${THRESHOLD_C}C"
else
  report_and_exit "$NAME" 0 "temp=${temp}C"
fi
