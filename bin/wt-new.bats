#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

# Test suite for bin/wt-new (create a git worktree, then run the per-clone
# setup hook).
#
# Two contracts matter here and both are load-bearing for the shell wrapper:
#
#   1. stdout is EXACTLY the new worktree path, nothing else. `new_wt()` does
#      `cd "$(wt-new ...)"`, so a stray line of git or hook chatter on stdout
#      would cd somewhere nonsensical. Everything else — git's own output, the
#      hook's stdout AND stderr — goes to stderr.
#   2. A failing hook does not roll back the worktree. The worktree stays, the
#      path is still printed (so the caller lands in it), the failure is loud,
#      and the exit status is nonzero.

WT_NEW="$BATS_TEST_DIRNAME/wt-new"

setup() {
  # Resolved tmpdir. On macOS $BATS_TEST_TMPDIR lives under /var, a symlink to
  # /private/var, and `git rev-parse --show-toplevel` reports the resolved
  # path — so the destination wt-new derives is a sibling of the REAL location.
  # Compare against the resolved path or every path assertion here is off by a
  # symlink.
  TMP="$(cd "$BATS_TEST_TMPDIR" && pwd -P)"

  # Isolate from the real user's git config — a global `wt.setup` would
  # otherwise fire in every one of these tests.
  export GIT_CONFIG_GLOBAL="$TMP/gitconfig-global"
  export GIT_CONFIG_SYSTEM=/dev/null
  : > "$GIT_CONFIG_GLOBAL"

  # The script's bottom guard skips main when sourced.
  source "$WT_NEW"

  REPO="$TMP/main"
  git init -q -b main "$REPO"
  git -C "$REPO" config user.email t@example.com
  git -C "$REPO" config user.name Tester
  printf 'hello\n' > "$REPO/file.txt"
  git -C "$REPO" add file.txt
  git -C "$REPO" commit -qm "init commit"

  cd "$REPO"
}

# ── wt_dst_path ──────────────────────────────────────────────────────────────
# The new worktree is a sibling of the SOURCE WORKTREE's root, not of $PWD.
# The old .zshrc new_wt used a literal "../$br", which only did the right thing
# when you happened to be standing in the repo root.

@test "wt_dst_path puts the worktree beside the source worktree root" {
  run wt_dst_path "/Users/x/dev/fresh-editor" "my-branch"
  [ "$status" -eq 0 ]
  [[ "$output" == "/Users/x/dev/my-branch" ]]
}

@test "wt_dst_path is independent of cwd" {
  mkdir -p "$REPO/deep/nested"
  cd "$REPO/deep/nested"
  run wt_dst_path "$REPO" "feature"
  [ "$status" -eq 0 ]
  [[ "$output" == "$TMP/feature" ]]
}

# ── wt_default_branch ────────────────────────────────────────────────────────

@test "wt_default_branch prefers origin/HEAD" {
  git remote add origin "$REPO"
  git update-ref refs/remotes/origin/trunk HEAD
  git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/trunk
  run wt_default_branch
  [ "$status" -eq 0 ]
  [[ "$output" == "trunk" ]]
}

@test "wt_default_branch falls back to a local main" {
  run wt_default_branch
  [ "$status" -eq 0 ]
  [[ "$output" == "main" ]]
}

@test "wt_default_branch falls back to master" {
  git branch -m main master
  run wt_default_branch
  [ "$status" -eq 0 ]
  [[ "$output" == "master" ]]
}

@test "wt_default_branch fails when there is no main, master, or origin/HEAD" {
  git branch -m main something-else
  run wt_default_branch
  [ "$status" -ne 0 ]
}

# ── usage ────────────────────────────────────────────────────────────────────

@test "wt_new_main with no branch exits nonzero and says so on stderr" {
  run --separate-stderr wt_new_main
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"usage"* ]]
  [ -z "$output" ]
}

@test "wt_new_main refuses when the destination already exists" {
  mkdir -p "$TMP/taken"
  run --separate-stderr wt_new_main taken
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"taken"* ]]
}

# ── worktree creation ────────────────────────────────────────────────────────

@test "creates a worktree for an existing branch and prints only its path" {
  git branch existing
  run --separate-stderr wt_new_main existing
  [ "$status" -eq 0 ]
  [ "$output" = "$TMP/existing" ]
  [ -f "$TMP/existing/file.txt" ]
}

