#!/usr/bin/env bats

# Test suite for the 2.76-rate-limits-pacman plugin.
#
# Layout:  <mood> 5h [bar] <dur> | 7d [bar] <dur>
#   mood — single emoji, the worse of 5h and 7d levels
#   bar  — N-cell track: ● used, ◇ expected, ◉ when same slot, · empty
#   dur  — largest single unit only (4d9h32m → 4d)

PLUGIN="$BATS_TEST_DIRNAME/plugins.d/2.76-rate-limits-pacman"

FIVE_HOUR_SECONDS=18000
SEVEN_DAY_SECONDS=604800

GREEN=$'\033[2;32m'
YELLOW=$'\033[2;33m'
RED=$'\033[2;31m'

setup() {
  TEST_DIR="$(mktemp -d "$TMPDIR/rate-limits-pacman-test.XXXXXX")"
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

# ── Mood face: takes the worse of the two windows ─────────────────────────────

@test "mood: (×_×) panic when one window is ≥90% absolute" {
  local now five_resets seven_resets
  now=$(date +%s)
  five_resets=$(( now + 100 ))
  seven_resets=$(( now + SEVEN_DAY_SECONDS - 86400 ))
  write_input 92 "$five_resets" 5 "$seven_resets"

  run bash "$PLUGIN"
  [[ "$output" == *"(×_×)"* ]]
}

@test "mood: (^_^) chill when both well under pace and low usage" {
  local now five_resets seven_resets
  now=$(date +%s)
  # 1h elapsed of 5h, 1% used → ratio 0.05
  # 1d elapsed of 7d, 1% used → ratio 0.07
  five_resets=$(( now + FIVE_HOUR_SECONDS - 3600 ))
  seven_resets=$(( now + SEVEN_DAY_SECONDS - 86400 ))
  write_input 1 "$five_resets" 1 "$seven_resets"

  run bash "$PLUGIN"
  [[ "$output" == *"(^_^)"* ]]
}

@test "mood: (•_•) neutral on pace" {
  local now five_resets seven_resets
  now=$(date +%s)
  # both right on pace
  five_resets=$(( now + FIVE_HOUR_SECONDS - 2 * 3600 ))
  seven_resets=$(( now + SEVEN_DAY_SECONDS - 4 * 86400 ))
  write_input 40 "$five_resets" 57 "$seven_resets"

  run bash "$PLUGIN"
  [[ "$output" == *"(•_•)"* ]]
}

@test "mood: (>_<) worried when one window is over pace (ratio ~1.4)" {
  local now five_resets seven_resets
  now=$(date +%s)
  # 5h: 60% used at hour 2 → expected 40, ratio 1.5 → level 3 (over pace)
  five_resets=$(( now + FIVE_HOUR_SECONDS - 2 * 3600 ))
  seven_resets=$(( now + SEVEN_DAY_SECONDS - 86400 ))
  write_input 56 "$five_resets" 5 "$seven_resets"

  run bash "$PLUGIN"
  [[ "$output" == *"(>_<)"* ]]
}

# ── Pac-man bar: 5-slot layout for 5h ─────────────────────────────────────────

@test "5h bar: ◉ when used and expected slot match" {
  local now five_resets seven_resets
  now=$(date +%s)
  # 40% used, 40% expected (2h elapsed of 5h) → both slot 2
  five_resets=$(( now + FIVE_HOUR_SECONDS - 2 * 3600 ))
  seven_resets=$(( now + SEVEN_DAY_SECONDS - 86400 ))
  write_input 40 "$five_resets" 5 "$seven_resets"

  run bash "$PLUGIN"
  [[ "$output" == *"5h [··◉··]"* ]]
}

@test "5h bar: under pace shows ● before ◇" {
  local now five_resets seven_resets
  now=$(date +%s)
  # 20% used (slot 1) at 60% expected (3h elapsed → slot 3)
  five_resets=$(( now + FIVE_HOUR_SECONDS - 3 * 3600 ))
  seven_resets=$(( now + SEVEN_DAY_SECONDS - 86400 ))
  write_input 20 "$five_resets" 5 "$seven_resets"

  run bash "$PLUGIN"
  [[ "$output" == *"5h [·●·◇·]"* ]]
}

@test "5h bar: over pace shows ● after ◇" {
  local now five_resets seven_resets
  now=$(date +%s)
  # 80% used (slot 4) at 40% expected (2h elapsed → slot 2)
  five_resets=$(( now + FIVE_HOUR_SECONDS - 2 * 3600 ))
  seven_resets=$(( now + SEVEN_DAY_SECONDS - 86400 ))
  write_input 80 "$five_resets" 5 "$seven_resets"

  run bash "$PLUGIN"
  [[ "$output" == *"5h [··◇·●]"* ]]
}

@test "5h bar: 0% at start is ●····" {
  local now five_resets seven_resets
  now=$(date +%s)
  five_resets=$(( now + FIVE_HOUR_SECONDS - 60 ))
  seven_resets=$(( now + SEVEN_DAY_SECONDS - 86400 ))
  write_input 0 "$five_resets" 5 "$seven_resets"

  run bash "$PLUGIN"
  [[ "$output" == *"5h [◉····]"* ]]
}

# ── Pac-man bar: 7-slot layout for 7d ─────────────────────────────────────────

@test "7d bar: 7 cells wide" {
  local now five_resets seven_resets
  now=$(date +%s)
  # 50% used (slot 3) at 50% expected (3.5d elapsed → slot 3) → merged
  five_resets=$(( now + FIVE_HOUR_SECONDS - 60 ))
  seven_resets=$(( now + SEVEN_DAY_SECONDS - 302400 ))  # 3.5d elapsed
  write_input 5 "$five_resets" 50 "$seven_resets"

  run bash "$PLUGIN"
  [[ "$output" == *"7d [···◉···]"* ]]
}

@test "7d bar: under pace at day 4" {
  local now five_resets seven_resets
  now=$(date +%s)
  # 14% used (slot 0) at day 4 elapsed (slot 4)
  five_resets=$(( now + FIVE_HOUR_SECONDS - 60 ))
  seven_resets=$(( now + SEVEN_DAY_SECONDS - 4 * 86400 ))
  write_input 5 "$five_resets" 14 "$seven_resets"

  run bash "$PLUGIN"
  [[ "$output" == *"7d [●···◇··]"* ]]
}

@test "7d bar: over pace at day 1" {
  local now five_resets seven_resets
  now=$(date +%s)
  # 60% used (slot 4) at day 1 elapsed (slot 1)
  five_resets=$(( now + FIVE_HOUR_SECONDS - 60 ))
  seven_resets=$(( now + SEVEN_DAY_SECONDS - 86400 ))
  write_input 5 "$five_resets" 60 "$seven_resets"

  run bash "$PLUGIN"
  [[ "$output" == *"7d [·◇··●··]"* ]]
}

# ── Duration: largest unit only ───────────────────────────────────────────────

@test "duration: 4d12h... → 4d (no compound units in output)" {
  local now five_resets seven_resets
  now=$(date +%s)
  five_resets=$(( now + 60 ))
  seven_resets=$(( now + 4 * 86400 + 12 * 3600 + 30 * 60 ))
  write_input 5 "$five_resets" 5 "$seven_resets"

  run bash "$PLUGIN"
  # No 4d3h or 4d12h compound — only 4d
  [[ ! "$output" =~ [0-9]d[0-9] ]]
  [[ "$output" == *"] 4d"* ]]
}

@test "duration: 1h45m → 1h" {
  local now five_resets seven_resets
  now=$(date +%s)
  five_resets=$(( now + 3600 + 45 * 60 ))
  seven_resets=$(( now + 60 ))
  write_input 5 "$five_resets" 5 "$seven_resets"

  run bash "$PLUGIN"
  [[ ! "$output" =~ [0-9]h[0-9] ]]
  [[ "$output" == *"] 1h"* ]]
}

@test "duration: 35m stays as 35m" {
  local now five_resets seven_resets
  now=$(date +%s)
  five_resets=$(( now + 35 * 60 + 30 ))  # 35m30s buffer
  seven_resets=$(( now + 60 ))
  write_input 5 "$five_resets" 5 "$seven_resets"

  run bash "$PLUGIN"
  [[ "$output" =~ \]\ [0-9]+m ]]
}

