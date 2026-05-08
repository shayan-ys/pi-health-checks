#!/usr/bin/env bash
# Health check: NordVPN Meshnet peer connectivity.
# Pushes heartbeat to Uptime Kuma every run. Kuma owns alerting via ntfy.
set -uo pipefail

KUMA_TOKEN="REPLACE_ME"
KUMA_URL="http://kuma.example:3001/api/push/${KUMA_TOKEN}"

LOG_FILE="/var/log/pi-health/check-nordvpn.log"
TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"

ERRORS=()

# NordVPN CLI can hang — wrap with timeout
PEER_OUTPUT="$(timeout 8 nordvpn meshnet peer list 2>&1 || true)"
EXIT_CODE=$?

if [[ $EXIT_CODE -eq 124 ]]; then
  ERRORS+=("nordvpn meshnet peer list timed out after 8s")
elif echo "$PEER_OUTPUT" | grep -qi 'error\|not logged in\|daemon is not running\|connect the VPN first'; then
  ERRORS+=("nordvpn error: $(echo "$PEER_OUTPUT" | head -1)")
else
  # Count non-empty, non-header lines that look like peer entries
  PEER_COUNT="$(echo "$PEER_OUTPUT" | grep -cE '^-{5,}|Hostname:' || true)"
  if [[ "$PEER_COUNT" -eq 0 ]]; then
    ERRORS+=("no Meshnet peers found (output: $(echo "$PEER_OUTPUT" | head -1 | cut -c1-80))")
  fi
fi

if (( ${#ERRORS[@]} > 0 )); then
  MSG="$(IFS='; '; echo "${ERRORS[*]}")"
  curl -fsS -m 10 -G \
    --data-urlencode "status=down" \
    --data-urlencode "msg=${MSG}" \
    "$KUMA_URL" >/dev/null || true
  echo "${TIMESTAMP} FAIL: ${MSG}" >> "$LOG_FILE"
  exit 1
fi

curl -fsS -m 10 -G \
  --data-urlencode "status=up" \
  --data-urlencode "msg=OK" \
  "$KUMA_URL" >/dev/null || true
echo "${TIMESTAMP} OK" >> "$LOG_FILE"
exit 0
