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

# ── Config loading ──────────────────────────────────────────────────────────

# The config block runs at source time, so these tests re-source the script
# with WORK_CONTEXT_CONFIG pointed at a fixture.
write_config() {
  local body="$1"
  local cfg="$BATS_TEST_TMPDIR/work-context.sup"
  printf '%s\n' "$body" > "$cfg"
  printf '%s' "$cfg"
}

@test "config: github_orgs is read when present" {
  local cfg
  cfg=$(write_config '{repos:["~/dev/widget"],github_orgs:["acme","initech"]}')
  WORK_CONTEXT_CONFIG="$cfg" source "$WC"
  [ "${#github_orgs[@]}" -eq 2 ]
  [[ "${github_orgs[0]}" == "acme" ]] || false
  [[ "${github_orgs[1]}" == "initech" ]]
}

@test "config: a config with no github_orgs loads without complaint" {
  # github_orgs is optional. Naming it in the query errored on a config that
  # omits it — invisibly, because the read swallowed stderr. The read no
  # longer swallows it, so this test can see the difference.
  local cfg err
  cfg=$(write_config '{repos:["~/dev/widget"]}')
  err="$BATS_TEST_TMPDIR/config.err"
  WORK_CONTEXT_CONFIG="$cfg" source "$WC" 2>"$err"
  [[ ! -s "$err" ]] || { cat "$err" >&2; false; }
  [ "${#github_orgs[@]}" -eq 0 ] || false
  [ "${#repos_to_check[@]}" -eq 1 ]
}

# ── open_prs rendering ──────────────────────────────────────────────────────

# stub_gh JSON
#   Puts a fake `gh` ahead of the real one on PATH: `auth status` succeeds and
#   `pr list` prints JSON, so open_prs can be rendered without the network.
stub_gh() {
  local json="$1"
  local bin="$BATS_TEST_TMPDIR/stubbin"
  mkdir -p "$bin"
  cat > "$bin/gh" <<-STUB
	#!/usr/bin/env bash
	[[ "\$1" == "auth" ]] && exit 0
	cat <<'JSON'
	$json
	JSON
	STUB
  chmod +x "$bin/gh"
  PATH="$bin:$PATH"
  export PATH
}

@test "open_prs: a PR with no reviewDecision renders as PENDING" {
  # gh omits reviewDecision entirely on a PR nobody has reviewed, so naming it
  # in the query is the same trap as the transcript flags — and here it would
  # take out the whole PR table, not one column.
  stub_gh '[{"number":7,"title":"widen the pipe","headRefName":"pipe","url":"u","headRepository":{"name":"widget"},"createdAt":"2026-09-01T00:00:00Z","updatedAt":"2026-09-01T00:00:00Z","isDraft":false}]'
  github_orgs=(acme)
  run open_prs
  [ "$status" -eq 0 ]
  [[ "$output" == *"widen the pipe"* ]] || false
  [[ "$output" == *"PENDING"* ]]
}

@test "open_prs: a reviewed PR renders its decision" {
  stub_gh '[{"number":8,"title":"narrow the pipe","headRefName":"pipe2","url":"u","reviewDecision":"APPROVED","headRepository":{"name":"widget"},"createdAt":"2026-09-01T00:00:00Z","updatedAt":"2026-09-02T00:00:00Z","isDraft":false}]'
  github_orgs=(acme)
  run open_prs
  [ "$status" -eq 0 ]
  [[ "$output" == *"APPROVED"* ]]
}

# ── search ──────────────────────────────────────────────────────────────────

# write_history LINE...
#   A fake ~/.claude/history.jsonl. `timestamp` is epoch ms, the shape the
#   search query's arithmetic expects.
write_history() {
  export CLAUDE_HISTORY_FILE="$BATS_TEST_TMPDIR/history.jsonl"
  : > "$CLAUDE_HISTORY_FILE"
  local line
  for line in "$@"; do printf '%s\n' "$line" >> "$CLAUDE_HISTORY_FILE"; done
}

@test "search finds a matching prompt" {
  write_history "{\"display\":\"fix the fivetran connector\",\"project\":\"/Users/t/dev/widget\",\"sessionId\":\"s1\",\"timestamp\":$(( $(date +%s) * 1000 ))}"
  run search fivetran 30
  [ "$status" -eq 0 ]
  [[ "$output" == *"fix the fivetran connector"* ]] || false
  [[ "$output" == *"widget"* ]]
}

@test "search: a term with an apostrophe searches instead of dying on a parse error" {
  write_history "{\"display\":\"it doesn't reconnect\",\"project\":\"/Users/t/dev/widget\",\"sessionId\":\"s1\",\"timestamp\":$(( $(date +%s) * 1000 ))}"
  run search "doesn't" 30
  [ "$status" -eq 0 ]
  [[ "$output" != *"parse error"* ]] || false
  [[ "$output" == *"reconnect"* ]]
}

@test "search: a non-numeric day window is rejected, not fed to the query" {
  write_history "{\"display\":\"anything\",\"project\":\"/Users/t/dev/widget\",\"sessionId\":\"s1\",\"timestamp\":$(( $(date +%s) * 1000 ))}"
  run search fivetran abc
  [ "$status" -eq 2 ]
  [[ "$output" == *"days must be a whole number"* ]]
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

@test "diag accepts a user record whose message.content is a block array" {
  # Tool-result turns carry an array, not a string. fields(this) returns leaf
  # paths, so ['message','content'] has to hold for both shapes or diag warns
  # on ordinary transcripts.
  fake_claude_state '{"type":"user","sessionId":"s1","timestamp":"2026-09-12T00:00:00Z","message":{"content":[{"type":"tool_result","content":"ok"}]},"gitBranch":"main"}'
  run diag
  [[ "$output" != *"missing expected fields"* ]]
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
