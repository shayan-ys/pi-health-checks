#!/bin/bash
# lib/pi-health.sh — shared helpers for pi-health-checks.
# Source from each check script via:
#   . "$(dirname "$0")/../lib/pi-health.sh"   # source-tree
# or, after install:
#   . /usr/local/lib/pi-health/pi-health.sh

# Resolve install dirs with override hooks (tests use these to redirect to tmp).
PI_HEALTH_LOG_DIR="${PI_HEALTH_LOG_DIR:-/var/log/pi-health}"
PI_HEALTH_STATE_DIR="${PI_HEALTH_STATE_DIR:-/var/lib/pi-health}"
PI_HEALTH_CONF_DIR="${PI_HEALTH_CONF_DIR:-/etc/pi-health}"

# Read /etc/pi-health/<name>.env if present.
load_env() {
  local name="$1"
  local conf="${PI_HEALTH_CONF_DIR}/${name}.env"
  # shellcheck disable=SC1090
  [[ -r "$conf" ]] && . "$conf" || true
}

# Append a timestamped line to /var/log/pi-health/<name>.log.
# Silently no-ops if the dir isn't writable (e.g. tests without root).
log() {
  local name="$1"; shift
  local logfile="${PI_HEALTH_LOG_DIR}/${name}.log"
  if [[ -w "${PI_HEALTH_LOG_DIR}" ]] || mkdir -p "${PI_HEALTH_LOG_DIR}" 2>/dev/null; then
    printf '%s [%s] %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$name" "$*" >> "$logfile" 2>/dev/null || true
  fi
}

# Push to Kuma (or any push monitor accepting GET-with-?status=&msg=).
# No-op if KUMA_PUSH_URL is unset/empty — runs the check as exit-code-only.
# Args: <up|down> [msg]
kuma_push() {
  local status="$1"; shift
  local msg="${*:-OK}"
  [[ -z "${KUMA_PUSH_URL:-}" ]] && return 0
  # Append status + msg as URL params. Kuma accepts both GET and POST.
  local sep="?"
  [[ "$KUMA_PUSH_URL" == *"?"* ]] && sep="&"
  curl -fsS -m 10 \
    --data-urlencode "status=${status}" \
    --data-urlencode "msg=${msg}" \
    -G "${KUMA_PUSH_URL}${sep%?}" >/dev/null 2>&1 \
    || curl -fsS -m 10 -G \
       --data-urlencode "status=${status}" \
       --data-urlencode "msg=${msg}" \
       "${KUMA_PUSH_URL}" >/dev/null 2>&1 \
    || return 0   # Push failures are not check failures.
}

# Exit 0 = up, 1 = down. Always pushes if KUMA_PUSH_URL is set.
report_and_exit() {
  local name="$1" rc="$2" msg="$3"
  if [[ "$rc" -eq 0 ]]; then
    log "$name" "OK: $msg"
    kuma_push up "$msg"
    echo "OK: $msg"
  else
    log "$name" "FAIL: $msg"
    kuma_push down "$msg"
    echo "FAIL: $msg"
  fi
  exit "$rc"
}
