#!/usr/bin/env bats
# claude-tabs.bats - Tests for claude-tabs save/restore
#
# Run with: bats test/claude-tabs.bats

CLAUDE_TABS="${BATS_TEST_DIRNAME}/../bin/claude-tabs"
CLAUDE_SLOT="${BATS_TEST_DIRNAME}/../bin/claude-slot"

setup() {
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/claude-tabs-test.XXXXXX")"
  export CLAUDE_TABS_PROJECTS_DIR="$TEST_DIR/projects"
  export CLAUDE_TABS_MANIFEST="$TEST_DIR/tab-state.json"

  mkdir -p "$CLAUDE_TABS_PROJECTS_DIR"
}

teardown() {
  if [[ -n "$TEST_DIR" && -d "$TEST_DIR" ]]; then
    rm -rf "$TEST_DIR"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# encode_project_path
# ─────────────────────────────────────────────────────────────────────────────

@test "encode_project_path replaces slashes with dashes" {
  source "$CLAUDE_TABS"
  run encode_project_path "/Users/chrismo/dev/ds5"
  [[ "$output" == "-Users-chrismo-dev-ds5" ]]
}

@test "encode_project_path handles trailing slash" {
  source "$CLAUDE_TABS"
  run encode_project_path "/Users/chrismo/dev/ds5/"
  [[ "$output" == "-Users-chrismo-dev-ds5" ]]
}

@test "encode_project_path handles path with spaces" {
  source "$CLAUDE_TABS"
  run encode_project_path "/Users/chrismo/Google Drive/work-rig/dev/ds5"
  [[ "$output" == "-Users-chrismo-Google Drive-work-rig-dev-ds5" ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# detect_sessions (from mock lsof output)
# ─────────────────────────────────────────────────────────────────────────────

@test "detect_sessions finds Claude session from lsof output" {
  source "$CLAUDE_TABS"

  # Create mock projects dir with JSONL
  mkdir -p "$CLAUDE_TABS_PROJECTS_DIR/-Users-chrismo-dev-ds5"
  touch "$CLAUDE_TABS_PROJECTS_DIR/-Users-chrismo-dev-ds5/abc-123-def.jsonl"

  # Mock lsof output: pid line then cwd line
  lsof_output="$(printf 'p925\nn/Users/chrismo/dev/ds5\np3616\nn/Users/chrismo/dev/not-a-claude-project\n')"

  run detect_sessions "$lsof_output"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *'"path": "/Users/chrismo/dev/ds5"'* ]]
  [[ "$output" == *'"session_id": "abc-123-def"'* ]]
  [[ "$output" == *'"name": "ds5"'* ]]
}

@test "detect_sessions skips non-Claude node processes" {
  source "$CLAUDE_TABS"

  # No projects dir for this path
  lsof_output="$(printf 'p3616\nn/Users/chrismo/dev/not-a-claude-project\n')"

  run detect_sessions "$lsof_output"
  [[ "$status" -eq 0 ]]
  [[ "$output" == "[]" ]]
}

@test "detect_sessions deduplicates cwds" {
  source "$CLAUDE_TABS"

  mkdir -p "$CLAUDE_TABS_PROJECTS_DIR/-Users-chrismo-dev-ds5"
  touch "$CLAUDE_TABS_PROJECTS_DIR/-Users-chrismo-dev-ds5/abc-123.jsonl"

  # Same cwd from two different PIDs
  lsof_output="$(printf 'p925\nn/Users/chrismo/dev/ds5\np926\nn/Users/chrismo/dev/ds5\n')"

  run detect_sessions "$lsof_output"
  [[ "$status" -eq 0 ]]
  # Should only appear once — count occurrences of "ds5" path entries
  local count
  count=$(echo "$output" | grep -c '"path": "/Users/chrismo/dev/ds5"')
  [[ "$count" -eq 1 ]]
}

@test "detect_sessions picks most recent JSONL as session ID" {
  source "$CLAUDE_TABS"

  mkdir -p "$CLAUDE_TABS_PROJECTS_DIR/-Users-chrismo-dev-ds5"
  # Create two JSONLs with different mtimes
  touch -t 202601010000 "$CLAUDE_TABS_PROJECTS_DIR/-Users-chrismo-dev-ds5/old-session.jsonl"
  sleep 0.1
  touch "$CLAUDE_TABS_PROJECTS_DIR/-Users-chrismo-dev-ds5/new-session.jsonl"

  lsof_output="$(printf 'p925\nn/Users/chrismo/dev/ds5\n')"

  run detect_sessions "$lsof_output"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *'"session_id": "new-session"'* ]]
}

