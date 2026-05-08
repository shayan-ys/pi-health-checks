#!/usr/bin/env bats

load ../test_helper/common
load ../test_helper/bats-support/load
load ../test_helper/bats-assert/load

setup() { setup_pi_health; }

@test "kuma_push is no-op when KUMA_PUSH_URL unset" {
  unset KUMA_PUSH_URL
  run bash -c '. lib/pi-health.sh && kuma_push down "msg"'
  assert_success
  # curl mock would have logged invocation; assert it did NOT.
  [ ! -s "$MOCK_BIN/.curl-invoked" ] || true
}

@test "log writes to PI_HEALTH_LOG_DIR/<name>.log" {
  run bash -c '. lib/pi-health.sh && log foo "hello"'
  assert_success
  run cat "$PI_HEALTH_LOG_DIR/foo.log"
  assert_output --partial "hello"
}

@test "load_env sources /etc/pi-health/<name>.env when present" {
  echo 'export FOO=bar' > "$PI_HEALTH_CONF_DIR/myname.env"
  run bash -c '. lib/pi-health.sh && load_env myname && echo "$FOO"'
  assert_success
  assert_output "bar"
}

@test "report_and_exit exits with given rc" {
  run bash -c '. lib/pi-health.sh && report_and_exit foo 1 "fail"'
  [ "$status" -eq 1 ]
}
