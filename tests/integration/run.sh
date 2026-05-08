#!/bin/bash
# Integration test:
# 1) Build a debian container with cron + coreutils.
# 2) Mount the repo, run install.sh --non-interactive with CHECKS=disk,mountpoint,dmesg-io.
# 3) Exercise check-disk against a fixture mountpoint.
# 4) Exercise check-mountpoint against a real bind mount.
# 5) Exercise check-dmesg-io against a faked dmesg binary that prints a known I/O error.
# 6) Pi-specific checks are NOT installed here — verified via unit tests.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IMAGE_TAG="pi-health-checks-test:latest"

docker build -q -t "$IMAGE_TAG" "$REPO_ROOT/tests/integration/" >/dev/null

docker run --rm --privileged \
  -v "$REPO_ROOT:/repo:ro" \
  "$IMAGE_TAG" bash -euxc '
    cp -r /repo /work && cd /work

    # Fake dmesg: print a fresh I/O error line.
    cat > /usr/local/bin/dmesg <<MOCK
#!/bin/bash
echo "[2026-05-08T12:00:00Z] blk_update_request: I/O error, dev sda, sector 12345"
MOCK
    chmod +x /usr/local/bin/dmesg

    # Install with the three generic checks.
    CHECKS=disk,mountpoint,dmesg-io ./install.sh --non-interactive

    # Verify scripts and lib are in place.
    test -x /usr/local/bin/check-disk.sh
    test -x /usr/local/bin/check-mountpoint.sh
    test -x /usr/local/bin/check-dmesg-io.sh
    test -r /usr/local/lib/pi-health/pi-health.sh
    test -d /etc/pi-health

    # Patch env files: container has no /mnt/data; redirect to / and /mnt/integration.
    sed -i "s|^MOUNTPOINT=.*|MOUNTPOINT=/|" /etc/pi-health/check-disk.env
    sed -i "s|^MOUNTPOINT=.*|MOUNTPOINT=/mnt/integration|" /etc/pi-health/check-mountpoint.env

    # check-disk: pass on a mountpoint with low usage.
    /usr/local/bin/check-disk.sh

    # check-mountpoint: real bind mount.
    mkdir -p /mnt/integration
    mount --bind /tmp /mnt/integration
    /usr/local/bin/check-mountpoint.sh

    # check-mountpoint: should fail on a non-mounted path.
    sed -i "s|^MOUNTPOINT=.*|MOUNTPOINT=/var/lib|" /etc/pi-health/check-mountpoint.env
    if /usr/local/bin/check-mountpoint.sh; then
      echo "expected failure on /var/lib mountpoint check"; exit 1
    fi

    # check-dmesg-io: first run sees fresh error → exits 1.
    if /usr/local/bin/check-dmesg-io.sh; then
      echo "expected first dmesg-io run to FAIL"; exit 1
    fi
    # Second run with same dmesg output → exits 0 (state-file dedup).
    /usr/local/bin/check-dmesg-io.sh

    # Verify install.sh wrote cron entries (root for nothing here, user crontab tested below).
    crontab -l 2>/dev/null | grep -E "check-disk|check-mountpoint|check-dmesg-io" || \
      { echo "no cron entries for installed checks"; exit 1; }

    # uninstall.sh --purge removes everything.
    ./uninstall.sh --purge
    test ! -x /usr/local/bin/check-disk.sh
    test ! -d /etc/pi-health

    echo "INTEGRATION TEST PASSED"
  '
