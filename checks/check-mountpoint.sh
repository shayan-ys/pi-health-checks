#!/bin/bash
# check-mountpoint — verify MOUNTPOINT is actually mounted (not the underlying dir).
#   MOUNTPOINT     default /mnt/data
#   KUMA_PUSH_URL  optional

set -euo pipefail
NAME=check-mountpoint
LIB="$(dirname "$0")/../lib/pi-health.sh"
[[ -r /usr/local/lib/pi-health/pi-health.sh ]] && LIB=/usr/local/lib/pi-health/pi-health.sh
# shellcheck source=../lib/pi-health.sh
. "$LIB"

load_env "$NAME"
MOUNTPOINT="${MOUNTPOINT:-/mnt/data}"

if mountpoint -q "$MOUNTPOINT"; then
  report_and_exit "$NAME" 0 "${MOUNTPOINT} mounted"
else
  report_and_exit "$NAME" 1 "${MOUNTPOINT} NOT mounted"
fi
