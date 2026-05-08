#!/usr/bin/env bats

# Test suite for the 1.50-model statusline plugin.
#
# Renders model display name and a 3-bar effort-level indicator. Effort is
# resolved in priority order:
#   1. effort.level             — canonical statusline JSON field (CC 2.1.121+)
#   2. model.reasoning_effort   — older speculative key, kept as a fallback
#   3. $CLAUDE_CODE_EFFORT_LEVEL
#   4. effortLevel in ~/.claude/settings.json
#   5. medium (default)

PLUGIN="$BATS_TEST_DIRNAME/plugins.d/1.50-model"

LIT=$'\033[2;32m'      # muted green (lit bar)
DIM=$'\033[38;5;238m'  # dark grey (dim bar)
RST=$'\033[2;37m'      # color reset

LOW="${LIT}▌${DIM}▌▌${RST}"
MED="${LIT}▌▌${DIM}▌${RST}"
HIGH="${LIT}▌▌▌${RST}"

setup() {
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/model-test.XXXXXX")"
  INPUT="$TEST_DIR/input.json"
  export CLAUDE_STATUS_INPUT="$INPUT"
  # Isolate from real settings.json so the fallback chain is deterministic.
  export HOME="$TEST_DIR"
  unset CLAUDE_CODE_EFFORT_LEVEL
}

teardown() {
  rm -rf "$TEST_DIR"
}

write_input() {
  printf '%s' "$1" > "$INPUT"
}

# ── effort.level (canonical, 2.1.121+) ────────────────────────────────────────

@test "effort.level: low renders 1 lit + 2 dim bars" {
  write_input '{"model":{"display_name":"Sonnet 4.6"},"effort":{"level":"low"}}'
  run bash "$PLUGIN"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Sonnet 4.6 ${LOW}"* ]]
}

@test "effort.level: medium renders 2 lit + 1 dim bar" {
  write_input '{"model":{"display_name":"Sonnet 4.6"},"effort":{"level":"medium"}}'
  run bash "$PLUGIN"
  [[ "$output" == *"Sonnet 4.6 ${MED}"* ]]
}

@test "effort.level: high renders 3 lit bars" {
  write_input '{"model":{"display_name":"Opus 4.7"},"effort":{"level":"high"}}'
  run bash "$PLUGIN"
  [[ "$output" == *"Opus 4.7 ${HIGH}"* ]]
}

@test "effort.level wins over model.reasoning_effort" {
  write_input '{"model":{"display_name":"Sonnet 4.6","reasoning_effort":"low"},"effort":{"level":"high"}}'
  run bash "$PLUGIN"
  [[ "$output" == *"Sonnet 4.6 ${HIGH}"* ]]
}

@test "effort.level wins over CLAUDE_CODE_EFFORT_LEVEL env var" {
  export CLAUDE_CODE_EFFORT_LEVEL="low"
  write_input '{"model":{"display_name":"Sonnet 4.6"},"effort":{"level":"high"}}'
  run bash "$PLUGIN"
  [[ "$output" == *"Sonnet 4.6 ${HIGH}"* ]]
}

# ── Fallback chain ────────────────────────────────────────────────────────────

@test "falls back to model.reasoning_effort when effort.level absent" {
  write_input '{"model":{"display_name":"Sonnet 4.6","reasoning_effort":"high"}}'
  run bash "$PLUGIN"
  [[ "$output" == *"Sonnet 4.6 ${HIGH}"* ]]
}

@test "falls back to env var when JSON has no effort fields" {
  export CLAUDE_CODE_EFFORT_LEVEL="high"
  write_input '{"model":{"display_name":"Sonnet 4.6"}}'
  run bash "$PLUGIN"
  [[ "$output" == *"Sonnet 4.6 ${HIGH}"* ]]
}

@test "falls back to settings.json effortLevel when nothing else set" {
  mkdir -p "$HOME/.claude"
  printf '%s' '{"effortLevel":"low"}' > "$HOME/.claude/settings.json"
  write_input '{"model":{"display_name":"Sonnet 4.6"}}'
  run bash "$PLUGIN"
  [[ "$output" == *"Sonnet 4.6 ${LOW}"* ]]
}

@test "no effort anywhere defaults to medium" {
  write_input '{"model":{"display_name":"Sonnet 4.6"}}'
  run bash "$PLUGIN"
  [[ "$output" == *"Sonnet 4.6 ${MED}"* ]]
}

# ── Model name ────────────────────────────────────────────────────────────────

@test "missing model display_name falls back to 'Claude'" {
  write_input '{"effort":{"level":"medium"}}'
  run bash "$PLUGIN"
  [[ "$output" == *"Claude ${MED}"* ]]
}