@test "detect_sessions handles multiple Claude sessions" {
  source "$CLAUDE_TABS"

  mkdir -p "$CLAUDE_TABS_PROJECTS_DIR/-Users-chrismo-dev-ds5"
  touch "$CLAUDE_TABS_PROJECTS_DIR/-Users-chrismo-dev-ds5/abc-123.jsonl"
  mkdir -p "$CLAUDE_TABS_PROJECTS_DIR/-Users-chrismo-dev-mta"
  touch "$CLAUDE_TABS_PROJECTS_DIR/-Users-chrismo-dev-mta/def-456.jsonl"

  lsof_output="$(printf 'p925\nn/Users/chrismo/dev/ds5\np3616\nn/Users/chrismo/dev/mta\n')"

  run detect_sessions "$lsof_output"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *'"name": "ds5"'* ]]
  [[ "$output" == *'"name": "mta"'* ]]
  [[ "$output" == *'"session_id": "abc-123"'* ]]
  [[ "$output" == *'"session_id": "def-456"'* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# Manifest write/read round-trip (save + list)
# ─────────────────────────────────────────────────────────────────────────────

@test "save writes manifest and list reads it back" {
  source "$CLAUDE_TABS"

  mkdir -p "$CLAUDE_TABS_PROJECTS_DIR/-Users-chrismo-dev-ds5"
  touch "$CLAUDE_TABS_PROJECTS_DIR/-Users-chrismo-dev-ds5/abc-123.jsonl"

  mock_lsof="$(printf 'p925\nn/Users/chrismo/dev/ds5\n')"
  export CLAUDE_TABS_LSOF_OUTPUT="$mock_lsof"

  # Save
  run cmd_save
  [[ "$status" -eq 0 ]]
  [[ -f "$CLAUDE_TABS_MANIFEST" ]]

  # Verify manifest content
  run cat "$CLAUDE_TABS_MANIFEST"
  [[ "$output" == *'"path": "/Users/chrismo/dev/ds5"'* ]]
  [[ "$output" == *'"session_id": "abc-123"'* ]]
}

@test "save reports count of sessions saved" {
  source "$CLAUDE_TABS"

  mkdir -p "$CLAUDE_TABS_PROJECTS_DIR/-Users-chrismo-dev-ds5"
  touch "$CLAUDE_TABS_PROJECTS_DIR/-Users-chrismo-dev-ds5/abc-123.jsonl"
  mkdir -p "$CLAUDE_TABS_PROJECTS_DIR/-Users-chrismo-dev-mta"
  touch "$CLAUDE_TABS_PROJECTS_DIR/-Users-chrismo-dev-mta/def-456.jsonl"

  mock_lsof="$(printf 'p925\nn/Users/chrismo/dev/ds5\np3616\nn/Users/chrismo/dev/mta\n')"
  export CLAUDE_TABS_LSOF_OUTPUT="$mock_lsof"

  run cmd_save
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Saved 2 sessions"* ]]
}

@test "list pipes JSON through grdy for table display" {
  source "$CLAUDE_TABS"

  mkdir -p "$CLAUDE_TABS_PROJECTS_DIR/-Users-chrismo-dev-ds5"
  touch "$CLAUDE_TABS_PROJECTS_DIR/-Users-chrismo-dev-ds5/abc-123.jsonl"

  mock_lsof="$(printf 'p925\nn/Users/chrismo/dev/ds5\n')"
  export CLAUDE_TABS_LSOF_OUTPUT="$mock_lsof"

  run cmd_list
  [[ "$status" -eq 0 ]]
  # Should contain box-drawing characters from grdy table
  [[ "$output" == *"╭"* ]]
  [[ "$output" == *"ds5"* ]]
  # Should NOT contain the old "active Claude sessions" text
  [[ "$output" != *"active Claude sessions"* ]]
  # Manifest should NOT be written
  [[ ! -f "$CLAUDE_TABS_MANIFEST" ]]
}

@test "list with no sessions produces no output" {
  source "$CLAUDE_TABS"

  mock_lsof="$(printf 'p3616\nn/Users/chrismo/dev/not-a-claude-project\n')"
  export CLAUDE_TABS_LSOF_OUTPUT="$mock_lsof"

  run cmd_list
  [[ "$status" -eq 0 ]]
  [[ -z "$output" ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# restore
# ─────────────────────────────────────────────────────────────────────────────

@test "restore generates claude-slot commands from manifest" {
  source "$CLAUDE_TABS"

  # Write a manifest directly
  cat > "$CLAUDE_TABS_MANIFEST" <<'MANIFEST'
[
  {"name": "ds5", "path": "/Users/chrismo/dev/ds5", "session_id": "abc-123"},
  {"name": "mta", "path": "/Users/chrismo/dev/mta", "session_id": "def-456"}
]
MANIFEST

  export CLAUDE_TABS_DRY_RUN=1
  run cmd_restore
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"/Users/chrismo/dev/ds5 --resume abc-123"* ]]
  [[ "$output" == *"/Users/chrismo/dev/mta --resume def-456"* ]]
}

@test "restore fails gracefully with missing manifest" {
  source "$CLAUDE_TABS"

  export CLAUDE_TABS_MANIFEST="$TEST_DIR/nonexistent.json"
  run cmd_restore
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"not found"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# batch restore
# ─────────────────────────────────────────────────────────────────────────────

@test "restore writes per-session cmd files" {
  source "$CLAUDE_TABS"
  export CLAUDE_TABS_CMD_DIR="$TEST_DIR/cmd-files"

  # Mock osascript
  export PATH="$TEST_DIR/bin:$PATH"
  mkdir -p "$TEST_DIR/bin"
  printf '#!/bin/bash\ncat > /dev/null\nexit 0\n' > "$TEST_DIR/bin/osascript"
  chmod +x "$TEST_DIR/bin/osascript"

  cat > "$CLAUDE_TABS_MANIFEST" <<'MANIFEST'
[
  {"name": "ds5", "path": "/Users/chrismo/dev/ds5", "session_id": "abc-123"},
  {"name": "mta", "path": "/Users/chrismo/dev/mta", "session_id": "def-456"}
]
MANIFEST

  cmd_restore

  [[ -f "$CLAUDE_TABS_CMD_DIR/cmd-0.txt" ]]
  [[ -f "$CLAUDE_TABS_CMD_DIR/cmd-1.txt" ]]

  local cmd0
  cmd0=$(cat "$CLAUDE_TABS_CMD_DIR/cmd-0.txt")
  [[ "$cmd0" == *"cd /Users/chrismo/dev/ds5"* ]]
  [[ "$cmd0" == *"claude --resume abc-123"* ]]

  local cmd1
  cmd1=$(cat "$CLAUDE_TABS_CMD_DIR/cmd-1.txt")
  [[ "$cmd1" == *"cd /Users/chrismo/dev/mta"* ]]
  [[ "$cmd1" == *"claude --resume def-456"* ]]
}

@test "restore invokes osascript exactly once for batch" {
  source "$CLAUDE_TABS"
  export CLAUDE_TABS_CMD_DIR="$TEST_DIR/cmd-files"
  export OSASCRIPT_COUNT_FILE="$TEST_DIR/osascript-count"

  # Mock osascript that counts invocations
  export PATH="$TEST_DIR/bin:$PATH"
  mkdir -p "$TEST_DIR/bin"
  cat > "$TEST_DIR/bin/osascript" <<'MOCK'
#!/bin/bash
count_file="${OSASCRIPT_COUNT_FILE}"
if [[ -f "$count_file" ]]; then
  count=$(($(cat "$count_file") + 1))
else
  count=1
fi
echo "$count" > "$count_file"
cat > /dev/null
exit 0
MOCK
  chmod +x "$TEST_DIR/bin/osascript"

  cat > "$CLAUDE_TABS_MANIFEST" <<'MANIFEST'
[
  {"name": "ds5", "path": "/Users/chrismo/dev/ds5", "session_id": "abc-123"},
  {"name": "mta", "path": "/Users/chrismo/dev/mta", "session_id": "def-456"}
]
MANIFEST

  cmd_restore

  [[ -f "$OSASCRIPT_COUNT_FILE" ]]
  local count
  count=$(cat "$OSASCRIPT_COUNT_FILE")
  [[ "$count" -eq 1 ]]
}

@test "build_restore_applescript includes session count and cmd dir" {
  source "$CLAUDE_TABS"

  local script
  script=$(build_restore_applescript "/tmp/test-cmds" 3)

  [[ "$script" == *'set sessionCount to 3'* ]]
  [[ "$script" == *'/tmp/test-cmds'* ]]
  [[ "$script" == *'pasteAndRun'* ]]
  [[ "$script" == *'newTab'* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# save history
# ─────────────────────────────────────────────────────────────────────────────

@test "save copies manifest to history dir" {
  source "$CLAUDE_TABS"
  export CLAUDE_TABS_HISTORY_DIR="$TEST_DIR/tab-history"

  mkdir -p "$CLAUDE_TABS_PROJECTS_DIR/-Users-chrismo-dev-ds5"
  touch "$CLAUDE_TABS_PROJECTS_DIR/-Users-chrismo-dev-ds5/abc-123.jsonl"

  export CLAUDE_TABS_LSOF_OUTPUT="$(printf 'p925\nn/Users/chrismo/dev/ds5\n')"

  cmd_save

  [[ -d "$CLAUDE_TABS_HISTORY_DIR" ]]
  local count
  count=$(ls "$CLAUDE_TABS_HISTORY_DIR" | wc -l | tr -d ' ')
  [[ "$count" -eq 1 ]]
}

@test "save history content matches manifest" {
  source "$CLAUDE_TABS"
  export CLAUDE_TABS_HISTORY_DIR="$TEST_DIR/tab-history"

  mkdir -p "$CLAUDE_TABS_PROJECTS_DIR/-Users-chrismo-dev-ds5"
  touch "$CLAUDE_TABS_PROJECTS_DIR/-Users-chrismo-dev-ds5/abc-123.jsonl"

  export CLAUDE_TABS_LSOF_OUTPUT="$(printf 'p925\nn/Users/chrismo/dev/ds5\n')"

  cmd_save

  local history_file
  history_file=$(ls "$CLAUDE_TABS_HISTORY_DIR"/*)
  diff "$CLAUDE_TABS_MANIFEST" "$history_file"
}

@test "save creates multiple history files on repeated saves" {
  source "$CLAUDE_TABS"
  export CLAUDE_TABS_HISTORY_DIR="$TEST_DIR/tab-history"

  mkdir -p "$CLAUDE_TABS_PROJECTS_DIR/-Users-chrismo-dev-ds5"
  touch "$CLAUDE_TABS_PROJECTS_DIR/-Users-chrismo-dev-ds5/abc-123.jsonl"

  export CLAUDE_TABS_LSOF_OUTPUT="$(printf 'p925\nn/Users/chrismo/dev/ds5\n')"

  cmd_save
  sleep 1
  cmd_save

  local count
  count=$(ls "$CLAUDE_TABS_HISTORY_DIR" | wc -l | tr -d ' ')
  [[ "$count" -eq 2 ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# claude-slot --resume flag parsing
# ─────────────────────────────────────────────────────────────────────────────

@test "claude-slot builds resume command" {
  export PATH="$TEST_DIR/bin:$PATH"
  mkdir -p "$TEST_DIR/bin"
  printf '#!/bin/bash\nexit 0\n' > "$TEST_DIR/bin/osascript"
  chmod +x "$TEST_DIR/bin/osascript"

  export CLAUDE_SLOT_CMD_DIR="$TEST_DIR/slot-cmd"
  mkdir -p "$TEST_DIR/worktree"
  run "$CLAUDE_SLOT" "$TEST_DIR/worktree" --resume abc-123-def
  [[ "$status" -eq 0 ]]

  cmd=$(cat "$CLAUDE_SLOT_CMD_DIR/cmd.txt")
  [[ "$cmd" == *"claude --resume abc-123-def"* ]]
}

@test "claude-slot resume flag does not include prompt" {
  export PATH="$TEST_DIR/bin:$PATH"
  mkdir -p "$TEST_DIR/bin"
  printf '#!/bin/bash\nexit 0\n' > "$TEST_DIR/bin/osascript"
  chmod +x "$TEST_DIR/bin/osascript"

  export CLAUDE_SLOT_CMD_DIR="$TEST_DIR/slot-cmd"
  mkdir -p "$TEST_DIR/worktree"
  run "$CLAUDE_SLOT" "$TEST_DIR/worktree" --resume abc-123
  [[ "$status" -eq 0 ]]

  cmd=$(cat "$CLAUDE_SLOT_CMD_DIR/cmd.txt")
  [[ "$cmd" == *"claude --resume abc-123"* ]]
  [[ "$cmd" != *"claude --resume abc-123 \""* ]]
}

@test "claude-slot without --resume still works with prompt" {
  export PATH="$TEST_DIR/bin:$PATH"
  mkdir -p "$TEST_DIR/bin"
  printf '#!/bin/bash\nexit 0\n' > "$TEST_DIR/bin/osascript"
  chmod +x "$TEST_DIR/bin/osascript"

  export CLAUDE_SLOT_CMD_DIR="$TEST_DIR/slot-cmd"
  mkdir -p "$TEST_DIR/worktree"
  run "$CLAUDE_SLOT" "$TEST_DIR/worktree" /mta:join PROJ-123
  [[ "$status" -eq 0 ]]

  cmd=$(cat "$CLAUDE_SLOT_CMD_DIR/cmd.txt")
  [[ "$cmd" == *'claude "/mta:join PROJ-123"'* ]]
}

@test "claude-slot without --resume and no prompt starts plain claude" {
  export PATH="$TEST_DIR/bin:$PATH"
  mkdir -p "$TEST_DIR/bin"
  printf '#!/bin/bash\nexit 0\n' > "$TEST_DIR/bin/osascript"
  chmod +x "$TEST_DIR/bin/osascript"

  export CLAUDE_SLOT_CMD_DIR="$TEST_DIR/slot-cmd"
  mkdir -p "$TEST_DIR/worktree"
  run "$CLAUDE_SLOT" "$TEST_DIR/worktree"
  [[ "$status" -eq 0 ]]

  cmd=$(cat "$CLAUDE_SLOT_CMD_DIR/cmd.txt")
  [[ "$cmd" == *"&& claude" ]]
}
