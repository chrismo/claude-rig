#!/usr/bin/env bats

# Test suite for the use-dedicated-tools.sh PreToolUse hook.
#
# The hook reads JSON from stdin with structure {"tool_input":{"command":"..."}},
# checks the command against a mapping of CLI tools that have dedicated Claude Code
# tool equivalents, and either denies with a JSON reason or allows silently.

HOOK="$BATS_TEST_DIRNAME/use-dedicated-tools.sh"

# ── Helper ──────────────────────────────────────────────────────────────────────

# run_hook CMD_STRING
#   Builds the hook JSON input for the given command string using super,
#   pipes it into the hook, and captures output/status via bats `run`.
run_hook() {
  local cmd_string="$1"
  local json_input
  json_input=$(super -j -c "values {tool_input: {command: '$cmd_string'}}")
  run bash -c "echo '$json_input' | bash $HOOK"
}

# assert_deny EXPECTED_TOOL_NAME
#   Asserts the hook denied with valid JSON mentioning the expected tool name.
assert_deny() {
  local expected_tool="$1"

  # Should exit 0 (the hook prints JSON and exits normally on deny)
  [ "$status" -eq 0 ]

  # Output must not be empty
  [ -n "$output" ]

  # Must be valid JSON in Claude Code's expected format
  local decision reason
  decision=$(echo "$output" | super -f line -c 'this.hookSpecificOutput.permissionDecision' -)
  reason=$(echo "$output" | super -f line -c 'this.hookSpecificOutput.permissionDecisionReason' -)

  [ "$decision" = "deny" ]
  [[ "$reason" == *"$expected_tool"* ]]
}

# assert_allow
#   Asserts the hook allowed the command (exit 0, no output).
assert_allow() {
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ── Deny: grep / rg → Grep tool ────────────────────────────────────────────────

@test "deny: grep foo bar → Grep tool" {
  run_hook "grep foo bar"
  assert_deny "Grep tool"
}

@test "deny: rg pattern file → Grep tool" {
  run_hook "rg pattern file"
  assert_deny "Grep tool"
}

# ── Deny: find → Glob tool ─────────────────────────────────────────────────────

@test "deny: find . -name '*.sh' → Glob tool" {
  run_hook 'find . -name "*.sh"'
  assert_deny "Glob tool"
}

# ── Deny: cat / head / tail → Read tool ────────────────────────────────────────

@test "deny: cat /etc/hosts → Read tool" {
  run_hook "cat /etc/hosts"
  assert_deny "Read tool"
}

@test "deny: head -n 10 file.txt → Read tool" {
  run_hook "head -n 10 file.txt"
  assert_deny "Read tool"
}

@test "deny: tail -f log.txt → Read tool" {
  run_hook "tail -f log.txt"
  assert_deny "Read tool"
}

# ── Deny: sed / awk → Edit tool ────────────────────────────────────────────────

@test "deny: sed 's/foo/bar/' file → Edit tool" {
  run_hook "sed s/foo/bar/ file"
  assert_deny "Edit tool"
}

@test "deny: awk '{print \$1}' file → Edit tool" {
  run_hook "awk {print} file"
  assert_deny "Edit tool"
}

# ── Deny: echo / printf with redirect → Write tool ─────────────────────────────

@test "deny: echo 'hello' > file.txt → Write tool" {
  run_hook 'echo "hello" > file.txt'
  assert_deny "Write tool"
}

@test "deny: printf 'data' >> file.txt → Write tool" {
  run_hook 'printf "data" >> file.txt'
  assert_deny "Write tool"
}

# ── Deny: python / python3 with json → SuperDB MCP ─────────────────────────────

@test "deny: python3 -c 'import json; ...' → SuperDB MCP" {
  run_hook "python3 -c import json"
  assert_deny "SuperDB MCP"
}

@test "deny: python -c 'json.loads(...)' → SuperDB MCP" {
  run_hook "python -c json.loads"
  assert_deny "SuperDB MCP"
}

# ── Deny: super CLI → SuperDB MCP ──────────────────────────────────────────────

@test "deny: super -j -c 'query' file.json → SuperDB MCP" {
  run_hook "super -j -c query file.json"
  assert_deny "SuperDB MCP"
}

# ── Deny: full path commands ────────────────────────────────────────────────────

@test "deny: /usr/bin/grep foo → Grep tool (full path stripped)" {
  run_hook "/usr/bin/grep foo"
  assert_deny "Grep tool"
}

# ── Deny: compound commands (pipes, chains, semicolons) ───────────────────────

@test "deny: git log | grep foo → compound (pipe)" {
  run_hook "git log | grep foo"
  assert_deny "Compound"
}

@test "deny: ls -la | tail -5 → compound (pipe)" {
  run_hook "ls -la | tail -5"
  assert_deny "Compound"
}

@test "deny: cd /path && cat file.txt → compound (&&)" {
  run_hook "cd /path && cat file.txt"
  assert_deny "Compound"
}

@test "deny: cmd1 ; find . -name foo → compound (;)" {
  run_hook "cmd1 ; find . -name foo"
  assert_deny "Compound"
}

@test "deny: cmd1 || grep fallback → compound (||)" {
  run_hook "cmd1 || grep fallback"
  assert_deny "Compound"
}

@test "deny: cmd1 | cmd2 | awk '{print}' → compound (deep pipeline)" {
  run_hook "cmd1 | cmd2 | awk {print}"
  assert_deny "Compound"
}

# ── Allow: commands without dedicated tools ─────────────────────────────────────

@test "allow: git status" {
  run_hook "git status"
  assert_allow
}

@test "allow: npm install" {
  run_hook "npm install"
  assert_allow
}

@test "allow: ls -la" {
  run_hook "ls -la"
  assert_allow
}

@test "allow: echo 'hello' (no redirect)" {
  run_hook "echo hello"
  assert_allow
}

@test "allow: printf 'hello\n' (no redirect)" {
  run_hook 'printf "hello\n"'
  assert_allow
}

@test "allow: python3 script.py (no json reference)" {
  run_hook "python3 script.py"
  assert_allow
}

@test "allow: mkdir -p /tmp/foo" {
  run_hook "mkdir -p /tmp/foo"
  assert_allow
}

# ── Output validation ──────────────────────────────────────────────────────────

@test "deny output is valid JSON in Claude Code hookSpecificOutput format" {
  run_hook "cat somefile"
  [ "$status" -eq 0 ]
  [ -n "$output" ]

  # Verify Claude Code's expected structure
  local event decision reason
  event=$(echo "$output" | super -f line -c 'this.hookSpecificOutput.hookEventName' -)
  decision=$(echo "$output" | super -f line -c 'this.hookSpecificOutput.permissionDecision' -)
  reason=$(echo "$output" | super -f line -c 'this.hookSpecificOutput.permissionDecisionReason' -)

  [ "$event" = "PreToolUse" ]
  [ "$decision" = "deny" ]
  [ -n "$reason" ]
}

@test "allow output is completely empty" {
  run_hook "git log"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
