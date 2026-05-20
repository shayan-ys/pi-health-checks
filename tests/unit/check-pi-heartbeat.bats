#!/usr/bin/env bats

load ../test_helper/common
load ../test_helper/bats-support/load
load ../test_helper/bats-assert/load

setup() {
  setup_pi_health
  export PI_HEALTH_TEMP_FILE="$BATS_TEST_TMPDIR/temp"
}

@test "always exits 0 with temp present" {
  echo "55000" > "$PI_HEALTH_TEMP_FILE"
  run run_check check-pi-heartbeat.sh
  assert_success
  assert_output --partial "55"
}

@test "exits 0 even without temp source" {
  rm -f "$PI_HEALTH_TEMP_FILE"
  run run_check check-pi-heartbeat.sh
  assert_success
}

@test "calls curl with ping= when KUMA_PUSH_URL is set and temp is available" {
  echo "62000" > "$PI_HEALTH_TEMP_FILE"
  cat > "$MOCK_BIN/curl" <<'EOF'
#!/bin/bash
echo "$@" > "$MOCK_BIN/.curl.args"
exit 0
EOF
  chmod +x "$MOCK_BIN/curl"
  KUMA_PUSH_URL="http://kuma.test/push/heartbeat" \
    run run_check check-pi-heartbeat.sh
  assert_success
  grep -q "ping=62" "$MOCK_BIN/.curl.args"
}
