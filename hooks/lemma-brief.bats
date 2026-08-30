#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

# Test suite for hooks/lemma-brief.sh.
#
# Fires on SessionStart. It is the READ half of the lemmalog loop: without it,
# facts go in and are never seen again, which is how a store quietly dies.
#
# It cannot query the engine — the lemmalog MCP tools are Claude-only, and a
# SessionStart hook is a script. But the snapshot is plain TSV, so it can be
# read directly, which is safe precisely because it is read-only: the MCP server
# rewrites that file after every mutating call.
#
# It must be silent when there is no news. A SessionStart hook that speaks every
# time is a hook people disable.

HOOK="$BATS_TEST_DIRNAME/lemma-brief.sh"

setup() {
  export CLAUDE_RIG_LEMMA_QUEUE="$BATS_TEST_TMPDIR/pending.tsv"
  export CLAUDE_RIG_LEMMA_SNAPSHOT="$BATS_TEST_TMPDIR/store.snapshot"
  # A real repo: the hook names the repo from `git rev-parse --show-toplevel`,
  # matching how lemma-commit.sh names it. A bare directory would resolve to
  # nothing, which is the correct behaviour but not the case under test here.
  export CLAUDE_RIG_LEMMA_CWD="$BATS_TEST_TMPDIR/claude-rig"
  mkdir -p "$CLAUDE_RIG_LEMMA_CWD"
  git -C "$CLAUDE_RIG_LEMMA_CWD" init -q
}

queue() { printf '%s\t%s\t%s\t%s\n' "$1" "$2" 100 "$3" >> "$CLAUDE_RIG_LEMMA_QUEUE"; }

# --- silence when there is nothing to say --------------------------------

@test "silent when the queue file does not exist" {
  run "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "silent when the queue is empty" {
  : > "$CLAUDE_RIG_LEMMA_QUEUE"

  run "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "silent when the queue holds nothing for THIS repo" {
  queue questor abc1234 "unrelated work"

  run "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- reporting -----------------------------------------------------------

@test "reports the pending count for this repo" {
  queue claude-rig abc1234 "first"
  queue claude-rig def5678 "second"

  run "$HOOK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"2 commits"* ]]
  [[ "$output" == *"claude-rig"* ]]
}

@test "counts only this repo, not the whole queue" {
  queue claude-rig abc1234 "mine"
  queue questor   def5678 "theirs"
  queue questor   aaa1111 "theirs too"

  run "$HOOK"
  [[ "$output" == *"1 commit"* ]]
  [[ "$output" != *"3 commits"* ]]
}

@test "names the drain command so the queue is actionable" {
  queue claude-rig abc1234 "first"

  run "$HOOK"
  [[ "$output" == *"lemma-drain"* ]]
}

@test "reports how many facts the store already holds for this repo" {
  queue claude-rig abc1234 "first"
  cat > "$CLAUDE_RIG_LEMMA_SNAPSHOT" <<'EOF'
LEMMALOG-SNAPSHOT-V1
NOW	100
FACT	edge	1	ep1	s:claude-rig s:ruled_out s:per-repo-stores
FACT	edge	1	ep1	s:claude-rig s:uses s:datalog
FACT	edge	1	ep2	s:questor s:uses s:ruby
EOF

  run "$HOOK"
  [[ "$output" == *"Facts on record for claude-rig: 2."* ]]
}

@test "omits the facts line when the store has nothing for this repo" {
  queue claude-rig abc1234 "first"
  cat > "$CLAUDE_RIG_LEMMA_SNAPSHOT" <<'EOF'
LEMMALOG-SNAPSHOT-V1
FACT	edge	1	ep2	s:questor s:uses s:ruby
EOF

  run "$HOOK"
  [ "$status" -eq 0 ]
  # Still reports the pending commit -- it is only the facts line that is
  # suppressed. "0 facts on record" is discouraging noise on day one.
  [[ "$output" == *"1 commit"* ]]
  [[ "$output" != *"Facts on record"* ]]
}

# --- never break session startup ----------------------------------------

@test "exits 0 with no snapshot file at all" {
  queue claude-rig abc1234 "first"

  run "$HOOK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 commit"* ]]
}

@test "a malformed snapshot never breaks startup" {
  queue claude-rig abc1234 "first"
  printf 'this is not a snapshot\n\n\t\t\n' > "$CLAUDE_RIG_LEMMA_SNAPSHOT"

  run "$HOOK"
  [ "$status" -eq 0 ]
}

@test "a malformed queue never breaks startup" {
  printf 'garbage with no tabs\n' > "$CLAUDE_RIG_LEMMA_QUEUE"

  run "$HOOK"
  [ "$status" -eq 0 ]
}

@test "exits 0 when the cwd is not a git repository" {
  export CLAUDE_RIG_LEMMA_CWD="$BATS_TEST_TMPDIR/nowhere"

  run "$HOOK"
  [ "$status" -eq 0 ]
}
