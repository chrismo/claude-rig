#!/usr/bin/env bats

# Test suite for the 2.77-spend plugin.
#
# Layout:  <pct>% <used>/<limit>
#
# Only accounts with usage credits have anything here, so on an individual plan
# this segment is absent entirely and 2.76 keeps showing 5h/7d from the payload.
# On an account without credits AND without rate_limits in the payload — the
# Enterprise shape — it falls back to the five_hour/seven_day the API returns,
# so that line is not simply blank.
#
# A status line must never break the prompt: every failure path here is silent
# and exit 0.

PLUGIN="$BATS_TEST_DIRNAME/plugins.d/2.77-spend"

GREEN=$'\033[2;32m'
YELLOW=$'\033[2;33m'
RED=$'\033[2;31m'

setup() {
  export CLAUDE_STATUS_INPUT="$BATS_TEST_TMPDIR/input.json"
  export CLAUDE_RIG_SPEND_JSON="$BATS_TEST_TMPDIR/usage.json"
  export CLAUDE_RIG_SPEND_CACHE="$BATS_TEST_TMPDIR/cache.json"
  echo '{"rate_limits":{"five_hour":{"used_percentage":5,"resets_at":1788223200}}}' > "$CLAUDE_STATUS_INPUT"
}

credits() {
  local used=$1 limit=$2 percent=$3
  cat > "$CLAUDE_RIG_SPEND_JSON" <<JSON
{"spend":{"used":{"amount_minor":$used,"currency":"USD","exponent":2},
          "limit":{"amount_minor":$limit,"currency":"USD","exponent":2},
          "percent":$percent,"enabled":true}}
JSON
}

no_credits() {
  cat > "$CLAUDE_RIG_SPEND_JSON" <<'JSON'
{"five_hour":{"utilization":12.0},"seven_day":{"utilization":34.0},
 "spend":{"used":{"amount_minor":0,"currency":"USD","exponent":2},
          "limit":null,"percent":0,"enabled":false}}
JSON
}

@test "credits account shows spend against the limit" {
  credits 1234 5000 25
  run "$PLUGIN"
  [ "$status" -eq 0 ]
  [[ "$output" == *'$12'* ]]
  [[ "$output" == *'$50'* ]]
  [[ "$output" != *"credits"* ]]
  [[ "$output" == *"25%"* ]]
}

@test "under 70 percent is green" {
  credits 1234 5000 25
  run "$PLUGIN"
  [[ "$output" == *"$GREEN"* ]]
}

@test "at 70 percent it turns yellow" {
  credits 3500 5000 70
  run "$PLUGIN"
  [[ "$output" == *"$YELLOW"* ]]
}

@test "at 90 percent it turns red" {
  credits 4500 5000 90
  run "$PLUGIN"
  [[ "$output" == *"$RED"* ]]
}

@test "individual plan renders nothing, leaving 2.76 to show 5h/7d" {
  no_credits
  run "$PLUGIN"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "no credits and no rate_limits falls back to the API's own windows" {
  no_credits
  echo '{"model":{"id":"claude-opus-5"}}' > "$CLAUDE_STATUS_INPUT"
  run "$PLUGIN"
  [ "$status" -eq 0 ]
  [[ "$output" == *"5h 12%"* ]]
  [[ "$output" == *"7d 34%"* ]]
}

# PATH is stripped too: the plugin deliberately falls back to a claude-spend on
# PATH (install.sh symlinks it there), so overriding the path alone finds it.
@test "a missing claude-spend is silent, not a broken prompt" {
  credits 1234 5000 25
  CLAUDE_RIG_SPEND_BIN="$BATS_TEST_TMPDIR/nope" PATH="/usr/bin:/bin" run "$PLUGIN"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "an unreachable API is silent, not a broken prompt" {
  export CLAUDE_RIG_SPEND_JSON="$BATS_TEST_TMPDIR/does-not-exist.json"
  run "$PLUGIN"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
