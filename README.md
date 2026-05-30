# pi-health-checks

> Eleven small bash health-check scripts (disk, mountpoint, docker, nordvpn,
> meshnet-routing, dmesg-io, argonone-fan, undervoltage, fan-thermal,
> thermal-emergency, pi-heartbeat) driven by cron, pushing heartbeats to
> [Uptime Kuma](https://github.com/louislam/uptime-kuma) push monitors.
> No daemon, no agent, no Python — just bash + cron + curl.

## What this is

Each script is a single ~30-line bash file that:
1. Reads its config from `/etc/pi-health/<name>.env`.
2. Runs one specific check (filesystem usage, mount liveness, docker daemon
   health, NordVPN Meshnet status + peer count, Meshnet peer routing
   permissions, fresh dmesg I/O errors, argonone fan controller health via
   `systemctl is-active argononed`, Pi undervoltage, fan-vs-thermal mismatch,
   thermal-emergency, CPU heartbeat).
3. Logs to `/var/log/pi-health/<name>.log`.
4. Optionally `curl`s a `KUMA_PUSH_URL` heartbeat (`?status=up&msg=...` or
   `?status=down&msg=...`). If the URL is unset, the check is exit-code-only.

Cron runs all of them every 5 minutes. Kuma's
[push monitor type](https://github.com/louislam/uptime-kuma/wiki/Monitor-Types)
flips DOWN if a heartbeat doesn't arrive within the configured grace period.

## Checks

| Check | What it does | Pi-only? |
|---|---|---|
| `check-disk` | Filesystem usage against `WARN_PCT` / `CRIT_PCT` | No |
| `check-mountpoint` | Confirms a path is a live mount | No |
| `check-docker-health` | Docker daemon responsive + all containers healthy | No |
| `check-nordvpn` | NordVPN Meshnet active, peer count ≥ `MIN_PEERS` | No |
| `check-meshnet-routing` | Every Meshnet peer has routing permission so it can reach Docker-published services. With `ALLOW_ALL_PEERS_ROUTING=true`, self-heals by granting it (new peers default to routing-disabled). | No |
| `check-dmesg-io` | Fresh I/O errors in dmesg since last run (state-dedup) | No |
| `check-argononed` | Checks `systemctl is-active argononed` (bus-collision-free) | Yes |
| `check-undervoltage` | `vcgencmd get_throttled` undervoltage bit | Yes |
| `check-fan-thermal` | Alerts when daemon-reported fan state contradicts a hot CPU (temp ≥ `THRESHOLD_C` + duty=0 OR duty ≥ 20%). Recommended Kuma Retries=2. | Yes |
| `check-thermal-emergency` | Fan-agnostic `THRESHOLD_C` (default 75°C) safety net. Recommended Kuma Retries=1. | No |
| `check-pi-heartbeat` | Always-UP heartbeat with `ping=<cpu_temp>` for Kuma sparkline | No |

## Why I wrote it

The existing pattern is repeated across every Pi/homelab post on r/selfhosted:
"I wrote some bash + cron + Kuma push monitors." Everyone re-derives the same
seven checks. This is just those seven checks, packaged with tests, install/
uninstall, and a single README.

## Install

Requires `bash`, `cron`, `coreutils`, `curl`, and `util-linux` (for `mountpoint`).
Pi-specific checks additionally require `vcgencmd` (Pi firmware) and `argononed`
(the Argon fan daemon — `systemctl is-active argononed` is used instead of I²C
probing to avoid bus collisions).

```bash
git clone https://github.com/shayan-ys/pi-health-checks.git
cd pi-health-checks
sudo ./install.sh
```

`install.sh` is interactive: it asks which checks to enable and what Kuma
push URL (if any) to write into each `/etc/pi-health/<name>.env`. For
unattended installs:

```bash
CHECKS=disk,mountpoint,docker-health,nordvpn,dmesg-io \
  sudo -E ./install.sh --non-interactive
```

Pi-specific checks (`argononed`, `undervoltage`) install to root's crontab so
they can read `/dev/i2c-1` and call `vcgencmd`. Generic checks install to the
invoking user's crontab.

## Configure

Each check has its own `/etc/pi-health/<name>.env`. Examples:

```bash
# /etc/pi-health/check-disk.env
MOUNTPOINT=/mnt/data
WARN_PCT=70
CRIT_PCT=90
KUMA_PUSH_URL=https://kuma.example/api/push/abcd1234

# /etc/pi-health/check-nordvpn.env
MIN_PEERS=2
KUMA_PUSH_URL=https://kuma.example/api/push/efgh5678
```

Defaults are sane; only set what you want to override.

## Set up Kuma push monitors

For each check you want surfaced in Kuma:
1. Kuma → Add New Monitor → Type: `Push`. Set `Heartbeat Interval` to 60s
   and `Heartbeat Retry Interval` to 60s, `Resend Notification if DOWN x times`
   to 1.
2. Copy the generated push URL (e.g. `https://kuma.example/api/push/abcd1234`).
3. Paste into `/etc/pi-health/check-<name>.env` as `KUMA_PUSH_URL=...`.

You don't need to embed `?status=` or `?msg=` in the URL — the script appends
them. Kuma's push monitor accepts both `up` and `down` and surfaces the
attached `msg=` in the dashboard.

## Recommended Kuma Monitor Settings

| Check | Heartbeat Interval | Retries | Notes |
|---|---|---|---|
| check-argononed | 5 min | 2 | Fires after 3 consecutive failures (~15 min) |
| check-fan-thermal | 5 min | 2 | Same; gates on daemon being active |
| check-thermal-emergency | 5 min | 1 | Fires faster (~10 min); fan-agnostic |
| check-undervoltage | 5 min | 1 | Existing |
| check-pi-heartbeat | 5 min | 0 | Sparkline only; Kuma flips DOWN on heartbeat timeout |

## Verify

```bash
sudo -u "$USER" /usr/local/bin/check-disk.sh && echo OK
tail -n 5 /var/log/pi-health/check-disk.log
crontab -l | grep check-
```

Within 5 minutes you should see the corresponding monitor go green in Kuma.

## Uninstall

```bash
sudo ./uninstall.sh         # removes scripts + cron, keeps /etc/pi-health + logs
sudo ./uninstall.sh --purge # also drops /etc/pi-health, /var/log/pi-health, /var/lib/pi-health
```

## Tests

```bash
# Unit tests (mocks df/docker/nordvpn/dmesg/vcgencmd/i2cdetect/curl/mountpoint):
./tests/bats/bin/bats tests/unit/

# Integration test (privileged Docker, real install.sh):
./tests/integration/run.sh

# Lint:
uv tool run --from shellcheck-py shellcheck lib/pi-health.sh checks/*.sh install.sh uninstall.sh
```

CI runs all three on every push (see `.github/workflows/ci.yml`).

## Design notes

- **Bash + cron, no daemon.** A daemon would add an attack surface for one
  `curl` per minute. Cron is already running on every Linux host.
- **Per-check `.env` file.** One file per script, one Kuma URL per script.
  Tokens stay scoped: a leaked disk-check URL doesn't let anyone push false
  heartbeats to the docker monitor.
- **`KUMA_PUSH_URL` is optional.** Skip it and the check becomes a plain
  cron exit-code monitor — useful when you also have systemd/journald
  watching for cron failures.
- **State-file dedup for dmesg-io.** Without it, every cron run would re-fire
  on the same I/O error until dmesg's ringbuffer rolled over.

## License

MIT — see [LICENSE](LICENSE).
