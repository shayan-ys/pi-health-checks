#!/bin/bash
# check-backup-age — newest file matching BACKUP_GLOB is younger than MAX_AGE_H.
#   BACKUP_GLOB    shell glob of backup files (required), e.g. /mnt/data/backups/app/app-*.tar.gz
#   MAX_AGE_H      default 36 (a daily job plus a 12-hour margin)
#   KUMA_PUSH_URL / GATUS_URL + GATUS_TOKEN  optional push targets

set -euo pipefail
NAME="${PI_HEALTH_CHECK_NAME:-check-backup-age}"
LIB="$(dirname "$0")/../lib/pi-health.sh"
[[ -r /usr/local/lib/pi-health/pi-health.sh ]] && LIB=/usr/local/lib/pi-health/pi-health.sh
# shellcheck source=../lib/pi-health.sh
. "$LIB"

load_env "$NAME"
BACKUP_GLOB="${BACKUP_GLOB:-}"
MAX_AGE_H="${MAX_AGE_H:-36}"

[[ -n "$BACKUP_GLOB" ]] || report_and_exit "$NAME" 1 "BACKUP_GLOB not set"

newest=""
newest_mtime=0
# shellcheck disable=SC2086  # the glob must expand
for f in $BACKUP_GLOB; do
  [[ -f "$f" ]] || continue
  m=$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f")
  if (( m > newest_mtime )); then newest_mtime=$m; newest=$f; fi
done

[[ -n "$newest" ]] || report_and_exit "$NAME" 1 "no backup matches ${BACKUP_GLOB}"

age_h=$(( ($(date +%s) - newest_mtime) / 3600 ))
if (( age_h >= MAX_AGE_H )); then
  report_and_exit "$NAME" 1 "newest backup $(basename "$newest") is ${age_h}h old (max ${MAX_AGE_H}h)"
fi
report_and_exit "$NAME" 0 "newest backup $(basename "$newest") is ${age_h}h old"
