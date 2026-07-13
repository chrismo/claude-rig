#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

# Test suite for bin/claude-pod.
#
# claude-pod reads ~/.claude/projects/<encoded-path>/*.jsonl files and renders
# session conversations. Tests run with CLAUDE_PROJECTS_DIR and
# CLAUDE_SESSIONS_META_DIR redirected into BATS_TEST_TMPDIR so they don't
# touch the real ~/.claude.
#
# Requires `super` (SuperDB) — same as the script itself.

POD="$BATS_TEST_DIRNAME/claude-pod"

setup() {
  export CLAUDE_PROJECTS_DIR="$BATS_TEST_TMPDIR/.claude/projects"
  export CLAUDE_SESSIONS_META_DIR="$BATS_TEST_TMPDIR/.claude/sessions"
  mkdir -p "$CLAUDE_PROJECTS_DIR" "$CLAUDE_SESSIONS_META_DIR"
  # Many tests want a clean baseline; --peers behavior depends on this.
  unset CLAUDE_CODE_SESSION_ID
  # The gitignore assertions ask "is this path ignored?", and the developer's own
  # global excludes file can answer yes — the recommended `.*console*.log` line
  # lives there. Point git at an empty config so the tests judge only what the
  # test repo itself declares.
  export GIT_CONFIG_GLOBAL="$BATS_TEST_TMPDIR/gitconfig"
  export GIT_CONFIG_SYSTEM=/dev/null
  : > "$GIT_CONFIG_GLOBAL"
}

# ── Fixture helpers ────────────────────────────────────────────────────────────

# encode_path /tmp/foo/bar → -tmp-foo-bar (mirrors claude-pod's encode_path).
encode_path() {
  local p="${1#/}"
  echo "-${p//\//-}"
}

# make_worktree NAME
#   Creates BATS_TEST_TMPDIR/NAME plus its encoded ~/.claude/projects/ dir.
#   Echoes the canonical worktree path.
make_worktree() {
  local name="$1"
  local wt="$BATS_TEST_TMPDIR/$name"
  mkdir -p "$wt"
  local canonical
  canonical=$(cd "$wt" && pwd)
  mkdir -p "$CLAUDE_PROJECTS_DIR/$(encode_path "$canonical")"
  echo "$canonical"
}

# session_dir_for WORKTREE → encoded projects subdir
session_dir_for() {
  echo "$CLAUDE_PROJECTS_DIR/$(encode_path "$(cd "$1" && pwd)")"
}

# write_session WORKTREE SID
#   Writes a minimal user+assistant jsonl, plus one meta record so the file's
#   inferred schema includes `isMeta` and `subtype` — the script's filters
#   reference those fields, and super errors at schema-resolution time if no
#   record in the file declares them. Real Claude sessions always have these.
write_session() {
  local wt="$1" sid="$2"
  local dir
  dir=$(session_dir_for "$wt")
  local file="$dir/$sid.jsonl"
  cat > "$file" <<EOF
{"type":"system","sessionId":"$sid","subtype":"info","timestamp":"2026-05-17T00:00:00Z","content":"meta-record-for-schema-inference","isMeta":true}
{"type":"user","sessionId":"$sid","timestamp":"2026-05-17T00:00:01Z","message":{"content":"hello"}}
{"type":"assistant","sessionId":"$sid","timestamp":"2026-05-17T00:00:02Z","message":{"content":[{"type":"text","text":"hi"}]}}
EOF
  echo "$file"
}

# rename_event WORKTREE SID NAME
#   Appends a real /rename system event.
rename_event() {
  local wt="$1" sid="$2" name="$3"
  local file
  file="$(session_dir_for "$wt")/$sid.jsonl"
  cat >> "$file" <<EOF
{"type":"system","sessionId":"$sid","subtype":"local_command","timestamp":"2026-05-17T00:00:02Z","content":"<local-command-stdout>Session renamed to: $name</local-command-stdout>"}
EOF
}

# tool_result_with_rename_text WORKTREE SID
#   Appends a user message whose content quotes the rename pattern — exercises
#   the name_from_jsonl false-positive guard.
tool_result_with_rename_text() {
  local wt="$1" sid="$2"
  local file
  file="$(session_dir_for "$wt")/$sid.jsonl"
  cat >> "$file" <<EOF
{"type":"user","sessionId":"$sid","timestamp":"2026-05-17T00:00:03Z","message":{"content":"comment: # Session renamed to: NAME — survives after exit"}}
EOF
}

