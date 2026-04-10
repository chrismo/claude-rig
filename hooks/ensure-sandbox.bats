#!/usr/bin/env bats

# Test suite for ensure-sandbox.sh SessionStart hook.
#
# The hook writes sandbox config to .claude/settings.local.json in the
# current directory. Tests use a temp directory to avoid touching real projects.

HOOK="$BATS_TEST_DIRNAME/ensure-sandbox.sh"

setup() {
  TEST_DIR="$(mktemp -d "$TMPDIR/ensure-sandbox-test.XXXXXX")"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# ── Core sandbox settings ─────────────────────────────────────────────────────

@test "enables sandbox" {
  cd "$TEST_DIR"
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  local enabled
  enabled=$(super -f line -c 'this.sandbox.enabled' .claude/settings.local.json)
  [ "$enabled" = "true" ]
}

@test "enables autoAllowBashIfSandboxed" {
  cd "$TEST_DIR"
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  local autoAllow
  autoAllow=$(super -f line -c 'this.sandbox.autoAllowBashIfSandboxed' .claude/settings.local.json)
  [ "$autoAllow" = "true" ]
}

# ── Filesystem allowWrite ─────────────────────────────────────────────────────

@test "sets filesystem.allowWrite including .claude/tmp" {
  cd "$TEST_DIR"
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  local paths
  paths=$(super -f line -c 'join(this.sandbox.filesystem.allowWrite, ",")' .claude/settings.local.json)
  [[ "$paths" == *".claude/tmp"* ]]
}

@test "sets filesystem.allowWrite including tmp" {
  cd "$TEST_DIR"
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  local paths
  paths=$(super -f line -c 'join(this.sandbox.filesystem.allowWrite, ",")' .claude/settings.local.json)
  [[ "$paths" == *"tmp"* ]]
}

# ── Preserves existing settings ───────────────────────────────────────────────

@test "preserves existing non-sandbox keys" {
  cd "$TEST_DIR"
  mkdir -p .claude
  echo '{"customKey": "preserved"}' > .claude/settings.local.json
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  local val
  val=$(super -f line -c 'this.customKey' .claude/settings.local.json)
  [ "$val" = "preserved" ]
}

@test "idempotent: running twice produces same result" {
  cd "$TEST_DIR"
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  local first_run
  first_run=$(cat .claude/settings.local.json)
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  local second_run
  second_run=$(cat .claude/settings.local.json)
  [ "$first_run" = "$second_run" ]
}
