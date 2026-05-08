#!/bin/bash
# uninstall.sh — remove scripts, lib, and cron entries. Optionally purge /etc + /var.
#
# Usage:
#   sudo ./uninstall.sh           # remove scripts + cron entries; keep config + logs
#   sudo ./uninstall.sh --purge   # also remove /etc/pi-health, /var/log/pi-health,
#                                 # /var/lib/pi-health

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "uninstall.sh: must run as root (use sudo)" >&2
  exit 1
fi

PURGE=0
[[ "${1:-}" == "--purge" ]] && PURGE=1

ALL_CHECKS=(disk mountpoint docker-health nordvpn dmesg-io argononed undervoltage)

# Remove scripts and lib
for c in "${ALL_CHECKS[@]}"; do
  rm -f "/usr/local/bin/check-${c}.sh"
done
rm -f /usr/local/lib/pi-health/pi-health.sh
rmdir /usr/local/lib/pi-health 2>/dev/null || true

# Strip cron entries for any user that has them
strip_cron_lines() {
  local user="$1"
  if crontab -u "$user" -l >/dev/null 2>&1; then
    local tmp
    tmp="$(mktemp)"
    crontab -u "$user" -l 2>/dev/null \
      | grep -vE '/usr/local/bin/check-(disk|mountpoint|docker-health|nordvpn|dmesg-io|argononed|undervoltage)\.sh' \
      > "$tmp" || true
    crontab -u "$user" - < "$tmp"
    rm -f "$tmp"
  fi
}

# Try root + every user with a crontab
strip_cron_lines root
if command -v getent >/dev/null 2>&1; then
  while IFS=: read -r user _; do
    [[ "$user" == "root" ]] && continue
    strip_cron_lines "$user" 2>/dev/null || true
  done < <(getent passwd | awk -F: '$3>=1000 && $3<65534')
fi

if [[ "$PURGE" -eq 1 ]]; then
  rm -rf /etc/pi-health /var/log/pi-health /var/lib/pi-health
  echo "Purged /etc/pi-health, /var/log/pi-health, /var/lib/pi-health."
else
  echo "Kept /etc/pi-health (config), /var/log/pi-health (logs), /var/lib/pi-health (state)."
  echo "Re-run with --purge to remove them."
fi

echo "Uninstalled."
