#!/bin/bash
# check-argononed — Pi only. Verify argononed service running + I2C 0x1a present.
#   I2C_BUS        default 1
#   I2C_ADDR       default 0x1a
#   KUMA_PUSH_URL  optional
# If running on a non-Pi host (no i2cdetect), exits 0 with a "skipped" log line.

set -euo pipefail
NAME=check-argononed
LIB="$(dirname "$0")/../lib/pi-health.sh"
[[ -r /usr/local/lib/pi-health/pi-health.sh ]] && LIB=/usr/local/lib/pi-health/pi-health.sh
# shellcheck source=../lib/pi-health.sh
. "$LIB"

load_env "$NAME"
I2C_BUS="${I2C_BUS:-1}"
I2C_ADDR="${I2C_ADDR:-0x1a}"

if ! command -v i2cdetect >/dev/null 2>&1; then
  log "$NAME" "skipped (i2cdetect not present — not a Pi or i2c-tools missing)"
  exit 0
fi

if ! systemctl is-active --quiet argononed.service 2>/dev/null; then
  report_and_exit "$NAME" 1 "argononed.service not active"
fi

# i2cdetect returns "1a" in its grid when the device is present. Capture to a
# variable first so `grep -q` can't close the pipe early and trip pipefail
# (i2cdetect would exit 141 on SIGPIPE → "not present" false positive).
addr_short="${I2C_ADDR#0x}"
i2c_out=$(i2cdetect -y "$I2C_BUS" 2>/dev/null || true)
if ! echo "$i2c_out" | grep -qiE "(^|[^0-9a-f])${addr_short}([^0-9a-f]|$)"; then
  report_and_exit "$NAME" 1 "I2C ${I2C_ADDR} not present on bus ${I2C_BUS}"
fi
report_and_exit "$NAME" 0 "argononed up, I2C ${I2C_ADDR} present"
