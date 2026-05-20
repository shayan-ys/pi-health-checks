#!/usr/bin/env bats

load ../test_helper/common
load ../test_helper/bats-support/load
load ../test_helper/bats-assert/load

setup() { setup_pi_health; }

@test "passes when systemctl reports active" {
  cat > "$MOCK_BIN/systemctl" <<'EOF'
#!/bin/bash
[[ "$1" == "is-active" && "$2" == "argononed" ]] && { echo active; exit 0; }
exit 3
EOF
  chmod +x "$MOCK_BIN/systemctl"
  run run_check check-argononed.sh
  assert_success
  assert_output --partial "OK"
}

@test "fails when systemctl reports inactive" {
  cat > "$MOCK_BIN/systemctl" <<'EOF'
#!/bin/bash
[[ "$1" == "is-active" ]] && { echo inactive; exit 3; }
exit 0
EOF
  chmod +x "$MOCK_BIN/systemctl"
  run run_check check-argononed.sh
  assert_failure
  assert_output --partial "argononed not active"
}

@test "fails when systemctl reports failed" {
  cat > "$MOCK_BIN/systemctl" <<'EOF'
#!/bin/bash
[[ "$1" == "is-active" ]] && { echo failed; exit 3; }
exit 0
EOF
  chmod +x "$MOCK_BIN/systemctl"
  run run_check check-argononed.sh
  assert_failure
}

@test "does NOT call i2cdetect (no bus collision)" {
  cat > "$MOCK_BIN/systemctl" <<'EOF'
#!/bin/bash
echo active; exit 0
EOF
  chmod +x "$MOCK_BIN/systemctl"
  cat > "$MOCK_BIN/i2cdetect" <<'EOF'
#!/bin/bash
touch "$MOCK_BIN/.i2cdetect.called"; exit 0
EOF
  chmod +x "$MOCK_BIN/i2cdetect"
  run run_check check-argononed.sh
  [ ! -f "$MOCK_BIN/.i2cdetect.called" ]
}
