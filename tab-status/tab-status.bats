#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

# Test suite for tab-status compute_title / get_agent_name.
#
# compute_title renders the Ghostty tab title. The behaviour under test:
# on the default branch (main/master) the parenthetical becomes the Claude
# session name (agentName, set by /rename or `claude --name`) when one exists;
# otherwise it stays the git branch.
#
# Sandbox note (CLAUDE.md): run with sandbox disabled — the suite does git init.

TAB_STATUS="$BATS_TEST_DIRNAME/tab-status"

setup() {
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tab-status-test.XXXXXX")"
  # Hermetic status dir so we don't read/write the real ~/.claude/tab-status.
  export STATUS_DIR="$TEST_DIR/status"
  mkdir -p "$STATUS_DIR"
  # Source the script; the guard at the bottom skips main when sourced.
  source "$TAB_STATUS"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# Create a git repo at $TEST_DIR/repo on branch $1 and cd into it.
# Sets the unborn branch name before the first commit so any name works
# without rename conflicts.
init_repo() {
  local branch="$1"
  REPO="$TEST_DIR/repo"
  mkdir -p "$REPO"
  cd "$REPO"
  git init -q
  git symbolic-ref HEAD "refs/heads/$branch"
  git config user.email test@example.com
  git config user.name test
  git commit --allow-empty -q -m init
}

# Write a transcript fixture with the given agent names (in order) and point
# TAB_STATUS_TRANSCRIPT at it. The last name is the "current" one.
make_transcript() {
  TRANSCRIPT="$TEST_DIR/session.jsonl"
  : > "$TRANSCRIPT"
  local n
  for n in "$@"; do
    printf '{"type":"agent-name","agentName":"%s","sessionId":"abc"}\n' "$n" >> "$TRANSCRIPT"
  done
  export TAB_STATUS_TRANSCRIPT="$TRANSCRIPT"
}

# ── compute_title ───────────────────────────────────────────────────────────────

@test "default branch (main) shows the session name in parens" {
  init_repo main
  make_transcript find-difficult-words-script
  run compute_title </dev/null

  [ "$status" -eq 0 ]
  [[ "$output" == *"(find-difficult-words-script)"* ]]
  [[ "$output" != *"(main)"* ]]
}

@test "default branch (main) with no name shows the branch" {
  init_repo main
  run compute_title </dev/null

  [ "$status" -eq 0 ]
  [[ "$output" == *"(main)"* ]]
}

@test "last agent-name record wins (mid-session rename)" {
  init_repo main
  make_transcript first-name second-name third-name
  run compute_title </dev/null

  [ "$status" -eq 0 ]
  [[ "$output" == *"(third-name)"* ]]
  [[ "$output" != *"first-name"* ]]
}

@test "feature branch shows the branch and ignores the session name" {
  init_repo some-feature
  make_transcript find-difficult-words-script
  run compute_title </dev/null

  [ "$status" -eq 0 ]
  [[ "$output" == *"(some-feature)"* ]]
  [[ "$output" != *"find-difficult-words-script"* ]]
}

@test "master is treated as a default branch" {
  init_repo master
  make_transcript stateful-petting-sunbeam
  run compute_title </dev/null

  [ "$status" -eq 0 ]
  [[ "$output" == *"(stateful-petting-sunbeam)"* ]]
  [[ "$output" != *"(master)"* ]]
}

@test "outside a git repo shows the dir with no parens" {
  mkdir -p "$TEST_DIR/plain"
  cd "$TEST_DIR/plain"
  run compute_title </dev/null

  [ "$status" -eq 0 ]
  [[ "$output" == *"plain"* ]]
  [[ "$output" != *"("* ]]
}

@test "status emoji prefix is preserved (name case)" {
  init_repo main
  make_transcript find-difficult-words-script
  printf 'active\n' > "$STATUS_DIR/$(basename "$REPO")"
  run compute_title </dev/null

  [ "$status" -eq 0 ]
  [[ "$output" == *"🟢 "* ]]
  [[ "$output" == *"(find-difficult-words-script)"* ]]
}

@test "status emoji prefix is preserved (branch case)" {
  init_repo some-feature
  printf 'waiting\n' > "$STATUS_DIR/$(basename "$REPO")"
  run compute_title </dev/null

  [ "$status" -eq 0 ]
  [[ "$output" == *"🟡 "* ]]
  [[ "$output" == *"(some-feature)"* ]]
}

@test "transcript_path is read from the hook JSON on stdin" {
  init_repo main
  make_transcript find-difficult-words-script
  # Drop the env override so the name MUST come from stdin (the hook path).
  unset TAB_STATUS_TRANSCRIPT
  run compute_title <<< "{\"transcript_path\":\"$TRANSCRIPT\",\"hook_event_name\":\"Stop\"}"

  [ "$status" -eq 0 ]
  [[ "$output" == *"(find-difficult-words-script)"* ]]
}

@test "manual invocation with no transcript does not hang; falls back to branch" {
  init_repo main
  # Empty (non-tty) stdin must not block on cat; must fall back to the branch.
  run timeout 5 bash -c "STATUS_DIR='$STATUS_DIR' source '$TAB_STATUS'; compute_title" </dev/null

  [ "$status" -ne 124 ]   # 124 == timeout fired (hang)
  [[ "$output" == *"(main)"* ]]
}

@test "nonexistent transcript path falls back to the branch" {
  init_repo main
  export TAB_STATUS_TRANSCRIPT="$TEST_DIR/does-not-exist.jsonl"
  run compute_title </dev/null

  [ "$status" -eq 0 ]
  [[ "$output" == *"(main)"* ]]
}

@test "installed hook chain: title computation reads stdin --hook left unread (real pipe)" {
  # Faithfully replicates the installed hook command shape, with hook JSON on a
  # non-seekable pipe (process substitution): `--hook` ignores stdin, so the
  # following title command must still read transcript_path from it. Uses
  # --print-title (pure) so the test doesn't invoke the osascript delivery path.
  init_repo main
  make_transcript chained-name
  unset TAB_STATUS_TRANSCRIPT
  run bash -c \
    "STATUS_DIR='$STATUS_DIR' '$TAB_STATUS' --hook active >/dev/null; STATUS_DIR='$STATUS_DIR' '$TAB_STATUS' --print-title" \
    < <(printf '%s' "{\"transcript_path\":\"$TRANSCRIPT\"}")

  [ "$status" -eq 0 ]
  [[ "$output" == *"(chained-name)"* ]]
}
