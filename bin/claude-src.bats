#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

# Test suite for bin/claude-src.
#
# The real input is a ~265MB bun-compiled binary, so every test here builds a
# tiny stand-in: a file with one block of binary junk and one block of readable
# JS. CLAUDE_SRC_BLOCK_BYTES shrinks the scan block to match.

SRC="$BATS_TEST_DIRNAME/claude-src"

setup() {
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/claude-src-test.XXXXXX")"
  export CLAUDE_SRC_CACHE_DIR="$TEST_DIR/cache"
  export CLAUDE_SRC_BLOCK_BYTES=64
  source "$SRC"
}

teardown() {
  [[ -n "$TEST_DIR" && -d "$TEST_DIR" ]] && rm -rf "$TEST_DIR"
}

# junk_block — 64 bytes of non-printable noise, like the bytecode regions.
junk_block() {
  head -c 64 /dev/zero | tr '\0' '\001'
}

# text_block <text> — <text> padded with spaces to exactly 64 bytes.
text_block() {
  printf '%s' "$1"
  head -c $((64 - ${#1})) /dev/zero | tr '\0' ' '
}

# fake_binary <path> — junk, then JS, then junk.
fake_binary() {
  {
    junk_block
    text_block 'function jvS(){let e=ee.XDG_RUNTIME_DIR;return e}'
    junk_block
  } > "$1"
}

# ── extract_bundle ────────────────────────────────────────────────────────────

@test "extract_bundle keeps readable blocks and drops binary ones" {
  fake_binary "$TEST_DIR/2.1.224"

  run extract_bundle "$TEST_DIR/2.1.224"
  [ "$status" -eq 0 ]
  [[ "$output" == *"XDG_RUNTIME_DIR"* ]]
  [[ "$output" != *$'\001'* ]]
}

@test "extract_bundle splits on semicolons so greps stay line-sized" {
  fake_binary "$TEST_DIR/2.1.224"

  run extract_bundle "$TEST_DIR/2.1.224"
  [ "$status" -eq 0 ]

  # `let e=...;return e` was one statement pair; it must land on two lines.
  local lines
  lines=$(printf '%s\n' "$output" | grep -c .)
  [ "$lines" -ge 2 ]
}

@test "extract_bundle emits nothing for an all-binary file" {
  { junk_block; junk_block; } > "$TEST_DIR/2.1.224"

  run extract_bundle "$TEST_DIR/2.1.224"
  [ "$status" -eq 0 ]
  [[ -z "$output" ]]
}

# ── cache ─────────────────────────────────────────────────────────────────────

@test "cache is keyed to the binary's version filename" {
  run cache_path_for "/somewhere/versions/2.1.224"
  [ "$status" -eq 0 ]
  [[ "$output" == "$CLAUDE_SRC_CACHE_DIR/2.1.224.lines" ]]
}

@test "ensure_extracted extracts once and reuses the cache" {
  fake_binary "$TEST_DIR/2.1.224"

  # --separate-stderr: the "extracting…" progress note goes to stderr and is
  # not part of the answer.
  run --separate-stderr ensure_extracted "$TEST_DIR/2.1.224"
  [ "$status" -eq 0 ]
  [[ "$output" == "$CLAUDE_SRC_CACHE_DIR/2.1.224.lines" ]]
  [[ -f "$CLAUDE_SRC_CACHE_DIR/2.1.224.lines" ]]

  # Second call must not re-read the binary — prove it by making the binary
  # unreadable and asking again.
  chmod 000 "$TEST_DIR/2.1.224"
  run ensure_extracted "$TEST_DIR/2.1.224"
  [ "$status" -eq 0 ]
  chmod 644 "$TEST_DIR/2.1.224"
}

@test "ensure_extracted re-extracts when the binary is newer than the cache" {
  fake_binary "$TEST_DIR/2.1.224"
  ensure_extracted "$TEST_DIR/2.1.224" > /dev/null

  # A new build lands at the same path (an in-place upgrade).
  {
    junk_block
    text_block 'function jvS(){return "REBUILT"}'
    junk_block
  } > "$TEST_DIR/2.1.224"
  touch "$TEST_DIR/2.1.224"

  ensure_extracted "$TEST_DIR/2.1.224" > /dev/null
  run cat "$CLAUDE_SRC_CACHE_DIR/2.1.224.lines"
  [[ "$output" == *"REBUILT"* ]]
  [[ "$output" != *"XDG_RUNTIME_DIR"* ]]
}

# ── resolve_claude_binary ─────────────────────────────────────────────────────

@test "resolve_claude_binary prefers an explicit CLAUDE_SRC_BINARY" {
  export CLAUDE_SRC_BINARY="$TEST_DIR/pinned"
  : > "$CLAUDE_SRC_BINARY"

  run resolve_claude_binary
  [ "$status" -eq 0 ]
  [[ "$output" == "$TEST_DIR/pinned" ]]
}

@test "resolve_claude_binary follows the launcher symlink to the version file" {
  mkdir -p "$TEST_DIR/versions"
  # Must be executable or `command -v` walks past it to the real claude.
  printf '#!/bin/sh\n' > "$TEST_DIR/versions/2.1.224"
  chmod +x "$TEST_DIR/versions/2.1.224"
  ln -s "$TEST_DIR/versions/2.1.224" "$TEST_DIR/claude"

  unset CLAUDE_SRC_BINARY CLAUDE_CODE_EXECPATH
  export PATH="$TEST_DIR:$PATH"

  run resolve_claude_binary
  [ "$status" -eq 0 ]
  [[ "$output" == "$TEST_DIR/versions/2.1.224" ]]
}

# ── search ────────────────────────────────────────────────────────────────────

@test "cmd_search prints matching lines with surrounding context" {
  fake_binary "$TEST_DIR/2.1.224"
  export CLAUDE_SRC_BINARY="$TEST_DIR/2.1.224"

  run cmd_search "XDG_RUNTIME_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"XDG_RUNTIME_DIR"* ]]
  # Context lines carry the neighbouring statement.
  [[ "$output" == *"return e"* ]]
}

@test "cmd_search reports a miss without failing the shell" {
  fake_binary "$TEST_DIR/2.1.224"
  export CLAUDE_SRC_BINARY="$TEST_DIR/2.1.224"

  run cmd_search "no-such-identifier-anywhere"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no match"* ]]
}

@test "cmd_search truncates very long lines" {
  {
    junk_block
    # One 64-byte statement with no semicolon — a single long line.
    text_block 'var LONG="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"'
    junk_block
  } > "$TEST_DIR/2.1.224"
  export CLAUDE_SRC_BINARY="$TEST_DIR/2.1.224"

  run --separate-stderr cmd_search "LONG" 0 20
  [ "$status" -eq 0 ]
  local longest
  longest=$(printf '%s\n' "$output" | awk '{ if (length($0)>m) m=length($0) } END { print m }')
  [ "$longest" -le 20 ]
}
