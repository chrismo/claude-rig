#!/usr/bin/env bats
# work-context.bats - Tests for bin/work-context
#
# Run with: bats test/work-context.bats

load '/opt/homebrew/lib/bats-support/load.bash'
load '/opt/homebrew/lib/bats-assert/load.bash'

SCRIPT="${BATS_TEST_DIRNAME}/../bin/work-context"

setup() {
  command -v super &>/dev/null || skip "super CLI not installed"

  TEST_HOME="$(mktemp -d)"
  mkdir -p "$TEST_HOME/.claude/projects/test-project"
  mkdir -p "$TEST_HOME/.config"

  # Create minimal config with UTC timezone for deterministic tests
  printf '{repos: [], tz_offset_hours: 0}\n' > "$TEST_HOME/.config/work-context.sup"

  # Compute test timestamps (ISO format, UTC)
  # "today" = today at 10:00 UTC, "yesterday" = yesterday at 10:00 UTC, etc.
  TODAY_DATE=$(date +"%Y-%m-%d")
  YESTERDAY_DATE=$(date -v-1d +"%Y-%m-%d" 2>/dev/null || date -d "1 day ago" +"%Y-%m-%d")
  THREE_DAYS_AGO_DATE=$(date -v-3d +"%Y-%m-%d" 2>/dev/null || date -d "3 days ago" +"%Y-%m-%d")

  TODAY_TS="${TODAY_DATE}T10:00:00Z"
  YESTERDAY_TS="${YESTERDAY_DATE}T10:00:00Z"
  THREE_DAYS_AGO_TS="${THREE_DAYS_AGO_DATE}T10:00:00Z"

  # Source the script with controlled config
  export CLAUDE_PROJECTS_DIR="$TEST_HOME/.claude/projects"
  export WORK_CONTEXT_CONFIG="$TEST_HOME/.config/work-context.sup"
  source "$SCRIPT"
  # Undo strict -u (unbound vars) and -o pipefail from sourced script,
  # but keep -e so bats assertions actually catch failures
  set +uo pipefail
}

teardown() {
  [[ -n "${TEST_HOME:-}" && -d "$TEST_HOME" ]] && rm -rf "$TEST_HOME"
}

# Helper: create a fake JSONL conversation file
# Args: filename session_id timestamp prompt [msg_count]
create_conversation() {
  local filename="$1" session_id="$2" timestamp="$3" prompt="$4"
  local msg_count="${5:-5}"
  local dir="$TEST_HOME/.claude/projects/test-project"

  # Write enough user messages to satisfy msg_count grep
  {
    printf '{"type":"user","sessionId":"%s","timestamp":"%s","message":{"content":"%s"},"gitBranch":"main"}\n' \
      "$session_id" "$timestamp" "$prompt"
    for ((i=2; i<=msg_count; i++)); do
      printf '{"type":"user","sessionId":"%s","timestamp":"%s","message":{"content":"follow-up %d"},"gitBranch":"main"}\n' \
        "$session_id" "$timestamp" "$i"
    done
  } > "$dir/$filename"
}

# ==============================================================================
# conversations_json filtering
# ==============================================================================

@test "conversations_json days=0 returns only today's conversations" {
  create_conversation "today.jsonl" "sess-today" "$TODAY_TS" "today prompt"
  create_conversation "yesterday.jsonl" "sess-yesterday" "$YESTERDAY_TS" "yesterday prompt"

  run conversations_json 0
  assert_success
  [[ "$output" == *"sess-today"* ]]
  [[ "$output" != *"sess-yesterday"* ]]
}

@test "conversations_json days=1 returns today and yesterday" {
  create_conversation "today.jsonl" "sess-today" "$TODAY_TS" "today prompt"
  create_conversation "yesterday.jsonl" "sess-yesterday" "$YESTERDAY_TS" "yesterday prompt"
  create_conversation "old.jsonl" "sess-old" "$THREE_DAYS_AGO_TS" "old prompt"

  run conversations_json 1
  assert_success
  [[ "$output" == *"sess-today"* ]]
  [[ "$output" == *"sess-yesterday"* ]]
  [[ "$output" != *"sess-old"* ]]
}

