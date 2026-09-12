#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

# Test suite for bin/claude-tabs.
#
# Most of claude-tabs is integration-level (lsof + AppleScript + Ghostty),
# but `build_restore_applescript` is a pure text generator — we can lock
# in its shape so future edits don't silently regress focus handling.

TABS="$BATS_TEST_DIRNAME/claude-tabs"

setup() {
  # Source the script so we can call its functions directly.
  # The script's guard at the bottom skips main when sourced.
  source "$TABS"
}

# ── REGISTRY_TO_TSV ───────────────────────────────────────────────────────────

# registry_tsv <ndjson> → the cwd<TAB>sessionId lines the filter keeps.
registry_tsv() {
  printf '%s\n' "$1" | super -i json -f line -c "$REGISTRY_TO_TSV" -
}

@test "registry filter keeps an entry whose records never declare 'kind'" {
  run registry_tsv '{"cwd":"/tmp/widget","sessionId":"abc123"}'
  [ "$status" -eq 0 ]
  [[ "$output" == *"/tmp/widget"* ]] || false
  [[ "$output" == *"abc123"* ]]
}

@test "registry filter drops non-interactive entries and keeps interactive ones" {
  run registry_tsv '{"kind":"sdk","cwd":"/tmp/bot","sessionId":"bot1"}
{"kind":"interactive","cwd":"/tmp/widget","sessionId":"abc123"}'
  [ "$status" -eq 0 ]
  [[ "$output" != *"/tmp/bot"* ]] || false
  [[ "$output" == *"/tmp/widget"* ]]
}

@test "registry filter drops entries missing cwd or sessionId" {
  run registry_tsv '{"kind":"interactive","sessionId":"nocwd"}
{"kind":"interactive","cwd":"/tmp/nosid"}
{"kind":"interactive","cwd":"/tmp/widget","sessionId":"abc123"}'
  [ "$status" -eq 0 ]
  [[ "$output" != *"nocwd"* ]] || false
  [[ "$output" != *"nosid"* ]] || false
  [[ "$output" == *"abc123"* ]]
}

@test "registry filter compiles against a file input with no 'kind' anywhere" {
  # super resolves field references at compile time when it can infer the
  # input schema up front — which it does for a file and not for a pipe. The
  # filter must not name a field the input never declares.
  local f="$BATS_TEST_TMPDIR/registry.json"
  printf '%s\n' '{"cwd":"/tmp/widget","sessionId":"abc123"}' > "$f"
  run super -i json -f line -c "$REGISTRY_TO_TSV" "$f"
  [ "$status" -eq 0 ]
  [[ "$output" == *"abc123"* ]]
}

# ── build_restore_applescript ─────────────────────────────────────────────────

@test "applescript targets specific terminals, not focus-routed keystrokes" {
  run build_restore_applescript "/tmp/cmd-dir" 3

  [ "$status" -eq 0 ]

  # The old, racy approach pasted via the clipboard and routed cmd+v
  # through System Events — which delivered to whatever tab happened to
  # be focused. The new approach must target terminals directly.
  [[ "$output" != *'keystroke "v"'* ]] || false
  [[ "$output" != *"pbcopy"* ]] || false

  # New approach uses Ghostty's scripting commands.
  [[ "$output" == *"input text"* ]] || false
  [[ "$output" == *"send key"* ]] || false
  [[ "$output" == *"to terminal"* ]]
}

@test "applescript creates new tabs via Ghostty's 'new tab' command" {
  run build_restore_applescript "/tmp/cmd-dir" 2

  [ "$status" -eq 0 ]

  # Old approach: keystroke "t" using command down (focus-dependent).
  [[ "$output" != *'keystroke "t"'* ]] || false

  # New approach: ask Ghostty to make a tab and hand us back the object.
  [[ "$output" == *"new tab"* ]]
}

@test "applescript creates a window when none exists (cold start)" {
  run build_restore_applescript "/tmp/cmd-dir" 3

  [ "$status" -eq 0 ]

  # On a cold start `tell application "Ghostty" to activate` does NOT open a
  # window — it can launch (or wake a backgrounded) Ghostty that has zero
  # windows. The script must explicitly create one via the scripting
  # dictionary's `new window` rather than waiting for activate to do it.
  [[ "$output" == *"new window"* ]] || false
  [[ "$output" == *"count of windows"* ]]
}

@test "applescript submits with the 'enter' key name, not 'return'" {
  run build_restore_applescript "/tmp/cmd-dir" 1

  [ "$status" -eq 0 ]

  # Ghostty's `send key` rejects "return" with "Unknown key name: return".
  # Its key names use "enter" (per the scripting dictionary's own example).
  [[ "$output" != *'send key "return"'* ]] || false
  [[ "$output" == *'send key "enter"'* ]]
}

@test "applescript embeds the command directory and session count" {
  run build_restore_applescript "/my/cmd/dir" 7

  [ "$status" -eq 0 ]
  [[ "$output" == *"/my/cmd/dir"* ]] || false
  # The count as the script actually carries it — a bare "7" matches any stray
  # digit in the generated AppleScript.
  [[ "$output" == *"set sessionCount to 7"* ]]
}

# ── history helpers ───────────────────────────────────────────────────────────

@test "history_label formats the timestamp from a snapshot filename" {
  run history_label "tab-state-20260501-083328.json"
  [ "$status" -eq 0 ]
  [[ "$output" == "2026-05-01 08:33:28" ]]
}

@test "history_label accepts a full path" {
  run history_label "/x/y/tab-history/tab-state-20251231-235959.json"
  [ "$status" -eq 0 ]
  [[ "$output" == "2025-12-31 23:59:59" ]]
}

@test "history_rows lists snapshots newest-first with path<TAB>label" {
  dir="$(mktemp -d "${TMPDIR:-/tmp}/tab-hist.XXXXXX")"
  : > "$dir/tab-state-20260101-010101.json"
  : > "$dir/tab-state-20260102-020202.json"
  touch -t 202601010101.01 "$dir/tab-state-20260101-010101.json"
  touch -t 202601020202.02 "$dir/tab-state-20260102-020202.json"

  run history_rows "$dir"
  [ "$status" -eq 0 ]

  first="$(echo "$output" | sed -n 1p)"
  second="$(echo "$output" | sed -n 2p)"
  [[ "$first"  == *"tab-state-20260102-020202.json"$'\t'"2026-01-02 02:02:02" ]] || false
  [[ "$second" == *"tab-state-20260101-010101.json"$'\t'"2026-01-01 01:01:01" ]] || false

  rm -rf "$dir"
}

@test "history_rows emits nothing for an empty/missing dir" {
  dir="$(mktemp -d "${TMPDIR:-/tmp}/tab-hist-empty.XXXXXX")"
  run history_rows "$dir"
  [ "$status" -eq 0 ]
  [[ -z "$output" ]] || false
  rm -rf "$dir"
}
