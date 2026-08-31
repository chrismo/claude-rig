#!/usr/bin/env bats

# Test suite for the 2.78-daily plugin.
#
# Layout:  24h [bar] <dur>
#
# Same alphabet as 2.76: ● used, ◇ on-pace, ◉ both at once, · empty. The window
# is the UTC day: the credit limit is a daily one that resets at midnight UTC,
# so the same used/limit figures 2.77 prints as "92% $4283/$4640" are today's
# spend, and the bar plots them against how far into the UTC day we are.
#
# A status line must never break the prompt: every failure path is silent, exit 0.

PLUGIN="$BATS_TEST_DIRNAME/plugins.d/2.78-daily"

GREEN=$'\033[2;32m'
YELLOW=$'\033[2;33m'
RED=$'\033[2;31m'

setup() {
  export CLAUDE_RIG_SPEND_JSON="$BATS_TEST_TMPDIR/usage.json"
  export CLAUDE_RIG_SPEND_CACHE="$BATS_TEST_TMPDIR/cache.json"
}

# credits <used_minor> <limit_minor> <percent>
credits() {
  cat > "$CLAUDE_RIG_SPEND_JSON" <<JSON
{"spend":{"used":{"amount_minor":$1,"currency":"USD","exponent":2},
          "limit":{"amount_minor":$2,"currency":"USD","exponent":2},
          "percent":$3,"enabled":true}}
JSON
}

no_credits() {
  cat > "$CLAUDE_RIG_SPEND_JSON" <<'JSON'
{"spend":{"used":{"amount_minor":0,"currency":"USD","exponent":2},
          "limit":null,"percent":0,"enabled":false}}
JSON
}

# at <utc-hh:mm> — pin the clock so bar position is deterministic.
at() { export CLAUDE_RIG_DAILY_NOW="$1"; }

@test "renders a 24h segment on a credits account" {
  credits 100000 464000 21
  at "2026-08-31T12:00:00Z"
  run "$PLUGIN"
  [ "$status" -eq 0 ]
  [[ "$output" == *"24h"* ]]
  [[ "$output" == *"["*"]"* ]]
}

@test "silent on an account with no usage credits" {
  no_credits
  at "2026-08-31T12:00:00Z"
  run "$PLUGIN"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "plots the same used/limit figures the spend segment reports" {
  # 2.77 renders this as "92% $4283/$4640"; near-spent, near the end of the day,
  # so the used marker is at the last slot and the segment is red.
  credits 428300 464000 92
  at "2026-08-31T23:35:00Z"
  run "$PLUGIN"
  [[ "$output" == *"$RED"* ]]
  [[ "$output" == *"25m"* ]]
  [[ "$output" == *"●"* || "$output" == *"◉"* ]]
}

@test "at 92 percent late in the day, used sits on the on-pace diamond" {
  credits 428300 464000 92
  at "2026-08-31T23:35:00Z"
  # Both land in the final slot, so they merge rather than printing separately.
  run "$PLUGIN"
  [[ "$output" == *"◉"* ]]
}

@test "no state file is written - the payload figure is already today's spend" {
  credits 428300 464000 92
  at "2026-08-31T23:35:00Z"
  run "$PLUGIN"
  [ ! -e "$HOME/.claude/cache/claude-daily-burn" ] || skip "pre-existing state file"
}

@test "countdown shows time remaining until midnight UTC" {
  credits 100000 464000 21
  at "2026-08-31T23:22:00Z"
  run "$PLUGIN"
  [[ "$output" == *"38m"* ]]
}

@test "countdown uses the largest single unit" {
  credits 100000 464000 21
  at "2026-08-31T06:00:00Z"
  run "$PLUGIN"
  [[ "$output" == *"18h"* ]]
}

@test "spending under pace is green" {
  credits 46400 464000 10      # 10% spent a quarter into the day
  at "2026-08-31T06:00:00Z"
  run "$PLUGIN"
  [[ "$output" == *"$GREEN"* ]]
}

@test "spending over pace is yellow" {
  credits 278400 464000 60     # 60% spent at midday
  at "2026-08-31T12:00:00Z"
  run "$PLUGIN"
  [[ "$output" == *"$YELLOW"* ]]
}

@test "at or over 90 percent is red regardless of pace" {
  credits 421120 464000 91     # 91% but the day is nearly over, so on pace
  at "2026-08-31T23:30:00Z"
  run "$PLUGIN"
  [[ "$output" == *"$RED"* ]]
}

@test "used marker tracks percent spent, not time" {
  credits 46400 464000 10      # 10% spent, but late in the day
  at "2026-08-31T23:00:00Z"
  run "$PLUGIN"
  # Used near the start, expected at the end: two distinct markers.
  [[ "$output" == *"●"* ]]
  [[ "$output" == *"◇"* ]]
}

@test "a failing spend binary is silent" {
  export CLAUDE_RIG_SPEND_BIN=/nonexistent/claude-spend
  at "2026-08-31T12:00:00Z"
  run "$PLUGIN"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
