#!/usr/bin/env bats

# Test suite for the 1.20-git plugin.
#
# Renders "git: <branch><status-flags>". The branch name is truncated to 40
# chars (37 + "...").

PLUGIN="$BATS_TEST_DIRNAME/plugins.d/1.20-git"

setup() {
  TEST_DIR="$(mktemp -d "$TMPDIR/git-test.XXXXXX")"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# Make a git repo on branch <branch> (unborn, no commits), return its path.
make_repo() {
  local branch=$1
  local repo="$TEST_DIR/repo"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" symbolic-ref HEAD "refs/heads/$branch"
  printf '%s' "$repo"
}

run_plugin() {
  local repo=$1
  run env CLAUDE_CURRENT_DIR="$repo" "$PLUGIN"
}

@test "outputs nothing outside a git repo" {
  mkdir -p "$TEST_DIR/plain"
  run env CLAUDE_CURRENT_DIR="$TEST_DIR/plain" "$PLUGIN"
  [ -z "$output" ]
}

@test "renders the branch name" {
  repo=$(make_repo "feature-x")
  run_plugin "$repo"
  [ "$output" = "git: feature-x" ]
}

@test "truncates a branch longer than 40 chars to 37 + ..." {
  branch="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" # 50 a's
  repo=$(make_repo "$branch")
  run_plugin "$repo"
  expected="git: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa..." # 37 a's + ...
  [ "$output" = "$expected" ]
}

@test "does not truncate a branch of exactly 40 chars" {
  branch="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" # 40 a's
  repo=$(make_repo "$branch")
  run_plugin "$repo"
  [ "$output" = "git: $branch" ]
}
