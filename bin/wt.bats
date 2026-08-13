#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

# Test suite for bin/wt (fzf worktree selector), migrated from
# brain/git/worktrees.sh.
#
# The parse is the part worth pinning. `git worktree list --porcelain` emits
# variable-length blocks, and the super pipeline pairs the "worktree" and
# "branch" lines by line COUNT — so any block that doesn't contribute exactly
# one of each desynchronizes every worktree after it. Detached and bare
# worktrees are exactly those blocks. Several tests below are regressions for
# observed corruption, not hypotheticals.
#
# As with wt-new, stdout is EXACTLY the selected path so `wt()` can cd to it.

WT="$BATS_TEST_DIRNAME/wt"

setup() {
  TMP="$(cd "$BATS_TEST_TMPDIR" && pwd -P)"
  source "$WT"
}

# Porcelain for: main repo on main, a detached worktree IN THE MIDDLE, and a
# normal branch worktree after it.
porcelain_with_detached_middle() {
  cat <<'EOF'
worktree /x/r
HEAD abc123
branch refs/heads/main

worktree /x/d
HEAD abc123
detached

worktree /x/b
HEAD abc123
branch refs/heads/feat
EOF
}

# ── wt_parse_worktrees ───────────────────────────────────────────────────────

@test "parses dir and branch for ordinary worktrees" {
  run bash -c 'source "$1"; printf "%s\n" "worktree /x/r" "HEAD abc" "branch refs/heads/main" | wt_parse_worktrees' _ "$WT"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"dir":"/x/r"'* ]]
  [[ "$output" == *'"branch":"main"'* ]]
  [[ "$output" == *'"leaf":"r"'* ]]
}

@test "a detached worktree gets a readable branch label, not an error value" {
  run bash -c 'source "$1"; printf "%s\n" "worktree /x/d" "HEAD abc" "detached" | wt_parse_worktrees' _ "$WT"
  [ "$status" -eq 0 ]
  [[ "$output" == *'(detached)'* ]]
  [[ "$output" != *'error'* ]]
}

@test "a bare worktree gets a readable branch label" {
  run bash -c 'source "$1"; printf "%s\n" "worktree /x/bare" "HEAD abc" "bare" | wt_parse_worktrees' _ "$WT"
  [ "$status" -eq 0 ]
  [[ "$output" == *'(bare)'* ]]
  [[ "$output" != *'error'* ]]
}

@test "a detached worktree in the middle does not desync the ones after it" {
  # Regression: with count-based pairing and no handling for the odd block,
  # /x/b was emitted with dir:null and became unreachable from the selector.
  run bash -c 'source "$1"; wt_parse_worktrees' _ "$WT" <<< "$(porcelain_with_detached_middle)"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c .)" -eq 3 ]
  [[ "$output" == *'"dir":"/x/b","branch":"feat"'* ]]
  [[ "$output" != *'null'* ]]
}

@test "preserves the order git reported" {
  run bash -c 'source "$1"; wt_parse_worktrees' _ "$WT" <<< "$(porcelain_with_detached_middle)"
  [ "$status" -eq 0 ]
  [[ "$(printf '%s\n' "$output" | sed -n 1p)" == *'/x/r'* ]]
  [[ "$(printf '%s\n' "$output" | sed -n 2p)" == *'/x/d'* ]]
  [[ "$(printf '%s\n' "$output" | sed -n 3p)" == *'/x/b'* ]]
}

@test "handles paths containing spaces" {
  run bash -c 'source "$1"; printf "%s\n" "worktree /x/my project" "HEAD abc" "branch refs/heads/main" | wt_parse_worktrees' _ "$WT"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"dir":"/x/my project"'* ]]
  [[ "$output" == *'"leaf":"my project"'* ]]
}

@test "a branch literally named 'detached' is not mangled into the placeholder" {
  run bash -c 'source "$1"; printf "%s\n" "worktree /x/w" "HEAD abc" "branch refs/heads/detached" | wt_parse_worktrees' _ "$WT"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"branch":"detached"'* ]]
  [[ "$output" != *'(detached)'* ]]
}

