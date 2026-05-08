#!/bin/bash
# check-docker-health — daemon reachable + no exited/unhealthy containers.
#   IGNORE_NAMES   regex of container names to ignore (default empty)
#   KUMA_PUSH_URL  optional

set -euo pipefail
NAME=check-docker-health
LIB="$(dirname "$0")/../lib/pi-health.sh"
[[ -r /usr/local/lib/pi-health/pi-health.sh ]] && LIB=/usr/local/lib/pi-health/pi-health.sh
# shellcheck source=../lib/pi-health.sh
. "$LIB"

load_env "$NAME"
IGNORE_NAMES="${IGNORE_NAMES:-}"

if ! docker info >/dev/null 2>&1; then
  report_and_exit "$NAME" 1 "docker daemon unreachable"
fi

# Find unhealthy or exited containers (excluding "exited (0)" — clean shutdown).
bad=$(docker ps -a --filter "status=exited" --filter "status=unhealthy" \
  --format '{{.Names}}\t{{.Status}}' \
  | awk -F'\t' '$2 !~ /Exited \(0\)/ {print}' \
  || true)

if [[ -n "$IGNORE_NAMES" ]]; then
  bad=$(echo "$bad" | grep -Ev "^(${IGNORE_NAMES})\b" || true)
fi

if [[ -n "$bad" ]]; then
  report_and_exit "$NAME" 1 "unhealthy/exited: $(echo "$bad" | tr '\n' ';' | head -c 200)"
else
  report_and_exit "$NAME" 0 "all containers healthy"
fi
