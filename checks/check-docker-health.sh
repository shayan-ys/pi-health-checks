#!/usr/bin/env bash
# Health check: all Docker containers healthy/running.
# Checks main (~/docker), monitoring (~/docker/monitoring), and homepage (~/docker/homepage) stacks.
# Pushes heartbeat to Uptime Kuma every run. Kuma owns alerting via ntfy.
# UP   if every container State=running and Status does not contain "(unhealthy)"
# DOWN if Docker daemon is unreachable, no containers found, or any container is exited/unhealthy/restarting
set -uo pipefail

CONFIG="/etc/pi-health/check-docker-health.env"
LOG="/var/log/pi-health/check-docker-health.log"
TS="$(date '+%Y-%m-%dT%H:%M:%S')"

if [[ ! -f "$CONFIG" ]]; then
  echo "${TS} ERROR: config not found at ${CONFIG}" >> "$LOG"
  exit 1
fi
source "$CONFIG"

# Guard: if Docker daemon is unreachable, push DOWN immediately
if ! docker info >/dev/null 2>&1; then
  curl -fsS -m 10 -G \
    --data-urlencode "status=down" \
    --data-urlencode "msg=docker-daemon-unreachable" \
    "$KUMA_PUSH_URL" >/dev/null || true
  echo "${TS} DOWN: docker-daemon-unreachable" >> "$LOG"
  exit 1
fi

BAD_CONTAINERS=()
ALL_CONTAINERS=""

# Get ALL containers (including exited/stopped): name, state, status
while IFS=$'\t' read -r name state status; do
  [[ -z "$name" ]] && continue
  ALL_CONTAINERS="${ALL_CONTAINERS}${name}"
  # Skip containers in "created" state (haven't started yet, not a failure)
  if [[ "$state" == "created" ]]; then
    continue
  fi
  # Flag bad states
  if [[ "$state" == "exited" || "$state" == "restarting" ]]; then
    BAD_CONTAINERS+=("${name}(${state})")
    continue
  fi
  # Flag unhealthy running containers
  if [[ "$state" == "running" && "$status" == *"(unhealthy)"* ]]; then
    BAD_CONTAINERS+=("${name}(unhealthy)")
    continue
  fi
done < <(docker ps -a --format '{{.Names}}\t{{.State}}\t{{.Status}}' 2>/dev/null || true)

# Guard: if no containers found at all, cluster is down
if [[ -z "$ALL_CONTAINERS" ]]; then
  curl -fsS -m 10 -G \
    --data-urlencode "status=down" \
    --data-urlencode "msg=no containers found / docker unreachable" \
    "$KUMA_PUSH_URL" >/dev/null || true
  echo "${TS} DOWN: no containers found / docker unreachable" >> "$LOG"
  exit 1
fi

if (( ${#BAD_CONTAINERS[@]} > 0 )); then
  STATUS="down"
  MSG="$(IFS=','; echo "${BAD_CONTAINERS[*]}")"
else
  STATUS="up"
  MSG="OK"
fi

curl -fsS -m 10 -G \
  --data-urlencode "status=${STATUS}" \
  --data-urlencode "msg=${MSG}" \
  "$KUMA_PUSH_URL" >/dev/null || true

echo "${TS} ${STATUS^^}: ${MSG}" >> "$LOG"
