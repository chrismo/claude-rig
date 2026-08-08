#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

# use-dedicated-tools.sh is DISABLED.
#
# abd6962 short-circuited it with an early `exit 0`, deferring to Claude's
# auto-mode, and left the ~160 lines of check logic in place with a documented
# way back: delete the early-exit block.
#
# The 67 tests that used to live here exercised that unreachable logic. All of
# them were stale, not just the 45 that went red — the 22 "allow" cases passed
# vacuously, because a hook that allows everything allows those too. A suite
# that cannot fail for the right reason is worse than no suite: it reads as
# coverage from the outside.
#
# They are not gone, only unstaged from the working tree. To get them back when
# re-enabling the hook:
#
#     git show 34c116d:hooks/use-dedicated-tools.bats > hooks/use-dedicated-tools.bats
#
# What remains is a tripwire. It asserts the hook is disabled, so that deleting
# the early-exit block turns this file red and points at the command above,
# rather than silently re-enabling checks with no tests behind them.

HOOK="$BATS_TEST_DIRNAME/use-dedicated-tools.sh"

@test "the hook is disabled: it allows a command the checks used to deny" {
  # `cat <file>` is what the old suite denied in favour of the Read tool. If the
  # hook is live again, this is exactly what it would object to.
  run bash -c "printf '%s' '{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"cat /etc/hosts\"}}' | '$HOOK'"
  [ "$status" -eq 0 ]
  [[ "$output" != *"permissionDecision"* ]] || {
    echo "The hook emitted a permission decision, so it is no longer disabled." >&2
    echo "Restore the real suite:" >&2
    echo "  git show 34c116d:hooks/use-dedicated-tools.bats > hooks/use-dedicated-tools.bats" >&2
    return 1; }
}

@test "the hook stays silent rather than emitting JSON" {
  run bash -c "printf '%s' '{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"rm -rf /tmp/x\"}}' | '$HOOK'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "the early-exit block is still present in the hook" {
  # Cheaper and more direct than inferring it from behaviour: if this line goes,
  # the checks are live again.
  run grep -c '^exit 0$' "$HOOK"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}
