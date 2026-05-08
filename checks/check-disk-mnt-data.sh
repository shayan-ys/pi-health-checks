#!/usr/bin/env bash
# Health check: disk usage on /mnt/data.
# Pushes heartbeat to Uptime Kuma every run. Kuma owns alerting via ntfy.
# UP  if < 90% used (warns with msg=warn:XX% if >= 70%)
# DOWN if >= 90% used
set -uo pipefail

CONFIG="/etc/pi-health/check-disk-mnt-data.env"
LOG="/var/log/pi-health/check-disk-mnt-data.log"
TS="$(date '+%Y-%m-%dT%H:%M:%S')"

if [[ ! -f "$CONFIG" ]]; then
  echo "${TS} ERROR: config not found at ${CONFIG}" >> "$LOG"
  exit 1
fi
source "$CONFIG"

ERRORS=()
STATUS="up"
MSG="OK"

# Get percent used (strip header line and trailing %)
PCENT_RAW="$(df --output=pcent /mnt/data 2>/dev/null | awk 'NR==2{gsub(/[% ]/,""); print}' || true)"

if ! [[ "$PCENT_RAW" =~ ^[0-9]+$ ]]; then
  ERRORS+=("df failed or unexpected output: ${PCENT_RAW}")
else
  PCENT="$PCENT_RAW"
  if (( PCENT >= 90 )); then
    ERRORS+=("disk usage critical: ${PCENT}% used")
  elif (( PCENT >= 70 )); then
    MSG="warn:${PCENT}%"
  else
    MSG="OK (${PCENT}% used)"
  fi
fi

if (( ${#ERRORS[@]} > 0 )); then
  STATUS="down"
  MSG="$(IFS='; '; echo "${ERRORS[*]}")"
fi

curl -fsS -m 10 -G \
  --data-urlencode "status=${STATUS}" \
  --data-urlencode "msg=${MSG}" \
  "$KUMA_PUSH_URL" >/dev/null || true

echo "${TS} ${STATUS^^}: ${MSG}" >> "$LOG"
