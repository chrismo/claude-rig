#!/usr/bin/env bats

# Test suite for the 1.10-project plugin.
#
# Renders the worktree/project name (basename of project_dir), EXCEPT when it
# equals the current git branch — in that case the name is redundant with the
# git segment, so the segment is dropped entirely. Names are truncated to 40
# chars (37 + "...").

PLUGIN="$BATS_TEST_DIRNAME/plugins.d/1.10-project"

setup() {
  TEST_DIR="$(mktemp -d "$TMPDIR/project-test.XXXXXX")"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# Make a git repo at $TEST_DIR/<name> on branch <branch> (unborn, no commits).
make_repo() {
  local name=$1 branch=$2
  local repo="$TEST_DIR/$name"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" symbolic-ref HEAD "refs/heads/$branch"
  printf '%s' "$repo"
}

run_plugin() {
  local repo=$1
  run env CLAUDE_PROJECT_DIR="$repo" CLAUDE_CURRENT_DIR="$repo" "$PLUGIN"
}

@test "outputs the worktree name when it differs from the branch" {
  repo=$(make_repo "myapp" "feature-x")
  run_plugin "$repo"
  [ "$output" = "myapp" ]
}

@test "drops the segment when the worktree name equals the branch" {
  repo=$(make_repo "feature-x" "feature-x")
  run_plugin "$repo"
  [ -z "$output" ]
}

@test "outputs the name when not in a git repo" {
  mkdir -p "$TEST_DIR/plain"
  run env CLAUDE_PROJECT_DIR="$TEST_DIR/plain" CLAUDE_CURRENT_DIR="$TEST_DIR/plain" "$PLUGIN"
  [ "$output" = "plain" ]
}

@test "outputs . when project_dir is empty" {
  run env CLAUDE_PROJECT_DIR="" CLAUDE_CURRENT_DIR="" "$PLUGIN"
  [ "$output" = "." ]
}

@test "truncates a name longer than 40 chars to 37 + ..." {
  name="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" # 50 a's
  repo=$(make_repo "$name" "some-branch")
  run_plugin "$repo"
  expected="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa..." # 37 a's + ...
  [ "$output" = "$expected" ]
  [ "${#output}" -eq 40 ]
}

@test "does not truncate a name of exactly 40 chars" {
  name="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" # 40 a's
  repo=$(make_repo "$name" "some-branch")
  run_plugin "$repo"
  [ "$output" = "$name" ]
  [ "${#output}" -eq 40 ]
}
