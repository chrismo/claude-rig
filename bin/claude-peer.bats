#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

# Test suite for bin/claude-peer.
#
# claude-peer lists and messages live Claude sessions from a shell, without
# going through Claude's own ListAgents/SendMessage tools. It reimplements what
# the binary does (see docs/inter-claude-protocol.md):
#
#   discovery  ~/.claude/sessions/<pid>.json, kill -0, then a connect probe
#   ref        sha256("session:" + messagingSocketPath), first 6 hex
#   send       one line of JSON on the peer's unix socket
#
# Tests build a fake registry in BATS_TEST_TMPDIR and stand up real unix
# sockets, so the probe and the send are exercised for real rather than mocked.

PEER="$BATS_TEST_DIRNAME/claude-peer"

setup() {
  export CLAUDE_SESSIONS_META_DIR="$BATS_TEST_TMPDIR/sessions"
  mkdir -p "$CLAUDE_SESSIONS_META_DIR"
  export CLAUDE_CODE_MESSAGING_SOCKET="$BATS_TEST_TMPDIR/self.sock"
  LISTENERS=()
}

teardown() {
  local p
  for p in "${LISTENERS[@]:-}"; do
    [ -n "$p" ] && kill "$p" 2>/dev/null
  done
  # bats fails a test whose teardown exits non-zero. With no listeners the loop
  # ends on a false [ -n "" ], which would fail every test that never started
  # one — for reasons having nothing to do with the test.
  return 0
}

# A registry record. Uses our own pid so the liveness check passes.
write_session() {
  local pid="$1" name="$2" sock="$3" kind="${4:-interactive}" status="${5:-idle}"
  local sockfield=""
  [ -n "$sock" ] && sockfield="\"messagingSocketPath\":\"$sock\","
  cat > "$CLAUDE_SESSIONS_META_DIR/$pid.json" <<EOF
{"pid":$pid,"sessionId":"11111111-2222-3333-4444-555555555555","cwd":"/tmp/wt",
 "name":"$name","kind":"$kind",$sockfield"status":"$status","startedAt":1786000000000}
EOF
}

# Real listener that appends whatever it receives to a file.
start_listener() {
  local sock="$1" out="$2"
  python3 -c "
import socket, os, sys, threading
p, out = sys.argv[1], sys.argv[2]
try: os.unlink(p)
except FileNotFoundError: pass
s = socket.socket(socket.AF_UNIX); s.bind(p); s.listen(4)
def serve():
    while True:
        c,_ = s.accept()
        d = c.recv(65536)
        if d:
            with open(out,'ab') as f: f.write(d)
        c.close()
threading.Thread(target=serve, daemon=True).start()
import time
time.sleep(30)
" "$sock" "$out" &
  LISTENERS+=($!)
  local i=0
  while [ ! -S "$sock" ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i+1)); done
}

expected_ref() {
  printf '%s' "session:$1" | shasum -a 256 | cut -c1-6
}

@test "--list shows a reachable peer with its name, pid and ref" {
  local sock="$BATS_TEST_TMPDIR/peer.sock"
  start_listener "$sock" "$BATS_TEST_TMPDIR/got"
  write_session $$ "alpha" "$sock"

  run "$PEER" --list
  [ "$status" -eq 0 ]
  [[ "$output" == *"alpha"* ]]
  [[ "$output" == *"$$"* ]]
  [[ "$output" == *"$(expected_ref "$sock")"* ]]
}

@test "--list excludes this session itself" {
  local sock="$BATS_TEST_TMPDIR/self.sock"
  start_listener "$sock" "$BATS_TEST_TMPDIR/got"
  write_session $$ "myself" "$sock"

  run "$PEER" --list
  [ "$status" -eq 0 ]
  [[ "$output" != *"myself"* ]]
}

@test "--list excludes sessions that never recorded a socket" {
  write_session $$ "socketless" ""

  run "$PEER" --list
  [ "$status" -eq 0 ]
  [[ "$output" != *"socketless"* ]]
}

@test "--list excludes a session whose socket no longer answers" {
  # A registry file can outlive the process: the socket path is recorded but
  # nothing is listening. Recorded path never implies reachable.
  local sock="$BATS_TEST_TMPDIR/stale.sock"
  python3 -c "
import socket
s = socket.socket(socket.AF_UNIX); s.bind('$sock'); s.close()"
  write_session $$ "ghost" "$sock"

  run "$PEER" --list
  [ "$status" -eq 0 ]
  [[ "$output" != *"ghost"* ]]
}

