#!/usr/bin/env bats

# Test suite for the 2.75-rate-limits statusline plugin.
#
# The plugin colors usage % by pace (green under, yellow at/over, red ≥90%
# absolute) and prefixes each window with a pie wedge that fills as the
# pace ratio (used / expected) climbs.

PLUGIN="$BATS_TEST_DIRNAME/plugins.d/disabled/2.75-rate-limits"

FIVE_HOUR_SECONDS=18000
SEVEN_DAY_SECONDS=604800

GREEN=$'\033[2;32m'
YELLOW=$'\033[2;33m'
RED=$'\033[2;31m'

W_EMPTY="○"
W_QUARTER="◔"
W_HALF="◑"
W_THREE="◕"
W_FULL="●"

setup() {
  TEST_DIR="$(mktemp -d "$TMPDIR/rate-limits-test.XXXXXX")"
  INPUT="$TEST_DIR/input.json"
  export CLAUDE_STATUS_INPUT="$INPUT"
}

teardown() {
  rm -rf "$TEST_DIR"
}

write_input() {
  local five_pct=$1 five_resets=$2 seven_pct=$3 seven_resets=$4
  cat > "$INPUT" <<EOF
{
  "rate_limits": {
    "five_hour": {
      "used_percentage": $five_pct,
      "resets_at": $five_resets
    },
    "seven_day": {
      "used_percentage": $seven_pct,
      "resets_at": $seven_resets
    }
  }
}
EOF
}

# ── Color × wedge: 7-day window ───────────────────────────────────────────────

@test "7d: 2% at 5 minutes elapsed is yellow ● (way over pace)" {
  local now seven_resets
  now=$(date +%s)
  seven_resets=$(( now + SEVEN_DAY_SECONDS - 300 ))
  write_input 1 $(( now + FIVE_HOUR_SECONDS - 60 )) 2 "$seven_resets"

  run bash "$PLUGIN"
  [ "$status" -eq 0 ]
  [[ "$output" == *"${YELLOW}7d ${W_FULL} 2%"* ]]
}

@test "7d: 60% at day 1 is yellow ● (way over pace)" {
  local now seven_resets
  now=$(date +%s)
  seven_resets=$(( now + SEVEN_DAY_SECONDS - 86400 ))
  write_input 10 $(( now + 100 )) 60 "$seven_resets"

  run bash "$PLUGIN"
  [[ "$output" == *"${YELLOW}7d ${W_FULL} 60%"* ]]
}

@test "7d: 80% at day 6 is green ◑ (on pace)" {
  local now seven_resets
  now=$(date +%s)
  seven_resets=$(( now + SEVEN_DAY_SECONDS - 6 * 86400 ))
  write_input 10 $(( now + 100 )) 80 "$seven_resets"

  run bash "$PLUGIN"
  [[ "$output" == *"${GREEN}7d ${W_HALF} 80%"* ]]
}

@test "7d: 50% at day 4 is green ◑ (on pace)" {
  local now seven_resets
  now=$(date +%s)
  seven_resets=$(( now + SEVEN_DAY_SECONDS - 4 * 86400 ))
  write_input 10 $(( now + 100 )) 50 "$seven_resets"

  run bash "$PLUGIN"
  [[ "$output" == *"${GREEN}7d ${W_HALF} 50%"* ]]
}

@test "7d: 95% at day 4 is red ● (over pace, absolute critical)" {
  local now seven_resets
  now=$(date +%s)
  seven_resets=$(( now + SEVEN_DAY_SECONDS - 4 * 86400 ))
  write_input 10 $(( now + 100 )) 95 "$seven_resets"

  run bash "$PLUGIN"
  [[ "$output" == *"${RED}7d ${W_FULL} 95%"* ]]
}

@test "7d: 0% is green ○" {
  local now seven_resets
  now=$(date +%s)
  seven_resets=$(( now + SEVEN_DAY_SECONDS - 86400 ))
  write_input 0 $(( now + 100 )) 0 "$seven_resets"

  run bash "$PLUGIN"
  [[ "$output" == *"${GREEN}7d ${W_EMPTY} 0%"* ]]
}

