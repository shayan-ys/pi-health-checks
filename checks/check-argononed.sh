#!/usr/bin/env bash
# Health check: argononed systemd service + I2C fan controller device.
# Pushes heartbeat to Uptime Kuma every run. Kuma owns alerting via ntfy.
set -uo pipefail

KUMA_TOKEN="8F0eYpcMVi13OHEc4LkVmAfSPWRXMcLS"
KUMA_URL="http://kuma.example:3001/api/push/${KUMA_TOKEN}"
I2CDETECT="/usr/sbin/i2cdetect"

ERRORS=()

SERVICE_STATE="$(systemctl is-active argononed 2>&1 || true)"
if [[ "$SERVICE_STATE" != "active" ]]; then
  ERRORS+=("argononed not active (${SERVICE_STATE})")
fi

if [[ ! -x "$I2CDETECT" ]]; then
  ERRORS+=("${I2CDETECT} missing or not executable")
else
  I2C_OUTPUT="$("$I2CDETECT" -y -q 1 2>&1 || true)"
  if ! echo "$I2C_OUTPUT" | grep -q ' 1a '; then
    ERRORS+=("I2C device 0x1a not found on bus 1")
  fi
fi

if (( ${#ERRORS[@]} > 0 )); then
  MSG="$(IFS='; '; echo "${ERRORS[*]}")"
  curl -fsS -m 10 -G \
    --data-urlencode "status=down" \
    --data-urlencode "msg=${MSG}" \
    "$KUMA_URL" >/dev/null || true
  echo "FAIL: ${MSG}"
  exit 1
fi

curl -fsS -m 10 -G \
  --data-urlencode "status=up" \
  --data-urlencode "msg=OK" \
  "$KUMA_URL" >/dev/null || true
echo "OK"
exit 0