@test "creates a new branch off the default branch when it does not exist" {
  run --separate-stderr wt_new_main brand-new
  [ "$status" -eq 0 ]
  [ "$output" = "$TMP/brand-new" ]
  run git -C "$TMP/brand-new" rev-parse --abbrev-ref HEAD
  [[ "$output" == "brand-new" ]]
}

@test "checks out a branch that exists only on origin, tracking it" {
  # The old .zshrc new_wt tested for refs/remotes/origin/$br and then ran
  # `git worktree add <path> <branch>` — which requires a LOCAL branch, so this
  # case died with "fatal: invalid reference". Verified against the original
  # before changing it: both failed identically with exit 128.
  # A real remote, so refs/remotes/origin/* are genuine remote-tracking refs.
  # The URL is never contacted. Faking the ref with update-ref alone is not a
  # realistic repo: git rejects --track against a ref with no remote config.
  git remote add origin "$TMP/origin.git"
  git update-ref refs/remotes/origin/from-origin HEAD
  run --separate-stderr wt_new_main from-origin
  [ "$status" -eq 0 ]
  [ "$output" = "$TMP/from-origin" ]
  run git -C "$TMP/from-origin" rev-parse --abbrev-ref HEAD
  [[ "$output" == "from-origin" ]]
}

@test "a branch only on origin gets a local branch tracking it" {
  git remote add origin "$TMP/origin.git"
  git update-ref refs/remotes/origin/tracked HEAD
  run --separate-stderr wt_new_main tracked
  [ "$status" -eq 0 ]
  run git -C "$TMP/tracked" config --get branch.tracked.merge
  [[ "$output" == "refs/heads/tracked" ]]
}

@test "a local branch is preferred over a same-named origin branch" {
  git branch local-wins
  git update-ref refs/remotes/origin/local-wins HEAD
  run --separate-stderr wt_new_main local-wins
  [ "$status" -eq 0 ]
  # Checked out the local branch, so no tracking config was created for it.
  run git -C "$TMP/local-wins" rev-parse --abbrev-ref HEAD
  [[ "$output" == "local-wins" ]]
}

@test "git's own chatter goes to stderr, never stdout" {
  run --separate-stderr wt_new_main noisy
  [ "$status" -eq 0 ]
  # Exactly one line on stdout: the path.
  [ "$(printf '%s' "$output" | grep -c '')" -eq 1 ]
  [[ "$stderr" == *"noisy"* ]]
}

@test "works from a subdirectory of the repo" {
  mkdir -p "$REPO/deep/nested"
  cd "$REPO/deep/nested"
  run --separate-stderr wt_new_main from-deep
  [ "$status" -eq 0 ]
  [ "$output" = "$TMP/from-deep" ]
}

# ── the setup hook ───────────────────────────────────────────────────────────

@test "runs \$GIT_COMMON_DIR/worktree-setup when it is executable" {
  cat > "$REPO/.git/worktree-setup" <<'EOF'
#!/usr/bin/env bash
printf 'src=%s dst=%s branch=%s\n' "$WT_SRC" "$WT_DST" "$WT_BRANCH" > "$WT_DST/hook-ran"
EOF
  chmod +x "$REPO/.git/worktree-setup"

  run --separate-stderr wt_new_main hooked
  [ "$status" -eq 0 ]
  [ -f "$TMP/hooked/hook-ran" ]
  run cat "$TMP/hooked/hook-ran"
  [[ "$output" == "src=$REPO dst=$TMP/hooked branch=hooked" ]]
}

@test "skips a worktree-setup file that is not executable" {
  printf '#!/usr/bin/env bash\ntouch "$WT_DST/should-not-exist"\n' \
    > "$REPO/.git/worktree-setup"
  run --separate-stderr wt_new_main unexec
  [ "$status" -eq 0 ]
  [ ! -e "$TMP/unexec/should-not-exist" ]
}

@test "runs the wt.setup config command when there is no hook script" {
  git config wt.setup 'printf "%s\n" "$WT_BRANCH" > "$WT_DST/from-config"'
  run --separate-stderr wt_new_main configured
  [ "$status" -eq 0 ]
  [ -f "$TMP/configured/from-config" ]
  run cat "$TMP/configured/from-config"
  [[ "$output" == "configured" ]]
}

@test "the hook script wins over the wt.setup config command" {
  cat > "$REPO/.git/worktree-setup" <<'EOF'
#!/usr/bin/env bash
touch "$WT_DST/from-script"
EOF
  chmod +x "$REPO/.git/worktree-setup"
  git config wt.setup 'touch "$WT_DST/from-config"'

  run --separate-stderr wt_new_main both
  [ "$status" -eq 0 ]
  [ -e "$TMP/both/from-script" ]
  [ ! -e "$TMP/both/from-config" ]
}

