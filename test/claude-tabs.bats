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
  export CLAUDE_TABS_SESSIONS_DIR="$TEST_DIR/sessions"

  mkdir -p "$CLAUDE_TABS_PROJECTS_DIR" "$CLAUDE_TABS_SESSIONS_DIR"
}

teardown() {
  if [[ -n "$TEST_DIR" && -d "$TEST_DIR" ]]; then
    rm -rf "$TEST_DIR"
  fi
}

# write_session <pid> <cwd> <session_id> [kind]
# Writes a registry file shaped like the real ~/.claude/sessions/<pid>.json.
# Pass "" as kind to omit the field entirely (older sessions had no `kind`).
write_session() {
  local pid="$1" cwd="$2" sid="$3" kind="${4-interactive}"
  local kind_field=""
  [[ -n "$kind" ]] && kind_field="\"kind\":\"$kind\","
  cat > "$CLAUDE_TABS_SESSIONS_DIR/$pid.json" <<JSON
{"pid":$pid,"sessionId":"$sid","cwd":"$cwd","startedAt":1786147045266,"version":"2.1.224","peerProtocol":1,$kind_field"entrypoint":"cli","messagingSocketPath":"/tmp/cc-socks/$pid.sock","name":"fixture","status":"idle"}
JSON
}

# write_transcript <cwd> <session_id>
# The transcript `claude --resume <session_id>` would reopen.
write_transcript() {
  local dir="$CLAUDE_TABS_PROJECTS_DIR/$(echo "${1%/}" | tr / -)"
  mkdir -p "$dir"
  touch "$dir/$2.jsonl"
}

# Fixture PIDs aren't real processes — let every registry entry through.
# Call after sourcing claude-tabs; the override sticks for the whole test.
stub_pid_liveness() {
  pid_is_live() { return 0; }
}

# registry_line <cwd> <session_id> [kind]
# One line of the NDJSON that read_registry emits and detect_sessions consumes.
registry_line() {
  local kind="${3-interactive}"
  if [[ -n "$kind" ]]; then
    printf '{"cwd":"%s","sessionId":"%s","kind":"%s"}\n' "$1" "$2" "$kind"
  else
    printf '{"cwd":"%s","sessionId":"%s"}\n' "$1" "$2"
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
# detect_sessions (registry NDJSON → manifest)
# ─────────────────────────────────────────────────────────────────────────────

@test "detect_sessions builds a manifest row from a registry entry" {
  source "$CLAUDE_TABS"

  write_transcript /Users/chrismo/dev/ds5 abc-123-def

  run detect_sessions "$(registry_line /Users/chrismo/dev/ds5 abc-123-def)"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *'"path": "/Users/chrismo/dev/ds5"'* ]]
  [[ "$output" == *'"session_id": "abc-123-def"'* ]]
  [[ "$output" == *'"name": "ds5"'* ]]
}

@test "detect_sessions pairs each session with its own recorded session_id" {
  source "$CLAUDE_TABS"

  # Three sessions in one directory. The registry records which session id
  # belongs to which — the old lsof path could only rank the directory's
  # transcripts by mtime and hope the pairing was right.
  write_transcript /Users/chrismo/dev/ds5 sess-a
  write_transcript /Users/chrismo/dev/ds5 sess-b
  write_transcript /Users/chrismo/dev/ds5 sess-c
  # A stale transcript from an exited session must not be resurrected.
  write_transcript /Users/chrismo/dev/ds5 old-stale

  ndjson="$(registry_line /Users/chrismo/dev/ds5 sess-a
            registry_line /Users/chrismo/dev/ds5 sess-b
            registry_line /Users/chrismo/dev/ds5 sess-c)"

  run detect_sessions "$ndjson"
  [[ "$status" -eq 0 ]]

  local path_count
  path_count=$(echo "$output" | grep -c '"path": "/Users/chrismo/dev/ds5"')
  [[ "$path_count" -eq 3 ]]

  [[ "$output" == *'"session_id": "sess-a"'* ]]
  [[ "$output" == *'"session_id": "sess-b"'* ]]
  [[ "$output" == *'"session_id": "sess-c"'* ]]
  [[ "$output" != *'"session_id": "old-stale"'* ]]
}