# ── Color × wedge: 5-hour window ──────────────────────────────────────────────

@test "5h: 30% at hour 2 is green ◔ (under pace, ratio ~0.75)" {
  local now five_resets
  now=$(date +%s)
  five_resets=$(( now + FIVE_HOUR_SECONDS - 2 * 3600 ))
  write_input 30 "$five_resets" 10 $(( now + 100 ))

  run bash "$PLUGIN"
  [[ "$output" == *"${GREEN}5h ${W_QUARTER} 30%"* ]]
}

@test "5h: 50% at hour 2 is yellow ◕ (over pace, ratio ~1.25)" {
  local now five_resets
  now=$(date +%s)
  five_resets=$(( now + FIVE_HOUR_SECONDS - 2 * 3600 ))
  write_input 50 "$five_resets" 10 $(( now + 100 ))

  run bash "$PLUGIN"
  [[ "$output" == *"${YELLOW}5h ${W_THREE} 50%"* ]]
}

@test "5h: 79% at hour 4 is green ◑ (on pace, ratio ~0.99)" {
  local now five_resets
  now=$(date +%s)
  five_resets=$(( now + FIVE_HOUR_SECONDS - 4 * 3600 ))
  write_input 79 "$five_resets" 10 $(( now + 100 ))

  run bash "$PLUGIN"
  [[ "$output" == *"${GREEN}5h ${W_HALF} 79%"* ]]
}

@test "5h: 95% near reset is red ◑ (red absolute, on-pace wedge)" {
  local now five_resets
  now=$(date +%s)
  five_resets=$(( now + 100 ))
  write_input 95 "$five_resets" 10 $(( now + 100 ))

  run bash "$PLUGIN"
  [[ "$output" == *"${RED}5h ${W_HALF} 95%"* ]]
}

# ── Wedge progression sweep (7d window, 1 day elapsed, expected ~14%) ─────────

@test "wedge: 5% at day 1 of 7d is ○ (ratio ~0.35)" {
  local now seven_resets
  now=$(date +%s)
  seven_resets=$(( now + SEVEN_DAY_SECONDS - 86400 ))
  write_input 1 $(( now + 100 )) 5 "$seven_resets"

  run bash "$PLUGIN"
  [[ "$output" == *"7d ${W_EMPTY} 5%"* ]]
}

@test "wedge: 10% at day 1 of 7d is ◔ (ratio ~0.7)" {
  local now seven_resets
  now=$(date +%s)
  seven_resets=$(( now + SEVEN_DAY_SECONDS - 86400 ))
  write_input 1 $(( now + 100 )) 10 "$seven_resets"

  run bash "$PLUGIN"
  [[ "$output" == *"7d ${W_QUARTER} 10%"* ]]
}

@test "wedge: 14% at day 1 of 7d is ◑ (ratio ~0.98)" {
  local now seven_resets
  now=$(date +%s)
  seven_resets=$(( now + SEVEN_DAY_SECONDS - 86400 ))
  write_input 1 $(( now + 100 )) 14 "$seven_resets"

  run bash "$PLUGIN"
  [[ "$output" == *"7d ${W_HALF} 14%"* ]]
}

@test "wedge: 20% at day 1 of 7d is ◕ (ratio ~1.4)" {
  local now seven_resets
  now=$(date +%s)
  seven_resets=$(( now + SEVEN_DAY_SECONDS - 86400 ))
  write_input 1 $(( now + 100 )) 20 "$seven_resets"

  run bash "$PLUGIN"
  [[ "$output" == *"7d ${W_THREE} 20%"* ]]
}

@test "wedge: 30% at day 1 of 7d is ● (ratio ~2.1)" {
  local now seven_resets
  now=$(date +%s)
  seven_resets=$(( now + SEVEN_DAY_SECONDS - 86400 ))
  write_input 1 $(( now + 100 )) 30 "$seven_resets"

  run bash "$PLUGIN"
  [[ "$output" == *"7d ${W_FULL} 30%"* ]]
}