@test "keeps slashes in nested branch names" {
  run bash -c 'source "$1"; printf "%s\n" "worktree /x/w" "HEAD abc" "branch refs/heads/feature/nested-name" | wt_parse_worktrees' _ "$WT"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"branch":"feature/nested-name"'* ]]
}

@test "ignores locked and prunable annotations" {
  run bash -c 'source "$1"; printf "%s\n" "worktree /x/w" "HEAD abc" "branch refs/heads/main" "locked" "prunable gitdir file points nowhere" | wt_parse_worktrees' _ "$WT"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c .)" -eq 1 ]
  [[ "$output" == *'"branch":"main"'* ]]
}

# ── wt_display_lines ─────────────────────────────────────────────────────────
# "<dir>\t<leaf> [<branch>]" — fzf shows field 2+, the path rides along hidden
# in field 1 so duplicate leaf names still resolve to the right worktree.

@test "display lines are dir TAB 'leaf [branch]'" {
  run bash -c 'source "$1"; wt_parse_worktrees | wt_display_lines' _ "$WT" \
    <<< "$(porcelain_with_detached_middle)"
  [ "$status" -eq 0 ]
  [[ "$(printf '%s\n' "$output" | sed -n 1p)" == $'/x/r\tr [main]' ]]
  [[ "$(printf '%s\n' "$output" | sed -n 2p)" == $'/x/d\td [(detached)]' ]]
  [[ "$(printf '%s\n' "$output" | sed -n 3p)" == $'/x/b\tb [feat]' ]]
}

# ── wt_main ──────────────────────────────────────────────────────────────────
# wt_select is the fzf seam; tests replace it so nothing interactive runs.

@test "prints the selected worktree path, and nothing else, on stdout" {
  mkdir -p "$TMP/chosen"
  wt_select() { printf '%s\t%s\n' "$TMP/chosen" "chosen [main]"; }
  wt_worktree_porcelain() { printf 'worktree %s\nHEAD abc\nbranch refs/heads/main\n' "$TMP/chosen"; }
  run --separate-stderr wt_main
  [ "$status" -eq 0 ]
  [ "$output" = "$TMP/chosen" ]
}

@test "resolves the right worktree when two share a leaf name" {
  mkdir -p "$TMP/a/dup" "$TMP/b/dup"
  wt_worktree_porcelain() {
    printf 'worktree %s\nHEAD abc\nbranch refs/heads/one\n\nworktree %s\nHEAD abc\nbranch refs/heads/two\n' \
      "$TMP/a/dup" "$TMP/b/dup"
  }
  # Pick the SECOND line — under leaf-name matching this returned the first.
  wt_select() { sed -n 2p; }
  run --separate-stderr wt_main
  [ "$status" -eq 0 ]
  [ "$output" = "$TMP/b/dup" ]
}

@test "cancelling the selector is a quiet success with no output" {
  wt_worktree_porcelain() { printf 'worktree /x/r\nHEAD abc\nbranch refs/heads/main\n'; }
  wt_select() { return 130; }   # fzf's ESC / Ctrl-C status
  run --separate-stderr wt_main
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "an empty selection is a quiet success with no output" {
  wt_worktree_porcelain() { printf 'worktree /x/r\nHEAD abc\nbranch refs/heads/main\n'; }
  wt_select() { printf ''; }
  run --separate-stderr wt_main
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a selected path that no longer exists fails loudly" {
  wt_worktree_porcelain() { printf 'worktree /x/gone\nHEAD abc\nbranch refs/heads/main\n'; }
  wt_select() { printf '%s\t%s\n' "/x/gone" "gone [main]"; }
  run --separate-stderr wt_main
  [ "$status" -ne 0 ]
  [ -z "$output" ]
  [[ "$stderr" == *"/x/gone"* ]]
}

@test "outside a git repo it fails and prints nothing on stdout" {
  cd "$TMP"
  run --separate-stderr wt_main
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}