@test "detect_sessions skips a session with no transcript on disk" {
  source "$CLAUDE_TABS"

  # A tab opened but never typed into: the registry has it, but Claude has
  # written no transcript, so `claude --resume` has nothing to reopen.
  run detect_sessions "$(registry_line /Users/chrismo/dev/ds5 never-prompted)"
  [[ "$status" -eq 0 ]]
  [[ "$output" == "[]" ]]
}

@test "detect_sessions skips sessions that aren't terminal tabs" {
  source "$CLAUDE_TABS"

  # kind is one of interactive / bg / daemon / daemon-worker. Only the first
  # is a tab someone wants reopened.
  write_transcript /Users/chrismo/dev/ds5 bg-1
  write_transcript /Users/chrismo/dev/ds5 daemon-1

  ndjson="$(registry_line /Users/chrismo/dev/ds5 bg-1 bg
            registry_line /Users/chrismo/dev/ds5 daemon-1 daemon)"

  run detect_sessions "$ndjson"
  [[ "$status" -eq 0 ]]
  [[ "$output" == "[]" ]]
}

@test "detect_sessions keeps entries written before kind existed" {
  source "$CLAUDE_TABS"

  write_transcript /Users/chrismo/dev/ds5 no-kind

  run detect_sessions "$(registry_line /Users/chrismo/dev/ds5 no-kind '')"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *'"session_id": "no-kind"'* ]]
}

@test "detect_sessions returns an empty array for no input" {
  source "$CLAUDE_TABS"

  run detect_sessions ""
  [[ "$status" -eq 0 ]]
  [[ "$output" == "[]" ]]
}

