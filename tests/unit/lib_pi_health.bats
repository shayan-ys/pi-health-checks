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

@test "kuma_push includes ping= when third arg given" {
  KUMA_PUSH_URL="http://kuma.test/push/abc"
  # Capture curl args by replacing curl with a recording mock
  cat > "$MOCK_BIN/curl" <<'EOF'
#!/bin/bash
echo "$@" > "$MOCK_BIN/.curl.args"
exit 0
EOF
  chmod +x "$MOCK_BIN/curl"
  . "$BATS_TEST_DIRNAME/../../lib/pi-health.sh"
  kuma_push up "OK temp=58" 58
  grep -q "ping=58" "$MOCK_BIN/.curl.args"
}

@test "kuma_push omits ping= when only two args" {
  KUMA_PUSH_URL="http://kuma.test/push/abc"
  cat > "$MOCK_BIN/curl" <<'EOF'
#!/bin/bash
echo "$@" > "$MOCK_BIN/.curl.args"
exit 0
EOF
  chmod +x "$MOCK_BIN/curl"
  . "$BATS_TEST_DIRNAME/../../lib/pi-health.sh"
  kuma_push up "OK"
  ! grep -q "ping=" "$MOCK_BIN/.curl.args"
}

@test "read_cpu_temp_c reads from PI_HEALTH_TEMP_FILE override" {
  echo "67234" > "$BATS_TEST_TMPDIR/fake_temp"
  PI_HEALTH_TEMP_FILE="$BATS_TEST_TMPDIR/fake_temp" \
    bash -c '. lib/pi-health.sh; read_cpu_temp_c' > "$BATS_TEST_TMPDIR/out"
  [ "$(cat "$BATS_TEST_TMPDIR/out")" = "67" ]
}

@test "read_cpu_temp_c returns empty when source file missing" {
  PI_HEALTH_TEMP_FILE="$BATS_TEST_TMPDIR/nonexistent" \
    bash -c '. lib/pi-health.sh; read_cpu_temp_c' > "$BATS_TEST_TMPDIR/out"
  [ -z "$(cat "$BATS_TEST_TMPDIR/out")" ]
}

@test "read_argon_duty_pct returns integer from --decode output (real format)" {
  mock_set argonone-cli ">> DECODEING MEMORY <<
Fan Status ON Speed 55%
System Temperature 62°
Fan Mode [ AUTO ]" 0
  . lib/pi-health.sh
  result=$(read_argon_duty_pct)
  [ "$result" = "55" ]
}

@test "read_argon_duty_pct returns 0 when fan is OFF" {
  mock_set argonone-cli ">> DECODEING MEMORY <<
Fan Status OFF Speed 0%
System Temperature 43°" 0
  . lib/pi-health.sh
  result=$(read_argon_duty_pct)
  [ "$result" = "0" ]
}

@test "read_argon_duty_pct returns empty when argonone-cli not present" {
  rm -f "$MOCK_BIN/argonone-cli"
  . lib/pi-health.sh
  result=$(read_argon_duty_pct)
  [ -z "$result" ]
}

@test "gatus_push is a no-op without GATUS_URL and GATUS_TOKEN" {
  unset GATUS_URL GATUS_TOKEN
  cat > "$MOCK_BIN/curl" <<'M'
#!/bin/bash
echo "$@" > "$MOCK_BIN/.curl.args"
M
  chmod +x "$MOCK_BIN/curl"
  . "$BATS_TEST_DIRNAME/../../lib/pi-health.sh"
  gatus_push down "x"
  [ ! -e "$MOCK_BIN/.curl.args" ]
}

@test "report_and_exit pushes failure to the Gatus key for the check" {
  echo 'GATUS_URL=http://gatus.test:8085/' > "$PI_HEALTH_CONF_DIR/common.env"
  echo 'GATUS_TOKEN=tok' >> "$PI_HEALTH_CONF_DIR/common.env"
  cat > "$MOCK_BIN/curl" <<'M'
#!/bin/bash
printf '%s\n' "$@" > "$MOCK_BIN/.curl.args"
M
  chmod +x "$MOCK_BIN/curl"
  run bash -c '. lib/pi-health.sh && load_env check-disk && report_and_exit check-disk 1 "disk full"'
  [ "$status" -eq 1 ]
  grep -qx "http://gatus.test:8085/api/v1/endpoints/host_check-disk/external" "$MOCK_BIN/.curl.args"
  grep -qx "success=false" "$MOCK_BIN/.curl.args"
  grep -qx "error=disk full" "$MOCK_BIN/.curl.args"
  grep -qx "Authorization: Bearer tok" "$MOCK_BIN/.curl.args"
}

@test "GATUS_KEY overrides the default key" {
  printf 'GATUS_URL=http://g\nGATUS_TOKEN=t\nGATUS_KEY=backup_opengym\n' > "$PI_HEALTH_CONF_DIR/common.env"
  cat > "$MOCK_BIN/curl" <<'M'
#!/bin/bash
printf '%s\n' "$@" > "$MOCK_BIN/.curl.args"
M
  chmod +x "$MOCK_BIN/curl"
  run bash -c '. lib/pi-health.sh && load_env x && report_and_exit x 0 ok'
  grep -qx "http://g/api/v1/endpoints/backup_opengym/external" "$MOCK_BIN/.curl.args"
  grep -qx "success=true" "$MOCK_BIN/.curl.args"
}