@test "the hook runs with cwd inside the new worktree" {
  git config wt.setup 'pwd > "$WT_DST/hook-cwd"'
  run --separate-stderr wt_new_main cwd-check
  [ "$status" -eq 0 ]
  run cat "$TMP/cwd-check/hook-cwd"
  [[ "$output" == "$TMP/cwd-check" ]]
}

@test "announces that a hook ran, on stderr" {
  git config wt.setup 'true'
  run --separate-stderr wt_new_main announced
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"wt.setup"* ]]
  [ "$output" = "$TMP/announced" ]
}

@test "hook stdout is relayed to stderr, keeping stdout to just the path" {
  git config wt.setup 'echo "cloned 4.2G of target/"'
  run --separate-stderr wt_new_main relayed
  [ "$status" -eq 0 ]
  [ "$output" = "$TMP/relayed" ]
  [[ "$stderr" == *"cloned 4.2G of target/"* ]]
}

@test "hook stderr is not swallowed" {
  git config wt.setup 'echo "cp: no space left" >&2'
  run --separate-stderr wt_new_main noisy-hook
  [[ "$stderr" == *"cp: no space left"* ]]
}

# ── hook failure: keep the worktree, print the path, fail loudly ─────────────

@test "a failing hook leaves the worktree in place and still prints the path" {
  git config wt.setup 'exit 3'
  run --separate-stderr wt_new_main failing
  [ "$status" -ne 0 ]
  [ "$output" = "$TMP/failing" ]
  [ -d "$TMP/failing" ]
  [ -f "$TMP/failing/file.txt" ]
  [[ "$stderr" == *"3"* ]]
}

@test "a failing hook script is reported loudly" {
  cat > "$REPO/.git/worktree-setup" <<'EOF'
#!/usr/bin/env bash
echo "boom" >&2
exit 1
EOF
  chmod +x "$REPO/.git/worktree-setup"
  run --separate-stderr wt_new_main failing-script
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"boom"* ]]
  [[ "$stderr" == *"worktree-setup"* ]]
  [ "$output" = "$TMP/failing-script" ]
}

# ── no hook at all ───────────────────────────────────────────────────────────

@test "no hook configured is a silent success" {
  run --separate-stderr wt_new_main plain
  [ "$status" -eq 0 ]
  [ "$output" = "$TMP/plain" ]
  [[ "$stderr" != *"wt.setup"* ]]
}

# ── hooks are inherited by worktrees ─────────────────────────────────────────
# Both mechanisms live in the git COMMON dir, so a worktree created from
# another worktree still finds them. This is the whole reason for using
# --git-common-dir instead of --git-dir.

@test "a worktree created from another worktree still finds the hook" {
  git config wt.setup 'touch "$WT_DST/inherited"'
  run --separate-stderr wt_new_main first
  [ "$status" -eq 0 ]

  cd "$TMP/first"
  run --separate-stderr wt_new_main second
  [ "$status" -eq 0 ]
  [ "$output" = "$TMP/second" ]
  [ -e "$TMP/second/inherited" ]
}

@test "a hook script is found from a linked worktree too" {
  cat > "$REPO/.git/worktree-setup" <<'EOF'
#!/usr/bin/env bash
touch "$WT_DST/inherited-script"
EOF
  chmod +x "$REPO/.git/worktree-setup"

  run --separate-stderr wt_new_main one
  [ "$status" -eq 0 ]
  cd "$TMP/one"
  run --separate-stderr wt_new_main two
  [ "$status" -eq 0 ]
  [ -e "$TMP/two/inherited-script" ]
}

# ── WT_SRC is the worktree you ran from ──────────────────────────────────────

@test "WT_SRC is the source worktree root, not the main repo" {
  git config wt.setup 'printf "%s\n" "$WT_SRC" > "$WT_DST/src"'
  run --separate-stderr wt_new_main src-a
  [ "$status" -eq 0 ]

  cd "$TMP/src-a"
  run --separate-stderr wt_new_main src-b
  [ "$status" -eq 0 ]
  run cat "$TMP/src-b/src"
  [[ "$output" == "$TMP/src-a" ]]
}

# ── not in a repo ────────────────────────────────────────────────────────────

@test "outside a git repo it fails with a clear message" {
  mkdir -p "$TMP/not-a-repo"
  cd "$TMP/not-a-repo"
  run --separate-stderr wt_new_main anything
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}