# live_session SID NAME PID PROJECTPATH
#   Writes a fake ~/.claude/sessions/<pid>.json metadata file.
live_session() {
  local sid="$1" name="$2" pid="$3" path="$4"
  cat > "$CLAUDE_SESSIONS_META_DIR/$pid.json" <<EOF
{"sessionId":"$sid","name":"$name","pid":$pid,"projectPath":"$path"}
EOF
}

# write_console WORKTREE [NAME]
#   Writes a fake `script` typescript: header line, ANSI-colored output, an OSC
#   title-set escape, a carriage-return progress redraw, and a blank-line run.
#   Echoes the log path.
write_console() {
  local wt="$1" name="${2:-.main-console.log}"
  local file="$wt/$name"
  printf 'Script started on Sun Jul 12 09:00:00 2026\n' > "$file"
  printf '\033]0;zsh\007\033[32mPASS\033[0m first-test\n' >> "$file"
  printf 'progress 10%%\rprogress 50%%\rprogress 100%%\n' >> "$file"
  printf '\n\n\n' >> "$file"
  printf 'boom: NoMethodError in widget.rb\n' >> "$file"
  echo "$file"
}

# ── Usage / exit codes ─────────────────────────────────────────────────────────

@test "no args → prints usage, exit 0" {
  run "$POD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: claude-pod"* ]]
}

@test "--help → prints usage, exit 0" {
  run "$POD" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: claude-pod"* ]]
}

@test "unknown flag → exit 2" {
  run "$POD" --bogus
  [ "$status" -eq 2 ]
}

@test "--turns with non-number → exit 2" {
  run "$POD" --turns abc /tmp
  [ "$status" -eq 2 ]
}

@test "--turns with --all → exit 2" {
  wt=$(make_worktree wt1)
  run "$POD" --all --turns 5 "$wt"
  [ "$status" -eq 2 ]
}

# ── Path resolution ────────────────────────────────────────────────────────────

@test "bad path → exit 1" {
  run "$POD" /does/not/exist
  [ "$status" -eq 1 ]
}

@test "valid worktree, --all matches nothing in window → exit 0, message on stderr" {
  wt=$(make_worktree wt1)
  file=$(write_session "$wt" "11111111-2222-3333-4444-555555555555")
  # Age the file so --since 1s excludes it (mtime-based filter).
  touch -t 202401010000 "$file"
  run --separate-stderr "$POD" --all --since 1s "$wt"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"no matching sessions"* ]]
}

@test "valid worktree, render mode no match → exit 0" {
  wt=$(make_worktree wt1)
  file=$(write_session "$wt" "11111111-2222-3333-4444-555555555555")
  touch -t 202401010000 "$file"
  run "$POD" --since 1s "$wt"
  [ "$status" -eq 0 ]
}

# ── --all listing ──────────────────────────────────────────────────────────────

@test "--all with sessions → table header + row" {
  wt=$(make_worktree wt1)
  write_session "$wt" "11111111-2222-3333-4444-555555555555" >/dev/null
  run "$POD" --all "$wt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"modified"* ]]
  [[ "$output" == *"11111111"* ]]
}

# ── --peers semantics ──────────────────────────────────────────────────────────

@test "--peers without CLAUDE_CODE_SESSION_ID → exit 2" {
  wt=$(make_worktree wt1)
  run "$POD" --peers "$wt"
  [ "$status" -eq 2 ]
}

@test "--peers excludes \$CLAUDE_CODE_SESSION_ID, includes others" {
  wt=$(make_worktree wt1)
  write_session "$wt" "11111111-2222-3333-4444-555555555555" >/dev/null
  write_session "$wt" "22222222-3333-4444-5555-666666666666" >/dev/null
  export CLAUDE_CODE_SESSION_ID="11111111-2222-3333-4444-555555555555"
  run "$POD" --peers "$wt"
  [ "$status" -eq 0 ]
  [[ "$output" != *"11111111-2222"* ]]
  [[ "$output" == *"22222222-3333"* ]]
}

# ── --session resolution ───────────────────────────────────────────────────────

@test "--session bogus-name → exit 1" {
  run "$POD" --session not-a-session
  [ "$status" -eq 1 ]
}

@test "--session by UUID renders" {
  wt=$(make_worktree wt1)
  sid="aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
  write_session "$wt" "$sid" >/dev/null
  run "$POD" --session "$sid" --turns 0 "$wt"
  [ "$status" -eq 0 ]
}

