#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

# Test suite for bin/lemma-queue.
#
# hooks/lemma-commit.sh calls this after a commit lands, to record a CANDIDATE
# for assertion into lemmalog. It is deliberately dumb: it records that a commit
# happened, never what the commit means. Meaning needs the reasoning that only
# Claude has in context, and it arrives later via /lemma-drain.
#
# Same split as bin/contract-record feeding experiments/lemmalog: exact rows in,
# judgement applied afterwards.
#
# Two hard rules, inherited from contract-record and for the same reason:
#   - it always exits 0. It runs inside a PostToolUse hook, where a failure
#     becomes model-visible noise attached to an unrelated tool call.
#   - anything unparseable is dropped in silence.

Q="$BATS_TEST_DIRNAME/lemma-queue"

setup() {
  export CLAUDE_RIG_LEMMA_QUEUE="$BATS_TEST_TMPDIR/pending.tsv"
}

# --- the happy path ------------------------------------------------------

@test "records a commit as repo, sha, timestamp, subject" {
  run "$Q" claude-rig 03d41dc "contract: record what each test established"
  [ "$status" -eq 0 ]

  run cat "$CLAUDE_RIG_LEMMA_QUEUE"
  [[ "$output" == "claude-rig"$'\t'"03d41dc"$'\t'* ]]
  [[ "$output" == *"contract: record what each test established" ]]
}

@test "stamps the row with an epoch timestamp" {
  "$Q" claude-rig 03d41dc "a subject"

  run cut -f3 "$CLAUDE_RIG_LEMMA_QUEUE"
  [[ "$output" =~ ^[0-9]{10}$ ]]
}

@test "appends, so commits accumulate across a session" {
  "$Q" claude-rig 03d41dc "first"
  "$Q" claude-rig fde410d "second"

  run wc -l < "$CLAUDE_RIG_LEMMA_QUEUE"
  [ "${output// /}" -eq 2 ]
}

@test "creates the queue file and its directory when absent" {
  export CLAUDE_RIG_LEMMA_QUEUE="$BATS_TEST_TMPDIR/nested/deeper/pending.tsv"

  run "$Q" claude-rig 03d41dc "a subject"
  [ "$status" -eq 0 ]
  [ -f "$CLAUDE_RIG_LEMMA_QUEUE" ]
}

@test "keeps a subject containing tabs on one row" {
  # git subjects are free text; a stray tab would shift every later column.
  "$Q" claude-rig 03d41dc "$(printf 'before\tafter')"

  run wc -l < "$CLAUDE_RIG_LEMMA_QUEUE"
  [ "${output// /}" -eq 1 ]
  run cut -f4 "$CLAUDE_RIG_LEMMA_QUEUE"
  [ "$output" = "before after" ]
}

# --- dedupe --------------------------------------------------------------
#
# A `git commit` with nothing staged fails and leaves HEAD unmoved, but the
# hook still reads `git log -1` and would re-queue the previous commit. Same
# shape for a re-run --amend. The SHA is the identity.

@test "ignores a repeat of the most recent sha for that repo" {
  "$Q" claude-rig 03d41dc "first"
  run "$Q" claude-rig 03d41dc "first"
  [ "$status" -eq 0 ]

  run wc -l < "$CLAUDE_RIG_LEMMA_QUEUE"
  [ "${output// /}" -eq 1 ]
}

@test "the same sha in a DIFFERENT repo is not a duplicate" {
  # Short SHAs collide across repos far more often than full ones.
  "$Q" claude-rig 03d41dc "first"
  "$Q" questor 03d41dc "unrelated"

  run wc -l < "$CLAUDE_RIG_LEMMA_QUEUE"
  [ "${output// /}" -eq 2 ]
}

@test "a sha returning after another commit is recorded again" {
  # An amend/revert dance can legitimately land back on an earlier sha; only
  # an immediate repeat is the failed-commit signature.
  "$Q" claude-rig 03d41dc "first"
  "$Q" claude-rig fde410d "second"
  "$Q" claude-rig 03d41dc "back again"

  run wc -l < "$CLAUDE_RIG_LEMMA_QUEUE"
  [ "${output// /}" -eq 3 ]
}

# --- never break the caller ----------------------------------------------

@test "exits 0 and writes nothing when called with no arguments" {
  run "$Q"
  [ "$status" -eq 0 ]
  [ ! -s "$CLAUDE_RIG_LEMMA_QUEUE" ]
}

@test "exits 0 and writes nothing when the sha is missing" {
  run "$Q" claude-rig
  [ "$status" -eq 0 ]
  [ ! -s "$CLAUDE_RIG_LEMMA_QUEUE" ]
}

@test "records a commit with an empty subject rather than dropping it" {
  # An empty subject is unusual but the commit still happened; losing it
  # would leave a silent hole in the queue.
  run "$Q" claude-rig 03d41dc ""
  [ "$status" -eq 0 ]

  run cut -f2 "$CLAUDE_RIG_LEMMA_QUEUE"
  [ "$output" = "03d41dc" ]
}

@test "exits 0 when the queue path is unwritable" {
  export CLAUDE_RIG_LEMMA_QUEUE="/dev/null/impossible/pending.tsv"

  run "$Q" claude-rig 03d41dc "a subject"
  [ "$status" -eq 0 ]
}

@test "exits 0 on a corrupt existing queue rather than refusing to append" {
  printf 'not a tsv row\n' > "$CLAUDE_RIG_LEMMA_QUEUE"

  run "$Q" claude-rig 03d41dc "a subject"
  [ "$status" -eq 0 ]

  run wc -l < "$CLAUDE_RIG_LEMMA_QUEUE"
  [ "${output// /}" -eq 2 ]
}