@test "conversations_json days=7 returns conversations within a week" {
  create_conversation "today.jsonl" "sess-today" "$TODAY_TS" "today prompt"
  create_conversation "3days.jsonl" "sess-3days" "$THREE_DAYS_AGO_TS" "3 days ago prompt"

  run conversations_json 7
  assert_success
  [[ "$output" == *"sess-today"* ]]
  [[ "$output" == *"sess-3days"* ]]
}

@test "conversations_json returns empty for no conversations" {
  run conversations_json 0
  assert_success
  [[ -z "$output" ]]
}

@test "conversations_json output includes expected fields" {
  create_conversation "today.jsonl" "sess-today" "$TODAY_TS" "hello world"

  run conversations_json 0
  assert_success
  [[ "$output" == *"sessionId"* ]]
  [[ "$output" == *"date"* ]]
  [[ "$output" == *"time"* ]]
  [[ "$output" == *"project"* ]]
  [[ "$output" == *"messageCount"* ]]
  [[ "$output" == *"first_prompt"* ]]
}

@test "conversations_json shows correct local date" {
  create_conversation "today.jsonl" "sess-today" "$TODAY_TS" "today prompt"

  local result
  result=$(conversations_json 0)
  # With tz_offset=0, the date field should match the UTC date
  [[ "$result" == *"$TODAY_DATE"* ]]
}

# ==============================================================================
# conversations (human-readable) delegates to conversations_json
# ==============================================================================

@test "conversations output includes conversation data" {
  # mlr must be available for formatted output
  command -v mlr &>/dev/null || skip "mlr not installed"

  create_conversation "today.jsonl" "sess-today" "$TODAY_TS" "my test prompt"

  run conversations 0
  assert_success
  [[ "$output" == *"RECENT CLAUDE CONVERSATIONS"* ]]
  [[ "$output" == *"my test prompt"* ]]
}

@test "conversations excludes old data same as conversations_json" {
  command -v mlr &>/dev/null || skip "mlr not installed"

  create_conversation "today.jsonl" "sess-today" "$TODAY_TS" "today prompt"
  create_conversation "yesterday.jsonl" "sess-yesterday" "$YESTERDAY_TS" "yesterday prompt"

  run conversations 0
  assert_success
  [[ "$output" == *"today prompt"* ]]
  [[ "$output" != *"yesterday prompt"* ]]
}

# ==============================================================================
# Cutoff calculation uses local time (UTC bug regression test)
# ==============================================================================

@test "conversations_json cutoff uses local date not UTC date" {
  # With tz_offset=-6 (CST): local midnight = 06:00 UTC
  # A conversation at 23:00 local (05:00 UTC next day) should be "today" local
  #
  # We test this by: setting tz_offset=-6 and creating a conversation
  # whose UTC timestamp is "tomorrow" but local date is "today".
  # If the code wrongly used UTC date for cutoff, this would be excluded.

  # Reconfigure with CST offset
  tz_offset_hours=-6

  # Conversation at 23:00 local today = 05:00 UTC tomorrow
  local tomorrow_date
  tomorrow_date=$(date -v+1d +"%Y-%m-%d" 2>/dev/null || date -d "1 day" +"%Y-%m-%d")
  local late_evening_utc="${tomorrow_date}T05:00:00Z"

  create_conversation "late.jsonl" "sess-late" "$late_evening_utc" "late evening prompt"

  run conversations_json 0
  assert_success
  [[ "$output" == *"sess-late"* ]]
}

# ==============================================================================
# worktrees_json filtering
# ==============================================================================