@test "--session by name from live sessions metadata" {
  wt=$(make_worktree wt1)
  sid="aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
  write_session "$wt" "$sid" >/dev/null
  live_session "$sid" "merlin" 99999 "$wt"
  run "$POD" --session merlin --turns 0
  [ "$status" -eq 0 ]
}

@test "--session by name resolves cross-worktree from disk rename event" {
  wt=$(make_worktree wt1)
  wt2=$(make_worktree wt2)
  sid="ccccdddd-1111-2222-3333-444444444444"
  write_session "$wt2" "$sid" >/dev/null
  rename_event "$wt2" "$sid" "lancelot"
  # Invoke from a DIFFERENT worktree — proves the disk map is global.
  cd "$wt"
  run "$POD" --session lancelot --turns 0
  [ "$status" -eq 0 ]
}

# ── Name extraction false-positive guard ───────────────────────────────────────

@test "name column empty when session has no real rename event (tool-result text doesn't false-match)" {
  wt=$(make_worktree wt1)
  sid="ffff0000-1111-2222-3333-444444444444"
  write_session "$wt" "$sid" >/dev/null
  tool_result_with_rename_text "$wt" "$sid"
  run "$POD" --all "$wt"
  [ "$status" -eq 0 ]
  # Garbage indicators that would appear under the old loose grep.
  [[ "$output" != *"survives after"* ]]
  [[ "$output" != *"NAME"* ]]
}

@test "real rename event resolves to its name in the listing" {
  wt=$(make_worktree wt1)
  sid="aaaaaaaa-1234-1234-1234-aaaaaaaaaaaa"
  write_session "$wt" "$sid" >/dev/null
  rename_event "$wt" "$sid" "galahad"
  run "$POD" --all "$wt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"galahad"* ]]
}

# ── SuperDB content-coercion quirk regression ──────────────────────────────────

@test "renders session whose only turn has string-typed message.content (SuperDB switch+unnest quirk)" {
  wt=$(make_worktree wt1)
  sid="bbbbcccc-1111-2222-3333-444444444444"
  local dir
  dir=$(session_dir_for "$wt")
  # Include the schema-seeding meta record (see write_session helper notes).
  cat > "$dir/$sid.jsonl" <<EOF
{"type":"system","sessionId":"$sid","subtype":"info","timestamp":"2026-05-17T00:00:00Z","content":"meta","isMeta":true}
{"type":"user","sessionId":"$sid","timestamp":"2026-05-17T00:00:01Z","message":{"content":"hello-string-only"}}
EOF
  run "$POD" --session "$sid" "$wt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"hello-string-only"* ]]
}

# ── bash 3.2 + set -u: empty EXCLUDES doesn't crash ────────────────────────────

@test "/bin/bash (3.2): --all with no --exclude doesn't trigger 'unbound variable' on EXCLUDES" {
  wt=$(make_worktree wt1)
  write_session "$wt" "aaaa1111-bbbb-cccc-dddd-eeeeeeeeeeee" >/dev/null
  # Force macOS's bash 3.2 so the EXCLUDES[@] regression is actually exercised.
  # On other systems /bin/bash may be a newer build — that's fine; this just
  # additionally validates portability.
  run /bin/bash "$POD" --all "$wt"
  [ "$status" -eq 0 ]
  [[ "$output" != *"unbound variable"* ]]
  [[ "$output" != *"EXCLUDES"* ]]
}

# ── --console: the human's terminal as a peer stream ───────────────────────────

@test "--console with no recording → exit 1, points at --record" {
  wt=$(make_worktree wt1)
  run --separate-stderr "$POD" --console "$wt"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"no console recording"* ]]
  [[ "$stderr" == *"--record"* ]]
}

@test "--console renders the recording with ANSI escapes stripped" {
  wt=$(make_worktree wt1)
  write_console "$wt" >/dev/null
  run "$POD" --console "$wt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS first-test"* ]]
  [[ "$output" == *"boom: NoMethodError"* ]]
  # No raw escape bytes survive.
  [[ "$output" != *$'\033'* ]]
}

@test "--console drops the 'Script started on' header" {
  wt=$(make_worktree wt1)
  write_console "$wt" >/dev/null
  run "$POD" --console "$wt"
  [ "$status" -eq 0 ]
  [[ "$output" != *"Script started on"* ]]
}

