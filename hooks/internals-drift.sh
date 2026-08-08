#!/usr/bin/env bash
#
# internals-drift - warn when Claude Code's version moves past the one
#                   claude-rig's internals were last verified against
#
# Fires on SessionStart.
#
# claude-rig depends on several things Claude Code does not expose as an API:
# the session registry (~/.claude/sessions/<pid>.json), the transcript .jsonl
# schema, the projects-directory path encoding, and the peer messaging protocol.
# None of that is contract; all of it can change in a point release.
#
# Claude Code upgrades itself and never runs install.sh, so a version bump is
# the only reliable moment to say "re-check the assumptions". This hook is that
# moment. It does not verify anything itself — it points at the suite that does:
#
#   bats bin/claude-contract.bats
#
# See docs/internals-contract.md for what is being asserted and why.
#
# Deliberately NOT `set -e`: a hook that fails must never take session startup
# down with it. Every unresolvable case exits 0 in silence.

set -uo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
VERIFIED_FILE="${CLAUDE_RIG_VERIFIED_FILE:-$REPO_DIR/docs/verified-against}"

# Resolve the build this session is RUNNING.
#
# Precedence matches bin/claude-src, with one addition. CLAUDE_SRC_BINARY is the
# explicit override (tests, and anyone pointing at a specific build).
# CLAUDE_CODE_EXECPATH is next and matters most in practice: Claude Code stages
# an upgrade by repointing the launcher symlink while existing sessions keep
# running the old build, so the symlink can already name a version this session
# is not executing. Falling back to the symlink is a last resort.
resolve_running_binary() {
  if [[ -n "${CLAUDE_SRC_BINARY:-}" && -f "${CLAUDE_SRC_BINARY}" ]]; then
    printf '%s\n' "$CLAUDE_SRC_BINARY"
    return 0
  fi

  if [[ -n "${CLAUDE_CODE_EXECPATH:-}" && -f "${CLAUDE_CODE_EXECPATH}" ]]; then
    printf '%s\n' "$CLAUDE_CODE_EXECPATH"
    return 0
  fi

  local launcher
  launcher=$(command -v claude 2>/dev/null) || return 1
  # The launcher is a symlink into versions/<version>; resolve it.
  local target
  target=$(readlink "$launcher" 2>/dev/null) || target="$launcher"
  [[ -f "$target" ]] || return 1
  printf '%s\n' "$target"
}

main() {
  [[ -r "$VERIFIED_FILE" ]] || exit 0

  local verified
  verified=$(tr -d '[:space:]' < "$VERIFIED_FILE" 2>/dev/null) || exit 0
  [[ -n "$verified" ]] || exit 0

  local binary
  binary=$(resolve_running_binary) || exit 0

  # The binary's filename IS its version. Anything else (a "latest" symlink, a
  # dev build) is not something we can compare, so stay quiet rather than nag.
  local running
  running=$(basename -- "$binary")
  [[ "$running" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]] || exit 0

  [[ "$running" == "$verified" ]] && exit 0

  cat <<EOF
⚠ claude-rig: internals verified against Claude Code $verified, running $running.

  claude-rig reads Claude Code internals that are not a supported API (session
  registry, transcript schema, peer messaging). A version change is the cue to
  re-check them:

      bats $REPO_DIR/bin/claude-contract.bats

  What is being asserted, and what to do when one fails:
      $REPO_DIR/docs/internals-contract.md
EOF
  exit 0
}

main "$@"