# Helper: override collect_worktree_data with fake worktree records
inject_worktree_data() {
  local now
  now=$(date +%s)
  # Must export so override survives into pipe subshells
  collect_worktree_data() {
    local _now; _now=$(date +%s)
    printf '{"name":"ds1","branch":"main","commit_ts":%s,"commit_msg":"latest commit","dirty":false,"gone":false}\n' "$_now"
    printf '{"name":"ds2","branch":"staging-2","commit_ts":%s,"commit_msg":"old commit","dirty":false,"gone":false}\n' "$((_now - 86400 * 30))"
    printf '{"name":"ds3","branch":"feat-123-something","commit_ts":%s,"commit_msg":"feature work","dirty":true,"gone":false}\n' "$((_now - 86400 * 5))"
    printf '{"name":"ds4","branch":"staging-7","commit_ts":%s,"commit_msg":"parked","dirty":false,"gone":false}\n' "$((_now - 86400 * 20))"
    printf '{"name":"ds5","branch":"feat-merged-and-deleted","commit_ts":%s,"commit_msg":"merged work","dirty":false,"gone":true}\n' "$((_now - 86400 * 3))"
  }
  export -f collect_worktree_data
}

@test "worktrees_json excludes staging branches by default" {
  inject_worktree_data

  local result
  result=$(worktrees_json)
  echo "$result" | grep -q "ds1"
  echo "$result" | grep -q "ds3"
  ! echo "$result" | grep -q "staging-2"
  ! echo "$result" | grep -q "staging-7"
}

@test "worktrees_json --all includes staging branches" {
  inject_worktree_data

  local result
  result=$(worktrees_json --all)
  echo "$result" | grep -q "staging-2"
  echo "$result" | grep -q "staging-7"
  echo "$result" | grep -q "ds1"
  echo "$result" | grep -q "ds3"
}

# ==============================================================================
# worktrees (human-readable) dirty column + branch truncation
# ==============================================================================

@test "worktrees has a dedicated dirty column" {
  command -v mlr &>/dev/null || skip "mlr not installed"
  inject_worktree_data

  run worktrees
  assert_success
  # A column header named "dirty"
  [[ "$output" == *"dirty"* ]]
}

@test "worktrees does not append dirty marker to wt name" {
  command -v mlr &>/dev/null || skip "mlr not installed"
  inject_worktree_data

  run worktrees
  assert_success
  # ds3 is dirty; it must not appear as "ds3*" (the marker now lives in its own column)
  [[ "$output" != *"ds3*"* ]]
  # But ds3 itself must still be present
  [[ "$output" == *"ds3"* ]]
}

@test "worktrees has a dedicated gone column" {
  command -v mlr &>/dev/null || skip "mlr not installed"
  inject_worktree_data

  run worktrees
  assert_success
  # Column header "gone" must be present (alongside the existing "dirty" header)
  [[ "$output" == *"gone"* ]]
  # ds5 (gone:true) is 3d old, should appear in recent table with an 'x' marker
  [[ "$output" == *"ds5"* ]]
  # Check the ds5 row has an 'x' between two pipes (i.e., in a column cell)
  echo "$output" | grep -E "ds5\b" | grep -qE '\|\s*x\s*\|'
}

@test "worktrees truncates branch names to 46 chars" {
  command -v mlr &>/dev/null || skip "mlr not installed"

  collect_worktree_data() {
    local _now; _now=$(date +%s)
    # 57-char branch — should be truncated to its 46-char prefix
    printf '{"name":"ds1","branch":"devops-1149-support-revival-of-shutdown-staging-axon-worker","commit_ts":%s,"commit_msg":"x","dirty":false}\n' "$_now"
  }
  export -f collect_worktree_data

  run worktrees
  assert_success
  # Truncated form (46 chars) present
  [[ "$output" == *"devops-1149-support-revival-of-shutdown-stagin"* ]]
  # Full form absent
  [[ "$output" != *"devops-1149-support-revival-of-shutdown-staging-axon-worker"* ]]
}
