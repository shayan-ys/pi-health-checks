#!/usr/bin/env bash
# Health check: Pi under-voltage (vcgencmd throttled bit 0).
# Pushes heartbeat to Uptime Kuma every run. Kuma owns alerting via ntfy.
set -uo pipefail

KUMA_TOKEN="K8b5uYWdNl9tEnxKuKXPsWE1yIPBYiFH"
KUMA_URL="http://kuma.example:3001/api/push/${KUMA_TOKEN}"

ERRORS=()

if ! command -v vcgencmd &>/dev/null; then
  ERRORS+=("vcgencmd missing")
else
  THROTTLED_RAW="$(vcgencmd get_throttled 2>&1 || true)"
  if ! echo "$THROTTLED_RAW" | grep -qE '^throttled=0x[0-9a-fA-F]+$'; then
    ERRORS+=("unexpected vcgencmd output: ${THROTTLED_RAW}")
  else
    THROTTLED_HEX="${THROTTLED_RAW#throttled=}"
    THROTTLED_DEC="$(printf '%d' "${THROTTLED_HEX}")"
    if (( THROTTLED_DEC & 0x1 )); then
      ERRORS+=("under-voltage now (${THROTTLED_RAW})")
    fi
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