@test "--list skips registry entries whose pid is dead" {
  write_session 999999 "zombie" "$BATS_TEST_TMPDIR/zombie.sock"

  run "$PEER" --list
  [ "$status" -eq 0 ]
  [[ "$output" != *"zombie"* ]]
}

@test "--all includes an unreachable session, marked as such" {
  local sock="$BATS_TEST_TMPDIR/stale2.sock"
  python3 -c "
import socket
s = socket.socket(socket.AF_UNIX); s.bind('$sock'); s.close()"
  write_session $$ "ghost" "$sock"

  run "$PEER" --all
  [ "$status" -eq 0 ]
  [[ "$output" == *"ghost"* ]]
  [[ "$output" == *"unreachable"* ]]
}

@test "--send delivers a well-formed user message, addressed by name" {
  local sock="$BATS_TEST_TMPDIR/peer.sock" got="$BATS_TEST_TMPDIR/got"
  start_listener "$sock" "$got"
  write_session $$ "alpha" "$sock"

  run "$PEER" --send alpha "hello from bash"
  [ "$status" -eq 0 ]

  sleep 0.4
  run python3 -c "
import json
line = open('$got').read().strip().splitlines()[0]
rec = json.loads(line)
assert rec['type'] == 'user', rec
assert rec['message']['role'] == 'user', rec
assert rec['message']['content'] == 'hello from bash', rec
print('ok')
"
  [ "$status" -eq 0 ] || { echo "$output" >&2; return 1; }
}

@test "--send addresses a peer by pid" {
  local sock="$BATS_TEST_TMPDIR/peer.sock" got="$BATS_TEST_TMPDIR/got"
  start_listener "$sock" "$got"
  write_session $$ "alpha" "$sock"

  run "$PEER" --send "$$" "by pid"
  [ "$status" -eq 0 ]
  sleep 0.4
  grep -q "by pid" "$got"
}

@test "--send addresses a peer by ref" {
  local sock="$BATS_TEST_TMPDIR/peer.sock" got="$BATS_TEST_TMPDIR/got"
  start_listener "$sock" "$got"
  write_session $$ "alpha" "$sock"

  run "$PEER" --send "$(expected_ref "$sock")" "by ref"
  [ "$status" -eq 0 ]
  sleep 0.4
  grep -q "by ref" "$got"
}

@test "--send reads the body from stdin when given -" {
  local sock="$BATS_TEST_TMPDIR/peer.sock" got="$BATS_TEST_TMPDIR/got"
  start_listener "$sock" "$got"
  write_session $$ "alpha" "$sock"

  run bash -c "echo 'piped body' | '$PEER' --send alpha -"
  [ "$status" -eq 0 ]
  sleep 0.4
  grep -q "piped body" "$got"
}

@test "--send escapes quotes and backslashes rather than emitting broken JSON" {
  local sock="$BATS_TEST_TMPDIR/peer.sock" got="$BATS_TEST_TMPDIR/got"
  start_listener "$sock" "$got"
  write_session $$ "alpha" "$sock"

  run "$PEER" --send alpha 'he said "hi" \ then left'
  [ "$status" -eq 0 ]
  sleep 0.4
  run python3 -c "
import json
line = open('$got').read().strip().splitlines()[0]
rec = json.loads(line)
assert rec['message']['content'] == 'he said \"hi\" \\\\ then left', rec['message']['content']
print('ok')
"
  [ "$status" -eq 0 ] || { echo "$output" >&2; return 1; }
}

@test "--send fails loudly for an unknown target" {
  run "$PEER" --send nobody "hello"
  [ "$status" -ne 0 ]
  [[ "$output" == *"nobody"* ]]
}

@test "--send refuses to message this session" {
  local sock="$BATS_TEST_TMPDIR/self.sock"
  start_listener "$sock" "$BATS_TEST_TMPDIR/got"
  write_session $$ "myself" "$sock"

  run "$PEER" --send myself "loop"
  [ "$status" -ne 0 ]
}

@test "--send fails when the target is listed but no longer answers" {
  local sock="$BATS_TEST_TMPDIR/stale3.sock"
  python3 -c "
import socket
s = socket.socket(socket.AF_UNIX); s.bind('$sock'); s.close()"
  write_session $$ "ghost" "$sock"

  run "$PEER" --send ghost "hello"
  [ "$status" -ne 0 ]
}

@test "an empty registry lists nothing and succeeds" {
  run "$PEER" --list
  [ "$status" -eq 0 ]
}
