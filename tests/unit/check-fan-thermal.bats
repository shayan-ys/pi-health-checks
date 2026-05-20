#!/usr/bin/env bats

load ../test_helper/common
load ../test_helper/bats-support/load
load ../test_helper/bats-assert/load

setup() {
  setup_pi_health
  # Default: argononed is active in these tests unless overridden
  cat > "$MOCK_BIN/systemctl" <<'EOF'
#!/bin/bash
[[ "$1" == "is-active" ]] && { echo active; exit 0; }
exit 0
EOF
  chmod +x "$MOCK_BIN/systemctl"
  # Provide a temp file we control
  export PI_HEALTH_TEMP_FILE="$BATS_TEST_TMPDIR/temp"
}

set_temp() { echo "${1}000" > "$PI_HEALTH_TEMP_FILE"; }

@test "passes when temp is low (50C) regardless of duty" {
  set_temp 50
  mock_set argonone-cli "Speed: 0%" 0
  run run_check check-fan-thermal.sh
  assert_success
  assert_output --partial "OK"
}

@test "fails when temp is 65C and duty is 0 (daemon not kicking fan)" {
  set_temp 65
  mock_set argonone-cli "Speed: 0%" 0
  run run_check check-fan-thermal.sh
  assert_failure
  assert_output --partial "duty=0"
}

@test "fails when temp is 70C and duty is 80% (fan on but Pi still hot)" {
  set_temp 70
  mock_set argonone-cli "Speed: 80%" 0
  run run_check check-fan-thermal.sh
  assert_failure
  assert_output --partial "duty=80"
}

@test "passes when temp is 64C (just below threshold) even with duty=0" {
  set_temp 64
  mock_set argonone-cli "Speed: 0%" 0
  run run_check check-fan-thermal.sh
  assert_success
}

@test "defers (rc 0) when argononed is not active" {
  set_temp 70
  cat > "$MOCK_BIN/systemctl" <<'EOF'
#!/bin/bash
[[ "$1" == "is-active" ]] && { echo inactive; exit 3; }
exit 0
EOF
  chmod +x "$MOCK_BIN/systemctl"
  mock_set argonone-cli "Speed: 80%" 0
  run run_check check-fan-thermal.sh
  assert_success
  assert_output --partial "deferring"
}

@test "degrades gracefully when argonone-cli is missing (temp-only)" {
  rm -f "$MOCK_BIN/argonone-cli"
  set_temp 70
  run run_check check-fan-thermal.sh
  assert_failure
  assert_output --partial "no daemon-cli"
}

@test "skips with rc 0 when no temp source available" {
  rm -f "$PI_HEALTH_TEMP_FILE"
  run run_check check-fan-thermal.sh
  assert_success
  assert_output --partial "skipped"
}
