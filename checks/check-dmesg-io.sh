#!/usr/bin/env bash
# Health check: NEW USB I/O errors in dmesg since last run.
# Uses a state file to track watermark so only new errors trigger DOWN.
# Pushes heartbeat to Uptime Kuma every run. Kuma owns alerting via ntfy.
set -uo pipefail

KUMA_TOKEN="bLSKebvZinVmYuJ5DQHhOZmHoAbX62YF"
KUMA_URL="http://kuma.example:3001/api/push/${KUMA_TOKEN}"
STATE_FILE="/var/lib/pi-health/dmesg-io.state"
LOG_FILE="/var/log/pi-health/check-dmesg-io.log"
TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"

ERRORS=()

# Collect all I/O error lines from dmesg (numeric kernel timestamps, NOT -T).
# -T converts timestamps to wall-clock strings, which breaks the numeric regex below.
DMESG_OUTPUT="$(dmesg 2>/dev/null | grep -iE 'I/O error.*sd[a-z]|Buffer I/O error.*sd[a-z]' || true)"

# Extract raw kernel timestamps (e.g. [1234567.890]) for watermark comparisons
# Format: [NNNNN.MMM] at start of each line
get_kernel_ts() {
  echo "$1" | grep -oP '^\[\s*\K[0-9]+\.[0-9]+(?=\])' || true
}

# Get latest kernel timestamp from ALL dmesg (for watermark updates)
LATEST_TS="$(dmesg 2>/dev/null | grep -oP '^\[\s*\K[0-9]+\.[0-9]+(?=\])' | tail -1 || true)"
LATEST_TS="${LATEST_TS:-0.000}"

# First-run: state file missing → record current watermark, exit UP without alerting
if [[ ! -f "$STATE_FILE" ]]; then
  echo "$LATEST_TS" > "$STATE_FILE"
  curl -fsS -m 10 -G \
    --data-urlencode "status=up" \
    --data-urlencode "msg=OK (first run, watermark set)" \
    "$KUMA_URL" >/dev/null || true
  echo "${TIMESTAMP} OK (first run, watermark=${LATEST_TS})" >> "$LOG_FILE"
  exit 0
fi

LAST_TS="$(tr -d '[:space:]' < "$STATE_FILE")"
LAST_TS="${LAST_TS:-0.000}"

# Filter error lines whose kernel timestamp > last seen
NEW_ERRORS=""
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  LINE_TS="$(get_kernel_ts "$line")"
  [[ -z "$LINE_TS" ]] && continue
  # Use awk for floating-point comparison
  if awk "BEGIN { exit !($LINE_TS > $LAST_TS) }"; then
    NEW_ERRORS="${NEW_ERRORS}${line}"$'\n'
  fi
done <<< "$DMESG_OUTPUT"

# Update watermark to latest dmesg timestamp (advance even on quiet runs)
echo "$LATEST_TS" > "$STATE_FILE"

if [[ -n "$NEW_ERRORS" ]]; then
  ERROR_COUNT="$(echo "$NEW_ERRORS" | grep -c . || true)"
  FIRST_LINE="$(echo "$NEW_ERRORS" | head -1 | cut -c1-100)"
  MSG="${ERROR_COUNT} new I/O error(s): ${FIRST_LINE}"
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
