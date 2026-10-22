#!/bin/bash
# install.sh — pick which checks to enable, install scripts + lib + env files,
# write per-script push settings to /etc/pi-health/<name>.env (and shared Gatus
# settings to /etc/pi-health/common.env), append cron
# entries to the invoking user's crontab (or root for argonone/undervoltage).
#
# Idempotent: re-running upgrades scripts in place and adds missing cron lines.
#
# Usage:
#   sudo ./install.sh                         # interactive
#   sudo ./install.sh --non-interactive       # uses CHECKS env var
#   CHECKS=disk,mountpoint,docker-health,nordvpn,dmesg-io sudo -E ./install.sh --non-interactive
#   GATUS_URL=http://127.0.0.1:8085 GATUS_TOKEN=... CHECKS=... sudo -E ./install.sh --non-interactive

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "install.sh: must run as root (use sudo)" >&2
  exit 1
fi

INTERACTIVE=1
[[ "${1:-}" == "--non-interactive" ]] && INTERACTIVE=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ALL_CHECKS=(disk mountpoint docker-health nordvpn meshnet-routing dmesg-io argononed undervoltage fan-thermal thermal-emergency pi-heartbeat backup-age)
PI_ONLY=(argononed undervoltage)

# Pick checks
if [[ "$INTERACTIVE" -eq 1 ]]; then
  echo "Available checks:"
  for c in "${ALL_CHECKS[@]}"; do
    pi_marker=""
    for p in "${PI_ONLY[@]}"; do [[ "$c" == "$p" ]] && pi_marker=" (Pi only)"; done
    echo "  - $c$pi_marker"
  done
  echo
  read -rp "Comma-separated list to enable (default: all): " CHECKS_INPUT
  if [[ -z "$CHECKS_INPUT" ]]; then
    CHECKS=("${ALL_CHECKS[@]}")
  else
    IFS=',' read -ra CHECKS <<< "$CHECKS_INPUT"
  fi
else
  : "${CHECKS:?CHECKS env var required in --non-interactive mode}"
  # shellcheck disable=SC2128  # CHECKS is the scalar env var here, not the array above
  IFS=',' read -ra CHECKS <<< "$CHECKS"
fi

# Validate
for c in "${CHECKS[@]}"; do
  c="$(echo "$c" | tr -d '[:space:]')"
  found=0
  for valid in "${ALL_CHECKS[@]}"; do [[ "$c" == "$valid" ]] && found=1; done
  [[ "$found" -eq 1 ]] || { echo "Unknown check: $c" >&2; exit 1; }
done

# Determine the invoking user (sudo target).
INVOKING_USER="${SUDO_USER:-root}"

# Create dirs
install -d -m 0755 /usr/local/lib/pi-health
install -d -m 0755 /etc/pi-health
install -d -m 0755 /var/log/pi-health
install -d -m 0755 /var/lib/pi-health
chown -R "$INVOKING_USER":"$INVOKING_USER" /var/log/pi-health /var/lib/pi-health

# Install lib
install -m 0644 "$SCRIPT_DIR/lib/pi-health.sh" /usr/local/lib/pi-health/pi-health.sh

# Shared Gatus push settings. Written only when both values are given; the
# token is readable by root and the invoking user only.
if [[ -n "${GATUS_URL:-}" && -n "${GATUS_TOKEN:-}" ]]; then
  umask_old=$(umask); umask 077
  printf 'GATUS_URL=%s\nGATUS_TOKEN=%s\n' "$GATUS_URL" "$GATUS_TOKEN" > /etc/pi-health/common.env
  umask "$umask_old"
  chown root:"$INVOKING_USER" /etc/pi-health/common.env
  chmod 0640 /etc/pi-health/common.env
fi

# Install each selected check
for c in "${CHECKS[@]}"; do
  c="$(echo "$c" | tr -d '[:space:]')"
  install -m 0755 "$SCRIPT_DIR/checks/check-${c}.sh" "/usr/local/bin/check-${c}.sh"

  # Seed env file if absent (don't clobber existing).
  if [[ ! -f "/etc/pi-health/check-${c}.env" ]]; then
    install -m 0644 "$SCRIPT_DIR/env/check-${c}.env.example" "/etc/pi-health/check-${c}.env"
    if [[ "$INTERACTIVE" -eq 1 ]]; then
      read -rp "Kuma push URL for check-${c} (blank to skip pushes): " url
      if [[ -n "$url" ]]; then
        sed -i.bak -E "s#^KUMA_PUSH_URL=.*#KUMA_PUSH_URL=${url//#/\\#}#" "/etc/pi-health/check-${c}.env"
        rm -f "/etc/pi-health/check-${c}.env.bak"
      else
        sed -i.bak -E 's#^KUMA_PUSH_URL=.*#KUMA_PUSH_URL=#' "/etc/pi-health/check-${c}.env"
        rm -f "/etc/pi-health/check-${c}.env.bak"
      fi
    fi
  fi
done

# Determine crontab owner per check (root for Pi-specific, $INVOKING_USER for the rest).
add_cron_line() {
  local user="$1" line="$2"
  local tmp
  tmp="$(mktemp)"
  crontab -u "$user" -l 2>/dev/null > "$tmp" || true
  grep -vF "$line" "$tmp" > "${tmp}.new" || true
  echo "$line" >> "${tmp}.new"
  crontab -u "$user" - < "${tmp}.new"
  rm -f "$tmp" "${tmp}.new"
}

for c in "${CHECKS[@]}"; do
  c="$(echo "$c" | tr -d '[:space:]')"
  needs_root=0
  for p in "${PI_ONLY[@]}"; do [[ "$c" == "$p" ]] && needs_root=1; done
  user="$INVOKING_USER"; [[ "$needs_root" -eq 1 ]] && user=root
  line="*/5 * * * * /usr/local/bin/check-${c}.sh"
  add_cron_line "$user" "$line"
done

echo
echo "Installed checks: ${CHECKS[*]}"
echo "Cron entries added to user(s) and root as appropriate."
echo "Edit /etc/pi-health/check-<name>.env to tune thresholds; push targets live in common.env (Gatus) or KUMA_PUSH_URL."
echo "Logs: /var/log/pi-health/<name>.log"
