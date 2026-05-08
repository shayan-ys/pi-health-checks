# pi-health-checks

> Seven small bash health-check scripts (disk, mountpoint, docker, nordvpn,
> dmesg-io, plus optional argonone-fan and undervoltage on Raspberry Pi)
> driven by cron, pushing heartbeats to [Uptime Kuma](https://github.com/louislam/uptime-kuma)
> push monitors. No daemon, no agent, no Python — just bash + cron + curl.

## What this is

Each script is a single ~30-line bash file that:
1. Reads its config from `/etc/pi-health/<name>.env`.
2. Runs one specific check (filesystem usage, mount liveness, docker daemon
   health, NordVPN Meshnet status + peer count, fresh dmesg I/O errors,
   argonone fan controller health, Pi undervoltage).
3. Logs to `/var/log/pi-health/<name>.log`.
4. Optionally `curl`s a `KUMA_PUSH_URL` heartbeat (`?status=up&msg=...` or
   `?status=down&msg=...`). If the URL is unset, the check is exit-code-only.

Cron runs all of them every 5 minutes. Kuma's
[push monitor type](https://github.com/louislam/uptime-kuma/wiki/Monitor-Types)
flips DOWN if a heartbeat doesn't arrive within the configured grace period.

## Why I wrote it

The existing pattern is repeated across every Pi/homelab post on r/selfhosted:
"I wrote some bash + cron + Kuma push monitors." Everyone re-derives the same
seven checks. This is just those seven checks, packaged with tests, install/
uninstall, and a single README.

## Install

Requires `bash`, `cron`, `coreutils`, `curl`, and `util-linux` (for `mountpoint`).
Pi-specific checks additionally require `vcgencmd` (Pi firmware) and `i2c-tools`.

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
