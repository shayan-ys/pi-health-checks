#!/usr/bin/env bats

load ../test_helper/common
load ../test_helper/bats-support/load
load ../test_helper/bats-assert/load

setup() { setup_pi_health; }

@test "fails when docker info errors" {
  mock_set docker "" 1
  run run_check check-docker-health.sh
  assert_failure
  assert_output --partial "daemon unreachable"
}

@test "passes when no exited/unhealthy containers" {
  # docker info: rc 0; docker ps -a: rc 0, empty.
  mock_set docker "" 0
  run run_check check-docker-health.sh
  assert_success
}

@test "fails when an unhealthy container is present" {
  # The single mock returns the same output for every docker invocation.
  # Acceptable here because the script tolerates non-empty output for
  # `docker info` (it only checks rc) and for `docker ps -a` it parses lines.
  mock_set docker $'web\tUp 2 hours (unhealthy)' 0
  run run_check check-docker-health.sh
  assert_failure
  assert_output --partial "unhealthy"
}

@test "IGNORE_NAMES filters out matching containers" {
  mock_set docker $'web\tExited (137) 1 minute ago' 0
  IGNORE_NAMES='web' run run_check check-docker-health.sh
  assert_success
}
