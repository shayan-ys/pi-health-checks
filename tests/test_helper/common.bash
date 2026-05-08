# common.bash — sourced from every .bats file via `load`.
# Sets up a temp PI_HEALTH dir, a mock-bin PATH, and helpers to pre-program mocks.

setup_pi_health() {
  export PI_HEALTH_LOG_DIR="$BATS_TEST_TMPDIR/log"
  export PI_HEALTH_STATE_DIR="$BATS_TEST_TMPDIR/state"
  export PI_HEALTH_CONF_DIR="$BATS_TEST_TMPDIR/conf"
  mkdir -p "$PI_HEALTH_LOG_DIR" "$PI_HEALTH_STATE_DIR" "$PI_HEALTH_CONF_DIR"

  export MOCK_BIN="$BATS_TEST_TMPDIR/mockbin"
  mkdir -p "$MOCK_BIN"
  # Copy the static mock fakes into the per-test mockbin.
  cp "$BATS_TEST_DIRNAME/../test_helper/mocks/"* "$MOCK_BIN/"
  chmod +x "$MOCK_BIN/"*
  export PATH="$MOCK_BIN:$PATH"

  # Each mock reads its programmed behavior from $MOCK_BIN/.<name>.{out,rc}
  # Set defaults: rc=0, no output.
  for tool in df docker nordvpn dmesg vcgencmd i2cdetect curl mountpoint; do
    : > "$MOCK_BIN/.${tool}.out"
    echo 0 > "$MOCK_BIN/.${tool}.rc"
  done
  # systemctl always succeeds by default; treat as a real binary if present.
  command -v systemctl >/dev/null || {
    cat > "$MOCK_BIN/systemctl" <<'M'
#!/bin/bash
[[ "$1" == "is-active" ]] && exit 0 ; exit 0
M
    chmod +x "$MOCK_BIN/systemctl"
  }
}

# Program a mock to print $2 and exit $3 on next invocation.
mock_set() {
  local name="$1" out="$2" rc="${3:-0}"
  printf '%s' "$out" > "$MOCK_BIN/.${name}.out"
  echo "$rc" > "$MOCK_BIN/.${name}.rc"
}

run_check() {
  local script="$1"; shift
  bash "$BATS_TEST_DIRNAME/../../checks/${script}" "$@"
}
