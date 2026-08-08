#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

# The internals contract.
#
# claude-rig reads several things Claude Code does not expose as a supported
# API. None of it is guaranteed to survive a point release. This suite asserts
# that each load-bearing assumption still holds against the CURRENTLY INSTALLED
# build, so a breaking change surfaces here instead of as a mysteriously empty
# claude-tabs or a claude-pod that renders nothing.
#
# Each test is prefixed with an assumption ID (A1, B2, …). Those IDs are the
# join to docs/internals-contract.md, which says what each one is for, who
# depends on it, and what to do when it fails. Keep them in sync: an ID here
# with no entry there is a dead end for whoever hits the failure.
#
# Run it after any Claude Code version change:
#     bats bin/claude-contract.bats
# hooks/internals-drift.sh nags you to when the version moves.
#
# Two deliberate limits:
#   - Anchors are plain string literals. Identifiers are re-mangled every build
#     (see docs/reading-the-claude-binary.md), so asserting on `tfa` would fail
#     for a rename that broke nothing.
#   - Tests that need live artifacts (a running session, a transcript) `skip`
#     when none exist rather than fail. A machine with no sessions should be
#     able to run this suite green.

SRC="$BATS_TEST_DIRNAME/claude-src"
SESSIONS_DIR="${CLAUDE_SESSIONS_META_DIR:-$HOME/.claude/sessions}"
PROJECTS_DIR="${CLAUDE_PROJECTS_DIR:-$HOME/.claude/projects}"

# Assert a literal appears in the installed bundle. claude-src exits 0 on a
# miss (by design), so presence is judged from the output, not the status.
assert_anchor() {
  local pattern="$1" out
  out=$("$SRC" "$pattern" 0 200 2>&1)
  if [[ "$out" == *"no match for"* || -z "$out" ]]; then
    echo "MISSING ANCHOR: '$pattern'" >&2
    echo "$out" >&2
    return 1
  fi
}

# --- A: the peer messaging mechanism -------------------------------------

@test "A1: the uds-messaging subsystem still exists" {
  assert_anchor 'uds-messaging'
}

@test "A2: sessions still advertise a socket via messagingSocketPath" {
  assert_anchor 'messagingSocketPath'
}

@test "A3: a session still learns its own address from the environment" {
  assert_anchor 'CLAUDE_CODE_MESSAGING_SOCKET'
}

@test "A4: the wire format is still newline-delimited JSON on a unix socket" {
  # The binary logs its own injection recipe; if this text is gone, the
  # hand-written socket writes in docs/inter-claude-protocol.md are suspect.
  assert_anchor 'Inject messages'
}

@test "A5: refs are still a truncated sha256" {
  # docs/inter-claude-protocol.md 1: sha256("session:"+sock), cut to 12, then
  # to 6 by the roster. If this changes, every computed ref is wrong.
  assert_anchor 'digest("hex").slice(0,12)'
}

@test "A6: bare-name sends are still gated by pins" {
  assert_anchor 'sendMessagePins'
}

@test "A7: the socket directory is still cc-socks" {
  assert_anchor 'cc-socks'
}

# --- B: the session registry ---------------------------------------------

@test "B1: the registry directory exists" {
  [ -d "$SESSIONS_DIR" ] || skip "no registry at $SESSIONS_DIR"
}

