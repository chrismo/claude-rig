#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

# Test suite for bin/agent-search.
#
# Focus: search_claude_projects and search_pi_sessions — the two transcript
# readers behind `agent-search` — plus the end-to-end run. pi's JSONL schema
# differs from Claude Code's (session id and cwd on a single type=session
# record, prompt text in message.content blocks rather than a plain string),
# so each gets its own fixture and its own test.
#
# Fixtures must mirror the real on-disk shapes byte for byte: fixtures written
# to match the code instead of the data are what let both the isCompactSummary
# breakage and a pi filter that matched nothing ship green.

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
	{"type":"user","timestamp":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","sessionId":"abc123","cwd":"/Users/tester/dev/widget","message":{"content":"real fivetran prompt"}}
	EOF

  run search_claude_projects "fivetran" 30 "$BATS_TEST_TMPDIR/claude-projects"
  [ "$status" -eq 0 ]
  [[ "$output" == *"real fivetran prompt"* ]] || false
  [[ "$output" != *"meta fivetran"* ]] || false
  [[ "$output" != *"summary fivetran"* ]]
}

@test "excludes Claude prompts outside the day window" {
  local dir="$BATS_TEST_TMPDIR/claude-projects/-Users-tester-dev-widget"
  mkdir -p "$dir"
  cat > "$dir/session.jsonl" <<-EOF
	{"type":"user","isMeta":true,"isCompactSummary":true,"timestamp":"2020-01-01T00:00:00Z","sessionId":"abc123","cwd":"/Users/tester/dev/widget","message":{"content":"meta record"}}
	{"type":"user","timestamp":"2020-01-01T00:00:00Z","sessionId":"abc123","cwd":"/Users/tester/dev/widget","message":{"content":"fix the fivetran connector"}}
	{"type":"user","timestamp":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","sessionId":"abc123","cwd":"/Users/tester/dev/widget","message":{"content":"fivetran still in window"}}
	EOF

  run search_claude_projects "fivetran" 30 "$BATS_TEST_TMPDIR/claude-projects"
  [ "$status" -eq 0 ]
  [[ "$output" == *"still in window"* ]] || false
  [[ "$output" != *"connector"* ]]
}

# ── search_pi_sessions ───────────────────────────────────────────────────────

@test "finds a matching pi prompt via the nested content[0].text shape" {
  local dir="$BATS_TEST_TMPDIR/pi-sessions/--Users-tester-dev-widget--"
  mkdir -p "$dir"
  cat > "$dir/2026-01-01_abc.jsonl" <<-EOF
	{"type":"session","version":3,"id":"pi-session-1","timestamp":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","cwd":"/Users/tester/dev/widget"}
	{"type":"message","message":{"role":"user","content":[{"type":"text","text":"fix the fivetran connector"}]},"timestamp":"$(date -u +%Y-%m-%dT%H:%M:%SZ)"}
	EOF

  run search_pi_sessions "fivetran" 30 "$BATS_TEST_TMPDIR/pi-sessions"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"source":"pi"'* ]] || false
  [[ "$output" == *'"sessionId":"pi-session-1"'* ]] || false
  [[ "$output" == *'"project":"widget"'* ]]
}

@test "excludes pi prompts outside the day window" {
  local dir="$BATS_TEST_TMPDIR/pi-sessions/--Users-tester-dev-widget--"
  mkdir -p "$dir"
  # The in-window line is a positive control: without it, a reader that
  # returned nothing at all would satisfy the exclusion assertion.
  cat > "$dir/2020-01-01_abc.jsonl" <<-EOF
	{"type":"session","version":3,"id":"pi-session-1","timestamp":"2020-01-01T00:00:00Z","cwd":"/Users/tester/dev/widget"}
	{"type":"message","message":{"role":"user","content":[{"type":"text","text":"fix the fivetran connector"}]},"timestamp":"2020-01-01T00:00:00Z"}
	{"type":"message","message":{"role":"user","content":[{"type":"text","text":"fivetran still in window"}]},"timestamp":"$(date -u +%Y-%m-%dT%H:%M:%SZ)"}
	EOF

  run search_pi_sessions "fivetran" 30 "$BATS_TEST_TMPDIR/pi-sessions"
  [ "$status" -eq 0 ]
  [[ "$output" == *"still in window"* ]] || false
  [[ "$output" != *"connector"* ]]
}

@test "ignores non-user pi messages (e.g. assistant/toolResult)" {
  local dir="$BATS_TEST_TMPDIR/pi-sessions/--Users-tester-dev-widget--"
  mkdir -p "$dir"
  cat > "$dir/2026-01-01_abc.jsonl" <<-EOF
	{"type":"session","version":3,"id":"pi-session-1","timestamp":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","cwd":"/Users/tester/dev/widget"}
	{"type":"message","message":{"role":"assistant","content":[{"type":"text","text":"fivetran fix applied"}]},"timestamp":"$(date -u +%Y-%m-%dT%H:%M:%SZ)"}
	{"type":"message","message":{"role":"user","content":[{"type":"text","text":"fivetran asked about"}]},"timestamp":"$(date -u +%Y-%m-%dT%H:%M:%SZ)"}
	EOF

  run search_pi_sessions "fivetran" 30 "$BATS_TEST_TMPDIR/pi-sessions"
  [ "$status" -eq 0 ]
  [[ "$output" == *"asked about"* ]] || false
  [[ "$output" != *"fix applied"* ]]
}

@test "pi project label comes from the session header's cwd, not the encoded dir" {
  # pi wraps its directory names in a double dash and flattens '/' to '-', so
  # the dir name alone can't recover a project whose own name has a dash.
  local dir="$BATS_TEST_TMPDIR/pi-sessions/--Users-tester-modev-claude-rig--"
  mkdir -p "$dir"
  cat > "$dir/2026-01-01_abc.jsonl" <<-EOF
	{"type":"session","version":3,"id":"pi-session-2","timestamp":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","cwd":"/Users/tester/modev/claude-rig"}
	{"type":"message","message":{"role":"user","content":[{"type":"text","text":"fix the fivetran connector"}]},"timestamp":"$(date -u +%Y-%m-%dT%H:%M:%SZ)"}
	EOF

  run search_pi_sessions "fivetran" 30 "$BATS_TEST_TMPDIR/pi-sessions"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"project":"claude-rig"'* ]]
}

@test "pi prompt text survives a turn carrying more than one block kind" {
  local dir="$BATS_TEST_TMPDIR/pi-sessions/--Users-tester-dev-widget--"
  mkdir -p "$dir"
  cat > "$dir/2026-01-01_abc.jsonl" <<-EOF
	{"type":"session","version":3,"id":"pi-session-3","timestamp":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","cwd":"/Users/tester/dev/widget"}
	{"type":"message","message":{"role":"user","content":[{"type":"toolResult","output":"noise"},{"type":"text","text":"fix the fivetran connector"}]},"timestamp":"$(date -u +%Y-%m-%dT%H:%M:%SZ)"}
	EOF

  run search_pi_sessions "fivetran" 30 "$BATS_TEST_TMPDIR/pi-sessions"
  [ "$status" -eq 0 ]
  [[ "$output" == *"fix the fivetran connector"* ]] || false
  [[ "$output" == *'"sessionId":"pi-session-3"'* ]]
}

# ── Term escaping ────────────────────────────────────────────────────────────

@test "a term containing an apostrophe searches instead of dying on a parse error" {
  local dir="$BATS_TEST_TMPDIR/claude-projects/-Users-tester-dev-widget"
  mkdir -p "$dir"
  cat > "$dir/session.jsonl" <<-EOF
	{"type":"user","timestamp":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","sessionId":"abc123","cwd":"/Users/tester/dev/widget","message":{"content":"it doesn't reconnect"}}
	EOF

  run search_claude_projects "doesn't" 30 "$BATS_TEST_TMPDIR/claude-projects"
  [ "$status" -eq 0 ]
  [[ "$output" != *"parse error"* ]] || false
  [[ "$output" == *"reconnect"* ]]
}

@test "a term containing a backslash escape searches as a regex" {
  local dir="$BATS_TEST_TMPDIR/claude-projects/-Users-tester-dev-widget"
  mkdir -p "$dir"
  cat > "$dir/session.jsonl" <<-EOF
	{"type":"user","timestamp":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","sessionId":"abc123","cwd":"/Users/tester/dev/widget","message":{"content":"ticket ENG-4218 filed"}}
	EOF

  run search_claude_projects 'ENG-\d+' 30 "$BATS_TEST_TMPDIR/claude-projects"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ENG-4218"* ]]
}

# ── End to end ───────────────────────────────────────────────────────────────

# Every assertion below runs the script as a program, which is where the
# breakage that prompted this suite's rewrite actually lived.

@test "run: renders a table merging both sources, newest first" {
  local cdir="$BATS_TEST_TMPDIR/claude-projects/-Users-tester-dev-widget"
  local pdir="$BATS_TEST_TMPDIR/pi-sessions/--Users-tester-dev-gadget--"
  mkdir -p "$cdir" "$pdir"
  cat > "$cdir/session.jsonl" <<-EOF
	{"type":"user","timestamp":"2026-09-10T00:00:00Z","sessionId":"abc123","cwd":"/Users/tester/dev/widget","message":{"content":"fivetran from claude"}}
	EOF
  cat > "$pdir/2026-01-01_abc.jsonl" <<-EOF
	{"type":"session","version":3,"id":"pi-session-1","timestamp":"2026-09-11T00:00:00Z","cwd":"/Users/tester/dev/gadget"}
	{"type":"message","message":{"role":"user","content":[{"type":"text","text":"fivetran from pi"}]},"timestamp":"2026-09-11T00:00:00Z"}
	EOF

  CLAUDE_SEARCH_PROJECTS_DIR="$BATS_TEST_TMPDIR/claude-projects" \
  CLAUDE_SEARCH_PI_SESSIONS_DIR="$BATS_TEST_TMPDIR/pi-sessions" \
    run "$CS" fivetran 3650
  [ "$status" -eq 0 ]
  [[ "$output" == *"fivetran from claude"* ]] || false
  [[ "$output" == *"fivetran from pi"* ]] || false
  # Newest first: the pi row (09-11) precedes the claude row (09-10).
  [[ "$output" =~ from\ pi(.|$'\n')*from\ claude ]]
}

@test "run: says so when nothing matches, rather than printing nothing" {
  local cdir="$BATS_TEST_TMPDIR/claude-projects/-Users-tester-dev-widget"
  mkdir -p "$cdir"
  cat > "$cdir/session.jsonl" <<-EOF
	{"type":"user","timestamp":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","sessionId":"abc123","cwd":"/Users/tester/dev/widget","message":{"content":"nothing to see"}}
	EOF

  CLAUDE_SEARCH_PROJECTS_DIR="$BATS_TEST_TMPDIR/claude-projects" \
  CLAUDE_SEARCH_PI_SESSIONS_DIR="$BATS_TEST_TMPDIR/pi-sessions" \
    run "$CS" fivetran 30
  [ "$status" -eq 0 ]
  [[ "$output" == *"no prompts matching"* ]]
}

@test "a failing source is reported by name, and the other source still prints" {
  # Stubbed rather than provoked: a malformed transcript is skipped quietly
  # (see the test below), so the only way to exercise the failure path is to
  # make a reader fail outright. Under the old single-pipeline form, a failing
  # claude reader aborted the group before pi ever ran, and a failing pi
  # reader took the script's exit status down with no message.
  local cdir="$BATS_TEST_TMPDIR/claude-projects/-Users-tester-dev-widget"
  mkdir -p "$cdir"
  cat > "$cdir/session.jsonl" <<-EOF
	{"type":"user","timestamp":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","sessionId":"abc123","cwd":"/Users/tester/dev/widget","message":{"content":"fivetran from claude"}}
	EOF
  search_pi_sessions() { return 1; }

  CLAUDE_SEARCH_PROJECTS_DIR="$BATS_TEST_TMPDIR/claude-projects" \
  CLAUDE_SEARCH_PI_SESSIONS_DIR="$BATS_TEST_TMPDIR/pi-sessions" \
    run agent_search_main fivetran 30
  [ "$status" -eq 0 ]
  [[ "$output" == *"reading pi transcripts failed"* ]] || false
  [[ "$output" == *"fivetran from claude"* ]]
}

@test "run: a malformed pi transcript is skipped, not fatal" {
  local cdir="$BATS_TEST_TMPDIR/claude-projects/-Users-tester-dev-widget"
  local pdir="$BATS_TEST_TMPDIR/pi-sessions/--Users-tester-dev-gadget--"
  mkdir -p "$cdir" "$pdir"
  cat > "$cdir/session.jsonl" <<-EOF
	{"type":"user","timestamp":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","sessionId":"abc123","cwd":"/Users/tester/dev/widget","message":{"content":"fivetran from claude"}}
	EOF
  printf 'this is not json at all\n' > "$pdir/2026-01-01_abc.jsonl"

  CLAUDE_SEARCH_PROJECTS_DIR="$BATS_TEST_TMPDIR/claude-projects" \
  CLAUDE_SEARCH_PI_SESSIONS_DIR="$BATS_TEST_TMPDIR/pi-sessions" \
    run "$CS" fivetran 30
  [ "$status" -eq 0 ]
  [[ "$output" == *"fivetran from claude"* ]]
}

@test "run: a non-numeric day window is rejected, not fed to the query" {
  CLAUDE_SEARCH_PROJECTS_DIR="$BATS_TEST_TMPDIR/claude-projects" \
  CLAUDE_SEARCH_PI_SESSIONS_DIR="$BATS_TEST_TMPDIR/pi-sessions" \
    run "$CS" fivetran abc
  [ "$status" -eq 2 ]
  [[ "$output" == *"days must be a whole number"* ]]
}

@test "run: --help and no args print usage, exit 0" {
  run "$CS" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: agent-search"* ]] || false
  run "$CS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: agent-search"* ]]
}
