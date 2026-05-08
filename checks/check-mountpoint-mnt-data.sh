#!/usr/bin/env bash
# Health check: /mnt/data is mounted.
# Pushes heartbeat to Uptime Kuma every run. Kuma owns alerting via ntfy.
set -uo pipefail

CONFIG="/etc/pi-health/check-mountpoint-mnt-data.env"
LOG="/var/log/pi-health/check-mountpoint-mnt-data.log"
TS="$(date '+%Y-%m-%dT%H:%M:%S')"

if [[ ! -f "$CONFIG" ]]; then
  echo "${TS} ERROR: config not found at ${CONFIG}" >> "$LOG"
  exit 1
fi
source "$CONFIG"

STATUS="up"
MSG="OK"

if ! mountpoint -q /mnt/data 2>/dev/null; then
  STATUS="down"
  MSG="/mnt/data is not mounted"
fi

curl -fsS -m 10 -G \
  --data-urlencode "status=${STATUS}" \
  --data-urlencode "msg=${MSG}" \
  "$KUMA_PUSH_URL" >/dev/null || true

echo "${TS} ${STATUS^^}: ${MSG}" >> "$LOG"