@test "B2: registry files are named <pid>.json" {
  [ -d "$SESSIONS_DIR" ] || skip "no registry at $SESSIONS_DIR"
  local found=0 f
  for f in "$SESSIONS_DIR"/*.json; do
    [ -e "$f" ] || continue
    found=1
    [[ "$(basename "$f")" =~ ^[0-9]+\.json$ ]] || {
      echo "unexpected registry filename: $f" >&2; return 1; }
  done
  [ "$found" -eq 1 ] || skip "no live sessions to check"
}

@test "B3: registry records still carry the fields claude-tabs and claude-pod read" {
  [ -d "$SESSIONS_DIR" ] || skip "no registry at $SESSIONS_DIR"
  local f
  f=$(ls -t "$SESSIONS_DIR"/*.json 2>/dev/null | head -1) || true
  [ -n "$f" ] || skip "no live sessions to check"

  run python3 -c "
import json,sys
d=json.load(open('$f'))
need=['pid','sessionId','cwd','kind','status','startedAt']
missing=[k for k in need if k not in d]
print('missing:', missing)
sys.exit(1 if missing else 0)
"
  [ "$status" -eq 0 ] || { echo "$output" >&2; return 1; }
}

@test "B4: kind and status still use the documented vocabularies" {
  [ -d "$SESSIONS_DIR" ] || skip "no registry at $SESSIONS_DIR"
  local f
  f=$(ls -t "$SESSIONS_DIR"/*.json 2>/dev/null | head -1) || true
  [ -n "$f" ] || skip "no live sessions to check"

  run python3 -c "
import json,sys
d=json.load(open('$f'))
kinds={'interactive','bg','daemon','daemon-worker'}
stats={'busy','shell','idle','waiting'}
bad=[]
if d.get('kind') not in kinds: bad.append(('kind', d.get('kind')))
if d.get('status') not in stats: bad.append(('status', d.get('status')))
print('unexpected:', bad)
sys.exit(1 if bad else 0)
"
  [ "$status" -eq 0 ] || { echo "$output" >&2; return 1; }
}

# --- C: transcripts, the widest-blast-radius surface ---------------------

@test "C1: the projects directory encodes a worktree path as -Users-name-…" {
  [ -d "$PROJECTS_DIR" ] || skip "no projects dir at $PROJECTS_DIR"
  local d found=0
  for d in "$PROJECTS_DIR"/*/; do
    [ -d "$d" ] || continue
    [[ "$(basename "$d")" == -* ]] && { found=1; break; }
  done
  [ "$found" -eq 1 ] || {
    echo "no directory using the leading-dash path encoding" >&2; return 1; }
}

@test "C2: transcript lines are JSON objects carrying .type" {
  local f
  f=$(ls -t "$PROJECTS_DIR"/*/*.jsonl 2>/dev/null | head -1) || true
  [ -n "$f" ] || skip "no transcripts to check"

  run python3 -c "
import json,sys
ok=0
for i,line in enumerate(open('$f')):
    if i>200: break
    line=line.strip()
    if not line: continue
    try: rec=json.loads(line)
    except Exception: continue
    if isinstance(rec,dict) and 'type' in rec: ok+=1
print('records with .type:', ok)
sys.exit(0 if ok else 1)
"
  [ "$status" -eq 0 ] || { echo "$output" >&2; return 1; }
}

@test "C3: user and assistant records still nest content under .message" {
  local f
  f=$(ls -t "$PROJECTS_DIR"/*/*.jsonl 2>/dev/null | head -1) || true
  [ -n "$f" ] || skip "no transcripts to check"

  run python3 -c "
import json,sys
ok=0
for i,line in enumerate(open('$f')):
    if i>400: break
    line=line.strip()
    if not line: continue
    try: rec=json.loads(line)
    except Exception: continue
    if rec.get('type') in ('user','assistant') and isinstance(rec.get('message'),dict) \
       and 'content' in rec['message']: ok+=1
print('records with .message.content:', ok)
sys.exit(0 if ok else 1)
"
  [ "$status" -eq 0 ] || { echo "$output" >&2; return 1; }
}

# --- D: the stamp --------------------------------------------------------

@test "D1: verified-against matches the running build" {
  # Not a failure of any mechanism — a reminder that the assumptions above were
  # confirmed against a different build than the one running. Re-verify (the
  # behavioural checks in docs/internals-contract.md included), then bump
  # docs/verified-against.
  local stamp_file="$BATS_TEST_DIRNAME/../docs/verified-against"
  [ -r "$stamp_file" ] || skip "no docs/verified-against"
  local stamp running binary
  stamp=$(tr -d '[:space:]' < "$stamp_file")

  binary="${CLAUDE_CODE_EXECPATH:-}"
  [ -n "$binary" ] || binary=$(readlink "$(command -v claude)" 2>/dev/null) || true
  [ -n "$binary" ] || skip "cannot resolve the running build"
  running=$(basename "$binary")

  [ "$stamp" = "$running" ] || {
    echo "verified against $stamp, running $running — re-verify, then bump docs/verified-against" >&2
    return 1; }
}
