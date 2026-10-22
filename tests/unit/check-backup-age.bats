#!/usr/bin/env bats

load ../test_helper/common
load ../test_helper/bats-support/load
load ../test_helper/bats-assert/load

setup() { setup_pi_health; mkdir -p "$BATS_TEST_TMPDIR/bk"; }

@test "passes when newest backup is fresh" {
  touch "$BATS_TEST_TMPDIR/bk/app-1.tar.gz"
  BACKUP_GLOB="$BATS_TEST_TMPDIR/bk/app-*.tar.gz" run run_check check-backup-age.sh
  assert_success
  assert_output --partial "app-1.tar.gz"
}

@test "fails when newest backup is older than MAX_AGE_H" {
  touch -t 202001010000 "$BATS_TEST_TMPDIR/bk/app-1.tar.gz"
  BACKUP_GLOB="$BATS_TEST_TMPDIR/bk/app-*.tar.gz" MAX_AGE_H=36 run run_check check-backup-age.sh
  assert_failure
  assert_output --partial "max 36h"
}

@test "uses the newest of several files" {
  touch -t 202001010000 "$BATS_TEST_TMPDIR/bk/app-old.tar.gz"
  touch "$BATS_TEST_TMPDIR/bk/app-new.tar.gz"
  BACKUP_GLOB="$BATS_TEST_TMPDIR/bk/app-*.tar.gz" run run_check check-backup-age.sh
  assert_success
  assert_output --partial "app-new"
}

@test "fails when nothing matches" {
  BACKUP_GLOB="$BATS_TEST_TMPDIR/bk/none-*.tar.gz" run run_check check-backup-age.sh
  assert_failure
  assert_output --partial "no backup matches"
}