@test "detect_sessions handles multiple Claude sessions" {
  source "$CLAUDE_TABS"

  write_transcript /Users/chrismo/dev/ds5 abc-123
  write_transcript /Users/chrismo/dev/mta def-456

  ndjson="$(registry_line /Users/chrismo/dev/ds5 abc-123
            registry_line /Users/chrismo/dev/mta def-456)"

  run detect_sessions "$ndjson"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *'"name": "ds5"'* ]]
  [[ "$output" == *'"name": "mta"'* ]]
  [[ "$output" == *'"session_id": "abc-123"'* ]]
  [[ "$output" == *'"session_id": "def-456"'* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# read_registry (session discovery)
# ─────────────────────────────────────────────────────────────────────────────
#
# These use real PIDs against the real liveness check: $$ is this bats process
# (alive), and 999999 is above macOS's default pid_max so it never exists.

@test "read_registry emits a line per live session" {
  source "$CLAUDE_TABS"

  write_session "$$" /Users/chrismo/dev/ds5 abc-123

  run read_registry
  [[ "$status" -eq 0 ]]
  [[ "$output" == *'"cwd":"/Users/chrismo/dev/ds5"'* ]]
  [[ "$output" == *'"sessionId":"abc-123"'* ]]
}

@test "read_registry skips sessions whose process is gone" {
  source "$CLAUDE_TABS"

  # Claude removes its registry file on a clean exit, but a killed session
  # (Ghostty quit, SIGKILL) leaves one behind.
  write_session 999999 /Users/chrismo/dev/dead dead-1
  write_session "$$" /Users/chrismo/dev/ds5 abc-123

  run read_registry
  [[ "$status" -eq 0 ]]
  [[ "$output" == *'"sessionId":"abc-123"'* ]]
  [[ "$output" != *"dead-1"* ]]
}

@test "read_registry ignores files that aren't <pid>.json" {
  source "$CLAUDE_TABS"

  echo '{"cwd":"/Users/chrismo/dev/junk","sessionId":"junk-1"}' \
    > "$CLAUDE_TABS_SESSIONS_DIR/not-a-pid.json"
  echo 'not json' > "$CLAUDE_TABS_SESSIONS_DIR/README.txt"

  run read_registry
  [[ "$status" -eq 0 ]]
  [[ "$output" != *"junk-1"* ]]
  [[ "$output" != *"not json"* ]]
}

@test "read_registry emits nothing when the registry dir is missing" {
  source "$CLAUDE_TABS"

  export CLAUDE_TABS_SESSIONS_DIR="$TEST_DIR/no-such-dir"
  run read_registry
  [[ "$status" -eq 0 ]]
  [[ -z "$output" ]]
}

@test "read_registry does not shell out to pgrep or lsof" {
  # The old discovery path missed running sessions when `pgrep` was called
  # from a claude-spawned subprocess. Reading the registry must not depend
  # on either tool being visible or working.
  export PATH="$TEST_DIR/bin:$PATH"
  mkdir -p "$TEST_DIR/bin"
  for tool in pgrep lsof; do
    printf '#!/bin/bash\necho "%s should not be called" >&2\nexit 99\n' "$tool" \
      > "$TEST_DIR/bin/$tool"
    chmod +x "$TEST_DIR/bin/$tool"
  done

  source "$CLAUDE_TABS"
  write_session "$$" /Users/chrismo/dev/ds5 abc-123

  run read_registry
  [[ "$status" -eq 0 ]]
  [[ "$output" != *"should not be called"* ]]
  [[ "$output" == *'"sessionId":"abc-123"'* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# Manifest write/read round-trip (save + list-active)
# ─────────────────────────────────────────────────────────────────────────────

@test "save writes manifest and list-active reads it back" {
  source "$CLAUDE_TABS"
  stub_pid_liveness

  write_session 925 /Users/chrismo/dev/ds5 abc-123
  write_transcript /Users/chrismo/dev/ds5 abc-123

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
  stub_pid_liveness

  write_session 925 /Users/chrismo/dev/ds5 abc-123
  write_transcript /Users/chrismo/dev/ds5 abc-123
  write_session 3616 /Users/chrismo/dev/mta def-456
  write_transcript /Users/chrismo/dev/mta def-456

  run cmd_save
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Saved 2 sessions"* ]]
}

@test "list-active pipes JSON through grdy for table display" {
  source "$CLAUDE_TABS"
  stub_pid_liveness

  write_session 925 /Users/chrismo/dev/ds5 abc-123
  write_transcript /Users/chrismo/dev/ds5 abc-123

  run cmd_list_active
  [[ "$status" -eq 0 ]]
  # Should contain box-drawing characters from grdy table
  [[ "$output" == *"╭"* ]]
  [[ "$output" == *"ds5"* ]]
  # Should NOT contain the old "active Claude sessions" text
  [[ "$output" != *"active Claude sessions"* ]]
  # Manifest should NOT be written
  [[ ! -f "$CLAUDE_TABS_MANIFEST" ]]
}

@test "save writes manifest sorted by name" {
  source "$CLAUDE_TABS"
  stub_pid_liveness

  # Written in non-alphabetical order; the registry is read in filename order.
  write_session 1 /Users/chrismo/dev/zebra z-1
  write_transcript /Users/chrismo/dev/zebra z-1
  write_session 2 /Users/chrismo/dev/apple a-1
  write_transcript /Users/chrismo/dev/apple a-1
  write_session 3 /Users/chrismo/dev/mango m-1
  write_transcript /Users/chrismo/dev/mango m-1

  cmd_save

  local manifest
  manifest=$(cat "$CLAUDE_TABS_MANIFEST")

  local apple_idx mango_idx zebra_idx
  apple_idx=$(echo "$manifest" | grep -n '"name": "apple"' | head -1 | cut -d: -f1)
  mango_idx=$(echo "$manifest" | grep -n '"name": "mango"' | head -1 | cut -d: -f1)
  zebra_idx=$(echo "$manifest" | grep -n '"name": "zebra"' | head -1 | cut -d: -f1)

  [[ "$apple_idx" -lt "$mango_idx" ]]
  [[ "$mango_idx" -lt "$zebra_idx" ]]
}

@test "list-active with no sessions produces no output" {
  source "$CLAUDE_TABS"
  stub_pid_liveness

  # In the registry but with no transcript — nothing to resume, nothing to show.
  write_session 3616 /Users/chrismo/dev/never-prompted zzz-999

  run cmd_list_active
  [[ "$status" -eq 0 ]]
  [[ -z "$output" ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# list-saved (reads the manifest, not live processes)
# ─────────────────────────────────────────────────────────────────────────────

@test "list-saved renders the saved manifest as a grdy table" {
  source "$CLAUDE_TABS"

  cat > "$CLAUDE_TABS_MANIFEST" <<'MANIFEST'
[
  {"name": "ds5", "path": "/Users/chrismo/dev/ds5", "session_id": "abc-123"},
  {"name": "mta", "path": "/Users/chrismo/dev/mta", "session_id": "def-456"}
]
MANIFEST

  run cmd_list_saved
  [[ "$status" -eq 0 ]]
  # Box-drawing chars from the grdy table
  [[ "$output" == *"╭"* ]]
  [[ "$output" == *"ds5"* ]]
  [[ "$output" == *"mta"* ]]
  [[ "$output" == *"abc-123"* ]]
}

@test "list-saved does not consult live sessions" {
  source "$CLAUDE_TABS"
  stub_pid_liveness

  # A live session that is NOT in the manifest must not appear.
  write_session 925 /Users/chrismo/dev/live-only live-999
  write_transcript /Users/chrismo/dev/live-only live-999

  cat > "$CLAUDE_TABS_MANIFEST" <<'MANIFEST'
[
  {"name": "ds5", "path": "/Users/chrismo/dev/ds5", "session_id": "abc-123"}
]
MANIFEST

  run cmd_list_saved
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"ds5"* ]]
  [[ "$output" != *"live-only"* ]]
}

@test "list-saved reports gracefully when no manifest exists" {
  source "$CLAUDE_TABS"

  export CLAUDE_TABS_MANIFEST="$TEST_DIR/nonexistent.json"
  run cmd_list_saved
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"$TEST_DIR/nonexistent.json"* ]]
  [[ "$output" == *"o saved"* ]]
}

@test "list-saved reports gracefully on an empty manifest" {
  source "$CLAUDE_TABS"

  echo "[]" > "$CLAUDE_TABS_MANIFEST"
  run cmd_list_saved
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"empty"* ]]
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
  [[ "$script" == *'sendToTerminal'* ]]
  [[ "$script" == *'new tab'* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# usage / dispatch
# ─────────────────────────────────────────────────────────────────────────────

@test "usage lists list-active and list-saved and the history path" {
  export CLAUDE_TABS_HISTORY_DIR="$TEST_DIR/tab-history"

  run "$CLAUDE_TABS"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"list-active"* ]]
  [[ "$output" == *"list-saved"* ]]
  # Plain `list` is gone — must not be advertised.
  [[ "$output" != *"  list "* ]]
  # History location is surfaced, with the real resolved path.
  [[ "$output" == *"$TEST_DIR/tab-history"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# save history
# ─────────────────────────────────────────────────────────────────────────────

@test "save copies manifest to history dir" {
  source "$CLAUDE_TABS"
  stub_pid_liveness
  export CLAUDE_TABS_HISTORY_DIR="$TEST_DIR/tab-history"

  write_session 925 /Users/chrismo/dev/ds5 abc-123
  write_transcript /Users/chrismo/dev/ds5 abc-123

  cmd_save

  [[ -d "$CLAUDE_TABS_HISTORY_DIR" ]]
  local count
  count=$(ls "$CLAUDE_TABS_HISTORY_DIR" | wc -l | tr -d ' ')
  [[ "$count" -eq 1 ]]
}

@test "save history content matches manifest" {
  source "$CLAUDE_TABS"
  stub_pid_liveness
  export CLAUDE_TABS_HISTORY_DIR="$TEST_DIR/tab-history"

  write_session 925 /Users/chrismo/dev/ds5 abc-123
  write_transcript /Users/chrismo/dev/ds5 abc-123

  cmd_save

  local history_file
  history_file=$(ls "$CLAUDE_TABS_HISTORY_DIR"/*)
  diff "$CLAUDE_TABS_MANIFEST" "$history_file"
}

@test "save creates multiple history files on repeated saves" {
  source "$CLAUDE_TABS"
  stub_pid_liveness
  export CLAUDE_TABS_HISTORY_DIR="$TEST_DIR/tab-history"

  write_session 925 /Users/chrismo/dev/ds5 abc-123
  write_transcript /Users/chrismo/dev/ds5 abc-123

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
