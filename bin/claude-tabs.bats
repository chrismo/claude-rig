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

@test "applescript embeds the command directory and session count" {
  run build_restore_applescript "/my/cmd/dir" 7

  [ "$status" -eq 0 ]
  [[ "$output" == *"/my/cmd/dir"* ]]
  [[ "$output" == *"7"* ]]
}
