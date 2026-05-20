#!/bin/bash
# check-fan-thermal — alerts when daemon-reported fan state contradicts a hot CPU.
#
# Fires DOWN when temp ≥ 65°C AND (duty=0 OR duty ≥ 20%). Pairs with Kuma
# Retries=2 (3 consecutive failures = ~15 min sustained) to suppress transients.
# Defers to check-argononed when the daemon isn't active.

set -euo pipefail
NAME=check-fan-thermal
THRESHOLD_C="${THRESHOLD_C:-65}"
LIB="$(dirname "$0")/../lib/pi-health.sh"
[[ -r /usr/local/lib/pi-health/pi-health.sh ]] && LIB=/usr/local/lib/pi-health/pi-health.sh
# shellcheck source=../lib/pi-health.sh
. "$LIB"

load_env "$NAME"

# Need a temp source
temp=$(read_cpu_temp_c)
if [[ -z "$temp" ]]; then
  log "$NAME" "skipped (no temp source — not a Pi or sysfs unreadable)"
  echo "skipped (no temp source)"
  exit 0
fi

# Defer to check-argononed if daemon is dead (avoid double-alerting)
if command -v systemctl >/dev/null 2>&1; then
  state=$(systemctl is-active argononed 2>/dev/null || true)
  if [[ "$state" != "active" ]]; then
    report_and_exit "$NAME" 0 "deferring (argononed state=${state:-unknown}), temp=${temp}C"
  fi
fi

duty=$(read_argon_duty_pct)

# Cool CPU = always OK
if (( temp < THRESHOLD_C )); then
  report_and_exit "$NAME" 0 "OK temp=${temp}C duty=${duty:-?}%"
fi

# Hot CPU + no daemon-cli = temp-only failure
if [[ -z "$duty" ]]; then
  report_and_exit "$NAME" 1 "no daemon-cli, temp=${temp}C >= ${THRESHOLD_C}C"
fi

# Hot CPU + duty=0 → daemon not commanding fan
if [[ "$duty" -eq 0 ]]; then
  report_and_exit "$NAME" 1 "hot but idle: temp=${temp}C duty=0% (daemon not kicking fan)"
fi

# Hot CPU + duty ≥ 20% → cooling not effective
if (( duty >= 20 )); then
  report_and_exit "$NAME" 1 "cooling ineffective: temp=${temp}C duty=${duty}%"
fi

# duty between 1–19% with temp ≥ 65°C: low-end fan range, still warming up — pass
report_and_exit "$NAME" 0 "OK temp=${temp}C duty=${duty}% (ramping)"
