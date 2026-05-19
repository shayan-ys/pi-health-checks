#!/usr/bin/env bats

load ../test_helper/common
load ../test_helper/bats-support/load
load ../test_helper/bats-assert/load

setup() { setup_pi_health; }

@test "skips with rc 0 when i2cdetect missing and not a Pi" {
  rm -f "$MOCK_BIN/i2cdetect"
  run run_check check-argononed.sh
  assert_success
}

@test "fails when on Pi hardware but i2cdetect not installed" {
  rm -f "$MOCK_BIN/i2cdetect"
  local model_file="$BATS_TEST_TMPDIR/pi-model"
  printf 'Raspberry Pi 4 Model B Rev 1.4\0' > "$model_file"
  export PI_MODEL_FILE="$model_file"
  run run_check check-argononed.sh
  assert_failure
  assert_output --partial "i2cdetect not installed"
}

@test "fails when systemctl reports argononed not active" {
  # Override the systemctl-mock-or-real with an explicit failing mock.
  cat > "$MOCK_BIN/systemctl" <<'S'
#!/bin/bash
exit 3
S
  chmod +x "$MOCK_BIN/systemctl"
  run run_check check-argononed.sh
  assert_failure
  assert_output --partial "not active"
}

@test "fails when I2C address absent from i2cdetect output" {
  cat > "$MOCK_BIN/systemctl" <<'S'
#!/bin/bash
exit 0
S
  chmod +x "$MOCK_BIN/systemctl"
  mock_set i2cdetect $'     0  1  2  3  4  5  6  7\n00:          --  --  --  --  --  --' 0
  run run_check check-argononed.sh
  assert_failure
  assert_output --partial "I2C 0x1a not present"
}

@test "passes when systemctl active + i2cdetect shows 1a" {
  cat > "$MOCK_BIN/systemctl" <<'S'
#!/bin/bash
exit 0
S
  chmod +x "$MOCK_BIN/systemctl"
  mock_set i2cdetect $'     0  1  2  3  4  5  6  7\n10: --  --  --  --  --  --  --  --  --  --  1a' 0
  run run_check check-argononed.sh
  assert_success
}