@test "--console collapses carriage-return redraws to the final segment" {
  wt=$(make_worktree wt1)
  write_console "$wt" >/dev/null
  run "$POD" --console "$wt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"progress 100%"* ]]
  [[ "$output" != *"progress 10%"* ]]
  [[ "$output" != *"progress 50%"* ]]
}

@test "--console squeezes blank-line runs" {
  wt=$(make_worktree wt1)
  write_console "$wt" >/dev/null
  run "$POD" --console "$wt"
  [ "$status" -eq 0 ]
  [[ "$output" != *$'\n\n\n'* ]]
}

@test "--console --tail N renders only the last N lines" {
  wt=$(make_worktree wt1)
  write_console "$wt" >/dev/null
  run "$POD" --console --tail 1 "$wt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"boom: NoMethodError"* ]]
  [[ "$output" != *"PASS first-test"* ]]
}

@test "--tail with non-number → exit 2" {
  wt=$(make_worktree wt1)
  run "$POD" --console --tail abc "$wt"
  [ "$status" -eq 2 ]
}

@test "--turns with --console → exit 2 (session render flag)" {
  wt=$(make_worktree wt1)
  write_console "$wt" >/dev/null
  run "$POD" --console --turns 5 "$wt"
  [ "$status" -eq 2 ]
}

@test "\$CLAUDE_CONSOLE_LOG overrides discovery" {
  wt=$(make_worktree wt1)
  write_console "$wt" >/dev/null
  printf 'from-the-override\n' > "$wt/elsewhere.log"
  export CLAUDE_CONSOLE_LOG="$wt/elsewhere.log"
  run "$POD" --console "$wt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"from-the-override"* ]]
  [[ "$output" != *"boom: NoMethodError"* ]]
}

@test "--console -f with several panes → exit 2 (no way to attribute an interleaved stream)" {
  wt=$(make_worktree wt1)
  two_consoles "$wt"
  run "$POD" --console -f "$wt"
  [ "$status" -eq 2 ]
}

# ── Multiple consoles: one pane per concern ────────────────────────────────────

# two_consoles WORKTREE
#   A server pane (older) and a tests pane (newer) — the everyday shape.
two_consoles() {
  local wt="$1"
  printf 'listening on :3000\n' > "$wt/.server-console.log"
  touch -t 202601010000 "$wt/.server-console.log"
  printf '3 failures, 0 errors\n' > "$wt/.tests-console.log"
}

@test "--console-list lists every recording by tag" {
  wt=$(make_worktree wt1)
  two_consoles "$wt"
  run "$POD" --console-list "$wt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"server"* ]]
  [[ "$output" == *"tests"* ]]
}

@test "--console-list with no recordings → exit 0, message on stderr" {
  wt=$(make_worktree wt1)
  run --separate-stderr "$POD" --console-list "$wt"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"no console recording"* ]]
}

@test "--console reads every pane, each under a heading naming it" {
  wt=$(make_worktree wt1)
  two_consoles "$wt"
  run "$POD" --console "$wt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"listening on :3000"* ]]
  [[ "$output" == *"3 failures"* ]]
  [[ "$output" == *"server"* ]]
  [[ "$output" == *"tests"* ]]
}

@test "--console orders panes oldest-written first, so the freshest reads last" {
  wt=$(make_worktree wt1)
  two_consoles "$wt"
  run "$POD" --console "$wt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"listening on :3000"*"3 failures"* ]]
}

@test "--console --tag narrows to one pane" {
  wt=$(make_worktree wt1)
  two_consoles "$wt"
  run "$POD" --console --tag server "$wt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"listening on :3000"* ]]
  [[ "$output" != *"3 failures"* ]]
}

@test "--console names the pane even when there's only one" {
  wt=$(make_worktree wt1)
  write_console "$wt" >/dev/null
  run "$POD" --console "$wt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"main"* ]]
  [[ "$output" == *"boom: NoMethodError"* ]]
}

@test "a legacy .my-console.log is still discovered, tagged 'my'" {
  wt=$(make_worktree wt1)
  write_console "$wt" .my-console.log >/dev/null
  run "$POD" --console "$wt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"my"* ]]
  [[ "$output" == *"boom: NoMethodError"* ]]
}

@test "--console --tag for an unknown tag → exit 1, lists what does exist" {
  wt=$(make_worktree wt1)
  two_consoles "$wt"
  run --separate-stderr "$POD" --console --tag nope "$wt"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"nope"* ]]
  [[ "$stderr" == *"server"* ]]
  [[ "$stderr" == *"tests"* ]]
}