# ── Duration: missing resets_at ──────────────────────────────────────────────

@test "duration: missing resets_at does not output error(missing)" {
  local now seven_resets
  now=$(date +%s)
  seven_resets=$(( now + 86400 ))
  cat > "$INPUT" <<EOF
{
  "rate_limits": {
    "five_hour": {
      "used_percentage": 30
    },
    "seven_day": {
      "used_percentage": 25,
      "resets_at": $seven_resets
    }
  }
}
EOF

  run bash "$PLUGIN"
  [[ "$output" != *'error("missing")'* ]]
}

# ── Color: same precedence as the wedge plugin ────────────────────────────────

@test "color: green when window is well under pace" {
  local now five_resets seven_resets
  now=$(date +%s)
  five_resets=$(( now + FIVE_HOUR_SECONDS - 4 * 3600 ))   # hour 4 of 5h
  seven_resets=$(( now + SEVEN_DAY_SECONDS - 6 * 86400 )) # day 6 of 7d
  write_input 50 "$five_resets" 50 "$seven_resets"

  run bash "$PLUGIN"
  [[ "$output" == *"${GREEN}5h"* ]]
  [[ "$output" == *"${GREEN}7d"* ]]
}

@test "color: red on ≥90% absolute" {
  local now five_resets seven_resets
  now=$(date +%s)
  five_resets=$(( now + 100 ))
  seven_resets=$(( now + SEVEN_DAY_SECONDS - 86400 ))
  write_input 95 "$five_resets" 10 "$seven_resets"

  run bash "$PLUGIN"
  [[ "$output" == *"${RED}5h"* ]]
}

@test "color: yellow when over pace" {
  local now five_resets seven_resets
  now=$(date +%s)
  # 60% used at hour 2 of 5h → ratio 1.5 → over pace
  five_resets=$(( now + FIVE_HOUR_SECONDS - 2 * 3600 ))
  seven_resets=$(( now + SEVEN_DAY_SECONDS - 86400 ))
  write_input 60 "$five_resets" 5 "$seven_resets"

  run bash "$PLUGIN"
  [[ "$output" == *"${YELLOW}5h"* ]]
}
