#!/usr/bin/env bats

# Test suite for the 1.50-model plugin.
#
# Renders "<model display name> <bars>", where bars is a 5-segment indicator
# (low/medium/high/xhigh/max) showing reasoning effort, lit green up to the
# current level and dark grey beyond it. Effort is resolved in order:
# statusline input (effort.level) -> CLAUDE_CODE_EFFORT_LEVEL env var ->
# settings.json (effortLevel) -> default (high).

PLUGIN="$BATS_TEST_DIRNAME/plugins.d/1.50-model"

LIT=$'\033[2;32m'
DIM=$'\033[38;5;238m'
RESET=$'\033[2;37m'
BAR="▌"

setup() {
  TEST_DIR="$(mktemp -d "$TMPDIR/model-test.XXXXXX")"
  INPUT="$TEST_DIR/input.json"
  SETTINGS="$TEST_DIR/settings.json"
  export CLAUDE_STATUS_INPUT="$INPUT"
  export CLAUDE_SETTINGS_PATH="$SETTINGS"
  unset CLAUDE_CODE_EFFORT_LEVEL
}

teardown() {
  rm -rf "$TEST_DIR"
}

write_input() {
  local model_name=$1 effort_level=$2
  if [[ -n "$effort_level" ]]; then
    cat > "$INPUT" <<EOF
{"model": {"display_name": "$model_name"}, "effort": {"level": "$effort_level"}}
EOF
  else
    cat > "$INPUT" <<EOF
{"model": {"display_name": "$model_name"}}
EOF
  fi
}

write_settings() {
  local effort_level=$1
  cat > "$SETTINGS" <<EOF
{"effortLevel": "$effort_level"}
EOF
}

# Build the expected bars segment for N lit bars out of 5.
bars_for() {
  local lit_count=$1
  local out="$LIT"
  local i
  for ((i = 0; i < lit_count; i++)); do out+="$BAR"; done
  if [[ $lit_count -lt 5 ]]; then
    out+="$DIM"
    for ((i = lit_count; i < 5; i++)); do out+="$BAR"; done
  fi
  out+="$RESET"
  printf '%s' "$out"
}

@test "renders the model display name" {
  write_input "Sonnet 5" "high"
  run env "$PLUGIN"
  [[ "$output" == "Sonnet 5 "* ]]
}

@test "falls back to 'Claude' when display_name is missing" {
  printf '{}' > "$INPUT"
  run env "$PLUGIN"
  [[ "$output" == "Claude "* ]]
}

@test "reads effort.level from the statusline input" {
  write_input "Sonnet 5" "xhigh"
  run env "$PLUGIN"
  [ "$output" = "Sonnet 5 $(bars_for 4)" ]
}

@test "low renders 1 lit bar" {
  write_input "Sonnet 5" "low"
  run env "$PLUGIN"
  [ "$output" = "Sonnet 5 $(bars_for 1)" ]
}

@test "medium renders 2 lit bars" {
  write_input "Sonnet 5" "medium"
  run env "$PLUGIN"
  [ "$output" = "Sonnet 5 $(bars_for 2)" ]
}

@test "high renders 3 lit bars" {
  write_input "Sonnet 5" "high"
  run env "$PLUGIN"
  [ "$output" = "Sonnet 5 $(bars_for 3)" ]
}

@test "xhigh renders 4 lit bars" {
  write_input "Sonnet 5" "xhigh"
  run env "$PLUGIN"
  [ "$output" = "Sonnet 5 $(bars_for 4)" ]
}

@test "max renders 5 lit bars" {
  write_input "Sonnet 5" "max"
  run env "$PLUGIN"
  [ "$output" = "Sonnet 5 $(bars_for 5)" ]
}

@test "effort level is case-insensitive" {
  write_input "Sonnet 5" "XHIGH"
  run env "$PLUGIN"
  [ "$output" = "Sonnet 5 $(bars_for 4)" ]
}

@test "defaults to high (3 lit bars) when no effort is found anywhere" {
  printf '{"model": {"display_name": "Sonnet 5"}}' > "$INPUT"
  run env "$PLUGIN"
  [ "$output" = "Sonnet 5 $(bars_for 3)" ]
}

@test "CLAUDE_CODE_EFFORT_LEVEL env var is used when input has no effort.level" {
  printf '{"model": {"display_name": "Sonnet 5"}}' > "$INPUT"
  run env CLAUDE_CODE_EFFORT_LEVEL="max" "$PLUGIN"
  [ "$output" = "Sonnet 5 $(bars_for 5)" ]
}

@test "statusline input effort.level takes precedence over the env var" {
  write_input "Sonnet 5" "low"
  run env CLAUDE_CODE_EFFORT_LEVEL="max" "$PLUGIN"
  [ "$output" = "Sonnet 5 $(bars_for 1)" ]
}

@test "falls back to settings.json effortLevel when input and env var are absent" {
  printf '{"model": {"display_name": "Sonnet 5"}}' > "$INPUT"
  write_settings "xhigh"
  run env "$PLUGIN"
  [ "$output" = "Sonnet 5 $(bars_for 4)" ]
}

@test "env var takes precedence over settings.json" {
  printf '{"model": {"display_name": "Sonnet 5"}}' > "$INPUT"
  write_settings "low"
  run env CLAUDE_CODE_EFFORT_LEVEL="max" "$PLUGIN"
  [ "$output" = "Sonnet 5 $(bars_for 5)" ]
}