@test "--tail bounds each pane independently, not the whole output" {
  wt=$(make_worktree wt1)
  printf 'server-old\nlistening on :3000\n' > "$wt/.server-console.log"
  touch -t 202601010000 "$wt/.server-console.log"
  printf 'tests-old\n3 failures, 0 errors\n' > "$wt/.tests-console.log"
  run "$POD" --console --tail 1 "$wt"
  [ "$status" -eq 0 ]
  # Last line of BOTH panes survives; the earlier line of each is dropped.
  [[ "$output" == *"listening on :3000"* ]]
  [[ "$output" == *"3 failures"* ]]
  [[ "$output" != *"server-old"* ]]
  [[ "$output" != *"tests-old"* ]]
}

@test "--tag outside --console/--record → exit 2" {
  wt=$(make_worktree wt1)
  run "$POD" --all --tag tests "$wt"
  [ "$status" -eq 2 ]
}

# ── Staleness: a log left behind looks exactly like a log being written ────────

@test "--console-list marks a recording nobody is holding open as ended" {
  wt=$(make_worktree wt1)
  two_consoles "$wt"
  run "$POD" --console-list "$wt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ended"* ]]
  [[ "$output" != *"live"* ]]
}

@test "--console-list reports how long ago each pane was last written" {
  wt=$(make_worktree wt1)
  printf 'ancient\n' > "$wt/.server-console.log"
  touch -t 202601010000 "$wt/.server-console.log"
  run "$POD" --console-list "$wt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ago"* ]]
  # Aged well over a year — must read in days, not minutes.
  [[ "$output" == *"d ago"* ]]
}

@test "--console-list marks a pane a live script process holds open as live" {
  wt=$(make_worktree wt1)
  cd "$wt"
  # A genuine script(1) recording, kept open. python gives it the tty it needs.
  python3 -c "import pty; pty.spawn(['script','-F','-q','.main-console.log','bash','-c','echo hi; sleep 20'])" \
    >/dev/null 2>&1 &
  local pid=$!
  # Wait for script to actually create and hold the file open.
  local i
  for i in 1 2 3 4 5 6 7 8 9 10; do
    [[ -s "$wt/.main-console.log" ]] && break
    sleep 0.3
  done
  run "$POD" --console-list "$wt"
  kill "$pid" 2>/dev/null || true
  [ "$status" -eq 0 ]
  [[ "$output" == *"live"* ]]
}

@test "--console heading says whether the pane is still live and how old it is" {
  wt=$(make_worktree wt1)
  printf 'ancient\n' > "$wt/.server-console.log"
  touch -t 202601010000 "$wt/.server-console.log"
  run "$POD" --console "$wt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ended"* ]]
  [[ "$output" == *"ago"* ]]
  [[ "$output" == *"ancient"* ]]
}

# ── --record: hand the human a command to start recording ──────────────────────

@test "--record prints a script(1) command for the default log path" {
  wt=$(make_worktree wt1)
  run "$POD" --record "$wt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"script -F -q"* ]]
  [[ "$output" == *".main-console.log"* ]]
}

@test "--record warns when the log path isn't gitignored" {
  wt=$(make_worktree wt1)
  git -C "$wt" init -q
  run "$POD" --record "$wt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"gitignore"* ]]
}

@test "--record stays quiet about gitignore when the path is already ignored" {
  wt=$(make_worktree wt1)
  git -C "$wt" init -q
  printf '.*console*.log\n' > "$wt/.gitignore"
  run "$POD" --record "$wt"
  [ "$status" -eq 0 ]
  [[ "$output" != *"gitignore"* ]]
}

@test "--record notes a recording is already in progress" {
  wt=$(make_worktree wt1)
  write_console "$wt" >/dev/null
  run "$POD" --record "$wt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already"* ]]
}

@test "--record --tag names a per-pane log" {
  wt=$(make_worktree wt1)
  run "$POD" --record --tag tests "$wt"
  [ "$status" -eq 0 ]
  [[ "$output" == *".tests-console.log"* ]]
}

@test "--record --tag doesn't warn about an unrelated pane's existing log" {
  wt=$(make_worktree wt1)
  printf 'listening on :3000\n' > "$wt/.server-console.log"
  run "$POD" --record --tag tests "$wt"
  [ "$status" -eq 0 ]
  [[ "$output" != *"already"* ]]
}
