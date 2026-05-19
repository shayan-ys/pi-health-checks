#!/bin/bash
# check-argononed — Pi only. Verify argononed service running + I2C 0x1a present.
#   I2C_BUS        default 1
#   I2C_ADDR       default 0x1a
#   KUMA_PUSH_URL  optional
#   PI_MODEL_FILE  override path for Pi model detection (default: /sys/firmware/devicetree/base/model)
# On non-Pi hosts (no i2cdetect and no Pi hardware signature): exits 0 with a "skipped" log line.
# On Pi hosts with i2cdetect missing: fails loud so Kuma gets a DOWN heartbeat.

set -euo pipefail
NAME=check-argononed
LIB="$(dirname "$0")/../lib/pi-health.sh"
[[ -r /usr/local/lib/pi-health/pi-health.sh ]] && LIB=/usr/local/lib/pi-health/pi-health.sh
# shellcheck source=../lib/pi-health.sh
. "$LIB"

load_env "$NAME"
I2C_BUS="${I2C_BUS:-1}"
I2C_ADDR="${I2C_ADDR:-0x1a}"
PI_MODEL_FILE="${PI_MODEL_FILE:-/sys/firmware/devicetree/base/model}"

# Locate i2cdetect: check PATH first, then common sbin locations that cron
# omits from its default PATH (/usr/bin:/bin).
I2CDETECT="$(command -v i2cdetect 2>/dev/null || true)"
if [[ -z "$I2CDETECT" ]]; then
  for p in /usr/sbin/i2cdetect /sbin/i2cdetect; do
    [[ -x "$p" ]] && I2CDETECT="$p" && break
  done
fi

if [[ -z "$I2CDETECT" ]]; then
  if [[ -r "$PI_MODEL_FILE" ]] && grep -qi 'raspberry pi' "$PI_MODEL_FILE"; then
    report_and_exit "$NAME" 1 "i2cdetect not installed (apt install i2c-tools)"
  fi
  log "$NAME" "skipped (not a Pi)"
  exit 0
fi

if ! systemctl is-active --quiet argononed.service 2>/dev/null; then
  report_and_exit "$NAME" 1 "argononed.service not active"
fi

# i2cdetect returns "1a" in its grid when the device is present. Capture to a
# variable first so `grep -q` can't close the pipe early and trip pipefail
# (i2cdetect would exit 141 on SIGPIPE → "not present" false positive).
addr_short="${I2C_ADDR#0x}"
i2c_out=$("$I2CDETECT" -y "$I2C_BUS" 2>/dev/null || true)
if ! echo "$i2c_out" | grep -qiE "(^|[^0-9a-f])${addr_short}([^0-9a-f]|$)"; then
  report_and_exit "$NAME" 1 "I2C ${I2C_ADDR} not present on bus ${I2C_BUS}"
fi
report_and_exit "$NAME" 0 "argononed up, I2C ${I2C_ADDR} present"
