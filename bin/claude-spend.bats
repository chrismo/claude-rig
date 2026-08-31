#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

# Test suite for bin/claude-spend.
#
# `.spend` is the usage-credits block, not "current usage". On an account with
# credits enabled it carries a money limit; on an individual plan `limit`, `cap`
# and `balance` are all null and there is no dollar figure anywhere in the
# response. Both shapes have to produce a sane answer, and neither may be
# confused with an actual failure.

S="$BATS_TEST_DIRNAME/claude-spend"

setup() {
  export CLAUDE_RIG_SPEND_JSON="$BATS_TEST_TMPDIR/usage.json"
}

# The real payload from an individual Max plan, trimmed to the keys that matter.
individual_plan() {
  cat > "$CLAUDE_RIG_SPEND_JSON" <<'JSON'
{
  "five_hour": { "utilization": 5.0, "limit_dollars": null, "used_dollars": null },
  "seven_day": { "utilization": 8.0, "limit_dollars": null, "used_dollars": null },
  "extra_usage": { "is_enabled": false, "credits_ever_enabled": false },
  "spend": {
    "used": { "amount_minor": 0, "currency": "USD", "exponent": 2 },
    "limit": null,
    "percent": 0,
    "enabled": false,
    "cap": null,
    "balance": null,
    "can_purchase_credits": false
  },
  "member_dashboard_available": false
}
JSON
}

# Synthetic: what the shape looks like once credits carry a spend limit.
with_spend_limit() {
  local used="$1" limit="$2" percent="$3"
  cat > "$CLAUDE_RIG_SPEND_JSON" <<JSON
{
  "spend": {
    "used": { "amount_minor": $used, "currency": "USD", "exponent": 2 },
    "limit": { "amount_minor": $limit, "currency": "USD", "exponent": 2 },
    "percent": $percent,
    "enabled": true
  }
}
JSON
}

@test "individual plan: says so instead of crashing" {
  individual_plan
  run "$S"
  [ "$status" -eq 0 ]
  [[ "$output" != *"error("* ]]
}

@test "individual plan: names the account kind and points at the status line" {
  individual_plan
  run "$S"
  [[ "$output" == *"usage credits"* ]]
  [[ "$output" == *"status line"* ]]
}

@test "individual plan: reports no dollar figure it does not have" {
  individual_plan
  run "$S"
  [[ "$output" != *'$0'* ]]
}

@test "spend block absent entirely: same answer, still exit 0" {
  echo '{"five_hour":{"utilization":5.0}}' > "$CLAUDE_RIG_SPEND_JSON"
  run "$S"
  [ "$status" -eq 0 ]
  [[ "$output" == *"usage credits"* ]]
}

@test "credits enabled: reports percent, used, and limit" {
  with_spend_limit 1234 5000 25
  run "$S"
  [ "$status" -eq 0 ]
  [[ "$output" == *"25%"* ]]
  [[ "$output" == *'$12.34'* ]]
  [[ "$output" == *'$50.00'* ]]
}

@test "credits enabled: whole dollars keep both decimal places" {
  with_spend_limit 500 10000 5
  run "$S"
  [[ "$output" == *'$5.00'* ]]
  [[ "$output" == *'$100.00'* ]]
}

@test "non-USD currency keeps its code instead of a dollar sign" {
  cat > "$CLAUDE_RIG_SPEND_JSON" <<'JSON'
{
  "spend": {
    "used": { "amount_minor": 1234, "currency": "EUR", "exponent": 2 },
    "limit": { "amount_minor": 5000, "currency": "EUR", "exponent": 2 },
    "percent": 25,
    "enabled": true
  }
}
JSON
  run "$S"
  [ "$status" -eq 0 ]
  [[ "$output" == *"12.34 EUR"* ]]
  [[ "$output" != *'$'* ]]
}

@test "a zero limit is still a limit, not an absent one" {
  with_spend_limit 0 0 0
  run "$S"
  [ "$status" -eq 0 ]
  [[ "$output" == *'$0.00 / $0.00'* ]]
}

@test "fetch failure is an error, and names the file" {
  export CLAUDE_RIG_SPEND_JSON="$BATS_TEST_TMPDIR/does-not-exist.json"
  run "$S"
  [ "$status" -ne 0 ]
  [[ "$output" == *"does-not-exist.json"* ]]
}

@test "an empty response is an error, not an account diagnosis" {
  : > "$CLAUDE_RIG_SPEND_JSON"
  run "$S"
  [ "$status" -ne 0 ]
  [[ "$output" != *"usage credits"* ]]
}

@test "a missing super says so, instead of blaming the API" {
  individual_plan
  PATH="/usr/bin:/bin" run "$S"
  [ "$status" -ne 0 ]
  [[ "$output" == *"super"* ]]
}

@test "an ambient superdb version pin does not decide what this runs" {
  with_spend_limit 1234 5000 25
  ASDF_SUPERDB_VERSION="0.0.0-nonexistent" run "$S"
  [ "$status" -eq 0 ]
  [[ "$output" == *'$12.34'* ]]
}

@test "malformed response is an error, not a parser spew" {
  echo 'not json' > "$CLAUDE_RIG_SPEND_JSON"
  run "$S"
  [ "$status" -ne 0 ]
  [[ "$output" == *"could not read"* ]]
}
