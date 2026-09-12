#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

# Test suite for bin/claude-search.
#
# Focus: search_claude_projects and search_pi_sessions — the two transcript
# readers behind `claude-search`. pi's JSONL schema differs from Claude
# Code's (session id on a single type=session record, prompt text nested at
# message.content[0].text instead of a plain string), so each gets its own
# fixture and its own test.

CS="$BATS_TEST_DIRNAME/agent-search"

setup() {
  source "$CS"
}

# ── search_claude_projects ──────────────────────────────────────────────────

@test "finds a matching Claude prompt within the day window" {
  local dir="$BATS_TEST_TMPDIR/claude-projects/-Users-tester-dev-widget"
  mkdir -p "$dir"
  # Mixed schema: one record carries the optional flags, one doesn't — the
  # common shape in real ~/.claude transcripts.
  cat > "$dir/session.jsonl" <<-EOF
	{"type":"user","isMeta":true,"isCompactSummary":true,"timestamp":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","sessionId":"abc123","cwd":"/Users/tester/dev/widget","message":{"content":"meta record"}}
	{"type":"user","timestamp":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","sessionId":"abc123","cwd":"/Users/tester/dev/widget","message":{"content":"fix the fivetran connector"}}
	EOF

  run search_claude_projects "fivetran" 30 "$BATS_TEST_TMPDIR/claude-projects"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"source":"claude"'* ]] || false
  [[ "$output" == *'"sessionId":"abc123"'* ]] || false
  [[ "$output" == *'"project":"widget"'* ]]
}

@test "finds a Claude prompt when no record carries isMeta/isCompactSummary" {
  # Real transcripts often contain neither field anywhere in the file. The
  # optional-field checks must not reference a field name that super cannot
  # resolve in the input schema, or the whole query fails to compile.
  local dir="$BATS_TEST_TMPDIR/claude-projects/-Users-tester-dev-widget"
  mkdir -p "$dir"
  cat > "$dir/session.jsonl" <<-EOF
	{"type":"user","timestamp":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","sessionId":"abc123","cwd":"/Users/tester/dev/widget","message":{"content":"fix the fivetran connector"}}
	EOF

  run search_claude_projects "fivetran" 30 "$BATS_TEST_TMPDIR/claude-projects"
  [ "$status" -eq 0 ]
  [[ "$output" == *"fivetran"* ]]
}

@test "excludes meta and compact-summary Claude records" {
  local dir="$BATS_TEST_TMPDIR/claude-projects/-Users-tester-dev-widget"
  mkdir -p "$dir"
  cat > "$dir/session.jsonl" <<-EOF
	{"type":"user","isMeta":true,"timestamp":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","sessionId":"abc123","cwd":"/Users/tester/dev/widget","message":{"content":"meta fivetran record"}}
	{"type":"user","isCompactSummary":true,"timestamp":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","sessionId":"abc123","cwd":"/Users/tester/dev/widget","message":{"content":"summary fivetran record"}}
	EOF

  run search_claude_projects "fivetran" 30 "$BATS_TEST_TMPDIR/claude-projects"
  [ "$status" -eq 0 ]
  [[ "$output" != *"fivetran"* ]]
}

@test "excludes Claude prompts outside the day window" {
  local dir="$BATS_TEST_TMPDIR/claude-projects/-Users-tester-dev-widget"
  mkdir -p "$dir"
  cat > "$dir/session.jsonl" <<-EOF
	{"type":"user","isMeta":true,"isCompactSummary":true,"timestamp":"2020-01-01T00:00:00Z","sessionId":"abc123","cwd":"/Users/tester/dev/widget","message":{"content":"meta record"}}
	{"type":"user","timestamp":"2020-01-01T00:00:00Z","sessionId":"abc123","cwd":"/Users/tester/dev/widget","message":{"content":"fix the fivetran connector"}}
	EOF

  run search_claude_projects "fivetran" 30 "$BATS_TEST_TMPDIR/claude-projects"
  [ "$status" -eq 0 ]
  [[ "$output" != *"fivetran"* ]]
}

# ── search_pi_sessions ───────────────────────────────────────────────────────

@test "finds a matching pi prompt via the nested content[0].text shape" {
  local dir="$BATS_TEST_TMPDIR/pi-sessions/-Users-tester-dev-widget"
  mkdir -p "$dir"
  cat > "$dir/2026-01-01_abc.jsonl" <<-EOF
	{"type":"session","id":"pi-session-1","cwd":"/Users/tester/dev/widget"}
	{"type":"message","message":{"role":"user","content":[{"text":"fix the fivetran connector"}]},"timestamp":"$(date -u +%Y-%m-%dT%H:%M:%SZ)"}
	EOF

  run search_pi_sessions "fivetran" 30 "$BATS_TEST_TMPDIR/pi-sessions"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"source":"pi"'* ]] || false
  [[ "$output" == *'"sessionId":"pi-session-1"'* ]] || false
  [[ "$output" == *'"project":"widget"'* ]]
}

@test "excludes pi prompts outside the day window" {
  local dir="$BATS_TEST_TMPDIR/pi-sessions/-Users-tester-dev-widget"
  mkdir -p "$dir"
  cat > "$dir/2020-01-01_abc.jsonl" <<-EOF
	{"type":"session","id":"pi-session-1","cwd":"/Users/tester/dev/widget"}
	{"type":"message","message":{"role":"user","content":[{"text":"fix the fivetran connector"}]},"timestamp":"2020-01-01T00:00:00Z"}
	EOF

  run search_pi_sessions "fivetran" 30 "$BATS_TEST_TMPDIR/pi-sessions"
  [ "$status" -eq 0 ]
  [[ "$output" != *"fivetran"* ]]
}

@test "ignores non-user pi messages (e.g. assistant/toolResult)" {
  local dir="$BATS_TEST_TMPDIR/pi-sessions/-Users-tester-dev-widget"
  mkdir -p "$dir"
  cat > "$dir/2026-01-01_abc.jsonl" <<-EOF
	{"type":"session","id":"pi-session-1","cwd":"/Users/tester/dev/widget"}
	{"type":"message","message":{"role":"assistant","content":[{"text":"fivetran fix applied"}]},"timestamp":"$(date -u +%Y-%m-%dT%H:%M:%SZ)"}
	EOF

  run search_pi_sessions "fivetran" 30 "$BATS_TEST_TMPDIR/pi-sessions"
  [ "$status" -eq 0 ]
  [[ "$output" != *"fivetran"* ]]
}
