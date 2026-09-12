#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

# Test suite for bin/work-context.
#
# Focus: collect_worktree_data — the local-git walk behind `work-context
# worktrees`. It must emit one self-contained JSON record per repo AND per
# linked worktree. These tests pin that contract so the worktree-path
# derivation (bash expansion of .git/worktrees/<n>/gitdir) and any
# parallelization of the walk don't silently drop or corrupt records.

WC="$BATS_TEST_DIRNAME/work-context"

setup() {
  # Point at a non-existent config so sourcing skips real-repo config loading
  # (and the super calls that go with it). We set repos_to_check ourselves.
  export WORK_CONTEXT_CONFIG="$BATS_TEST_TMPDIR/no-such-config.sup"

  # The script's bottom guard skips main() when sourced.
  source "$WC"

  # Build a throwaway repo with one commit and one linked worktree.
  REPO="$BATS_TEST_TMPDIR/main"
  git init -q -b main "$REPO"
  git -C "$REPO" config user.email t@example.com
  git -C "$REPO" config user.name Tester
  printf 'hello\n' > "$REPO/file.txt"
  git -C "$REPO" add file.txt
  git -C "$REPO" commit -qm "init commit"
  git -C "$REPO" worktree add -q "$BATS_TEST_TMPDIR/wt-feature" -b feature

  repos_to_check=("$REPO")
}

# ── diag: Claude-internals canaries ─────────────────────────────────────────

# fake_claude_state USER_RECORD_JSON
#   Points diag's canaries at a throwaway projects dir and history.jsonl.
#   (HOME itself can't be redirected here — the asdf shim that provides
#   `super` reads $HOME/.asdf and fails to exec without it.)
fake_claude_state() {
  local user_record="$1"
  export CLAUDE_PROJECTS_DIR="$BATS_TEST_TMPDIR/fake/projects"
  export CLAUDE_HISTORY_FILE="$BATS_TEST_TMPDIR/fake/history.jsonl"
  mkdir -p "$CLAUDE_PROJECTS_DIR/-tmp-widget"
  printf '%s\n' "$user_record" > "$CLAUDE_PROJECTS_DIR/-tmp-widget/s1.jsonl"
  printf '%s\n' '{"display":"hi","sessionId":"s1","timestamp":1}' > "$CLAUDE_HISTORY_FILE"
}

@test "diag passes the transcript field check when every expected field is present" {
  fake_claude_state '{"type":"user","sessionId":"s1","timestamp":"2026-09-12T00:00:00Z","message":{"content":"hi"},"gitBranch":"main"}'
  run diag
  [[ "$output" != *"missing expected fields"* ]] || false
  [[ "$output" != *"missing sessionId field"* ]]
}

@test "diag warns when the transcript's user record is missing a field" {
  fake_claude_state '{"type":"user","sessionId":"s1","timestamp":"2026-09-12T00:00:00Z","message":{"content":"hi"}}'
  run diag
  [[ "$output" == *"missing expected fields"* ]]
}

# ── collect_worktree_data ───────────────────────────────────────────────────

@test "emits a record for the main repo" {
  run collect_worktree_data
  [ "$status" -eq 0 ]
  [[ "$output" == *'"name":"main"'* ]]
}

@test "emits a record for the linked worktree (gitdir path derivation)" {
  run collect_worktree_data
  [ "$status" -eq 0 ]
  # If the gitdir->worktree path strip is wrong, the dir won't exist and the
  # worktree record is dropped. This pins that derivation.
  [[ "$output" == *'"name":"wt-feature"'* ]] || false
  [[ "$output" == *'"branch":"feature"'* ]]
}

@test "emits exactly one record per repo + worktree (no dupes, no drops)" {
  run collect_worktree_data
  [ "$status" -eq 0 ]
  # main + wt-feature = 2 lines.
  [ "${#lines[@]}" -eq 2 ]
}

@test "each record is a single self-contained JSON object" {
  run collect_worktree_data
  [ "$status" -eq 0 ]
  for line in "${lines[@]}"; do
    [[ "$line" == '{'*'}' ]] || false
    [[ "$line" == *'"branch":'* ]] || false
    [[ "$line" == *'"commit_ts":'* ]] || false
  done
}

@test "reports a clean worktree as not dirty" {
  run collect_worktree_data
  [ "$status" -eq 0 ]
  [[ "$output" == *'"dirty":false'* ]] || false
  [[ "$output" != *'"dirty":true'* ]]
}

@test "reports an untracked file as dirty" {
  printf 'junk\n' > "$REPO/untracked.txt"
  run collect_worktree_data
  [ "$status" -eq 0 ]
  [[ "$output" == *'"dirty":true'* ]]
}
