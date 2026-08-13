#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

# Test suite for shell/rig.zsh.
#
# Run under bats (bash), but every assertion drives a real `zsh -f` so the
# behaviour tested is zsh's, not bash's.
#
# The case that matters: zsh expands aliases at PARSE time, so a live alias
# named `wt` turns the later `wt() { ... }` into a syntax error rather than a
# redefinition. That is not hypothetical — it is exactly what happens when you
# re-source .zshrc from a shell that still has the old `alias wt=...` loaded,
# which is the normal way anyone would try this file out. rig.zsh has to be
# sourceable into a shell that already has the definitions it is replacing.

RIG="$BATS_TEST_DIRNAME/rig.zsh"

# zsh -c exits 0 even on a parse error inside a sourced file, so status alone
# proves nothing. Assert on what was written to stderr.
source_rig() {
  run zsh -f -c "$1"
  [[ "$output" != *"parse error"* ]] || return 1
  [[ "$output" != *"defining function based on alias"* ]] || return 1
}

@test "sources cleanly in a virgin shell" {
  source_rig "source '$RIG'; echo ok"
  [[ "$output" == *"ok"* ]]
}

@test "defines new_wt and wt as functions" {
  source_rig "source '$RIG'; type new_wt; type wt"
  [[ "$output" == *"new_wt is a shell function"* ]]
  [[ "$output" == *"wt is a shell function"* ]]
}

@test "sources cleanly when a conflicting wt alias is live" {
  # Regression: re-sourcing .zshrc with the old brain-era alias still loaded
  # failed with "defining function based on alias \`wt'" + a parse error.
  source_rig "alias wt='source /some/brain/worktrees.sh'; source '$RIG'; echo ok"
  [[ "$output" == *"ok"* ]]
}

@test "the wt function wins over a pre-existing wt alias" {
  source_rig "alias wt='echo ALIAS'; source '$RIG'; type wt"
  [[ "$output" == *"wt is a shell function"* ]]
  [[ "$output" != *"alias"* ]]
}

@test "sources cleanly when a conflicting new_wt alias is live" {
  source_rig "alias new_wt='echo ALIAS'; source '$RIG'; type new_wt"
  [[ "$output" == *"new_wt is a shell function"* ]]
}

@test "is idempotent — sourcing twice is clean" {
  source_rig "source '$RIG'; source '$RIG'; type wt"
  [[ "$output" == *"wt is a shell function"* ]]
}

@test "does not clobber an unrelated alias" {
  source_rig "alias gs='git status'; source '$RIG'; alias gs"
  [[ "$output" == *"git status"* ]]
}

@test "new_wt reports the failure status of wt-new but still cds" {
  # A wt.setup hook that fails leaves a usable worktree; new_wt should land you
  # in it AND surface the nonzero status.
  local fake="$BATS_TEST_TMPDIR/fakebin"
  mkdir -p "$fake" "$BATS_TEST_TMPDIR/dest"
  cat > "$fake/wt-new" <<EOF
#!/bin/sh
echo "$BATS_TEST_TMPDIR/dest"
exit 7
EOF
  chmod +x "$fake/wt-new"
  source_rig "PATH='$fake:\$PATH'; source '$RIG'; new_wt br; echo \"rc=\$?\"; pwd"
  [[ "$output" == *"rc=7"* ]]
  [[ "$output" == *"$BATS_TEST_TMPDIR/dest"* ]]
}

@test "wt cds to the path its command prints" {
  local fake="$BATS_TEST_TMPDIR/fakebin"
  mkdir -p "$fake" "$BATS_TEST_TMPDIR/picked"
  cat > "$fake/wt" <<EOF
#!/bin/sh
echo "$BATS_TEST_TMPDIR/picked"
EOF
  chmod +x "$fake/wt"
  source_rig "PATH='$fake:\$PATH'; source '$RIG'; wt; pwd"
  [[ "$output" == *"$BATS_TEST_TMPDIR/picked"* ]]
}

@test "a cancelled wt leaves the shell where it was" {
  local fake="$BATS_TEST_TMPDIR/fakebin"
  mkdir -p "$fake"
  printf '#!/bin/sh\nexit 0\n' > "$fake/wt"
  chmod +x "$fake/wt"
  source_rig "PATH='$fake:\$PATH'; cd /tmp; source '$RIG'; wt; echo \"rc=\$?\"; pwd"
  [[ "$output" == *"rc=0"* ]]
  [[ "$output" == *"/tmp"* ]]
}
