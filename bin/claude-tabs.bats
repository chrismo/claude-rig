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

# ── build_restore_applescript ─────────────────────────────────────────────────

@test "applescript targets specific terminals, not focus-routed keystrokes" {
  run build_restore_applescript "/tmp/cmd-dir" 3

  [ "$status" -eq 0 ]

  # The old, racy approach pasted via the clipboard and routed cmd+v
  # through System Events — which delivered to whatever tab happened to
  # be focused. The new approach must target terminals directly.
  [[ "$output" != *'keystroke "v"'* ]]
  [[ "$output" != *"pbcopy"* ]]

  # New approach uses Ghostty's scripting commands.
  [[ "$output" == *"input text"* ]]
  [[ "$output" == *"send key"* ]]
  [[ "$output" == *"to terminal"* ]] || [[ "$output" == *"to term"* ]]
}

@test "applescript creates new tabs via Ghostty's 'new tab' command" {
  run build_restore_applescript "/tmp/cmd-dir" 2

  [ "$status" -eq 0 ]

  # Old approach: keystroke "t" using command down (focus-dependent).
  [[ "$output" != *'keystroke "t"'* ]]

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
  [[ "$output" == *"new window"* ]]
  [[ "$output" == *"count of windows"* ]]
}

@test "applescript submits with the 'enter' key name, not 'return'" {
  run build_restore_applescript "/tmp/cmd-dir" 1

  [ "$status" -eq 0 ]

  # Ghostty's `send key` rejects "return" with "Unknown key name: return".
  # Its key names use "enter" (per the scripting dictionary's own example).
  [[ "$output" != *'send key "return"'* ]]
  [[ "$output" == *'send key "enter"'* ]]
}

@test "applescript embeds the command directory and session count" {
  run build_restore_applescript "/my/cmd/dir" 7

  [ "$status" -eq 0 ]
  [[ "$output" == *"/my/cmd/dir"* ]]
  [[ "$output" == *"7"* ]]
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
  [[ "$first"  == *"tab-state-20260102-020202.json"$'\t'"2026-01-02 02:02:02" ]]
  [[ "$second" == *"tab-state-20260101-010101.json"$'\t'"2026-01-01 01:01:01" ]]

  rm -rf "$dir"
}

@test "history_rows emits nothing for an empty/missing dir" {
  dir="$(mktemp -d "${TMPDIR:-/tmp}/tab-hist-empty.XXXXXX")"
  run history_rows "$dir"
  [ "$status" -eq 0 ]
  [[ -z "$output" ]]
  rm -rf "$dir"
}
