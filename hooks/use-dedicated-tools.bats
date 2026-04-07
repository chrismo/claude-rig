#!/usr/bin/env bats

# Test suite for the use-dedicated-tools.sh PreToolUse hook.
#
# The hook reads JSON from stdin with structure {"tool_input":{"command":"..."}},
# checks the command against a mapping of CLI tools that have dedicated Claude Code
# tool equivalents, and either denies with a JSON reason or allows silently.
#
# NOTE: The hook writes logs to ~/.claude/logs/, which is outside the sandbox
# write-allow list. These tests must run with sandbox disabled
# (dangerouslyDisableSandbox: true) or every test will fail because the hook
# crashes on the blocked log writes.

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

@test "allow: rg pattern file" {
  run_hook "rg pattern file"
  assert_allow
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

@test "deny: super -c with pipe in query → SuperDB MCP (not compound)" {
  run_hook "super -c from settings.json | permissions.deny"
  assert_deny "SuperDB MCP"
}

# ── Deny: dangerous shell commands ─────────────────────────────────────────────

@test "deny: eval echo hello → eval blocked" {
  run_hook 'eval echo hello'
  assert_deny "eval"
}

@test "deny: exec /bin/sh → exec blocked" {
  run_hook "exec /bin/sh"
  assert_deny "exec"
}

@test "deny: source ~/.bashrc → source blocked" {
  run_hook "source ~/.bashrc"
  assert_deny "source"
}

@test "deny: bash -c 'rm -rf /' → bash -c blocked" {
  run_hook "bash -c rm -rf /"
  assert_deny "bash -c"
}

@test "deny: sh -c 'whoami' → sh -c blocked" {
  run_hook "sh -c whoami"
  assert_deny "sh -c"
}

@test "deny: bash script.sh → run directly" {
  run_hook "bash script.sh"
  assert_deny "directly"
}

@test "deny: sh install.sh → run directly" {
  run_hook "sh install.sh"
  assert_deny "directly"
}

@test "deny: bash install.sh arg1 arg2 → run directly" {
  run_hook "bash install.sh --verbose --dry-run"
  assert_deny "directly"
}

@test "allow: bash --version (flag, not script)" {
  run_hook "bash --version"
  assert_allow
}

# ── Deny: git -C ───────────────────────────────────────────────────────────────

@test "deny: git -C /other/path status → git -C blocked" {
  run_hook "git -C /other/path status"
  assert_deny "git -C"
}

@test "allow: git status (no -C flag)" {
  run_hook "git status"
  assert_allow
}

@test "allow: git commit -m message" {
  run_hook "git commit -m message"
  assert_allow
}

@test "allow: git commit with -C in message body" {
  run_hook "git commit -m Block git -C in hook"
  assert_allow
}

# ── Deny: absolute paths under working directory ──────────────────────────────

@test "deny: absolute path under cwd → use relative path" {
  run_hook "$(pwd)/scripts/deploy.sh config"
  assert_deny "relative path"
}

@test "allow: relative path to script" {
  run_hook "./scripts/deploy.sh config"
  assert_allow
}

@test "allow: /usr/bin/ls -la (full path stripped, ls allowed)" {
  run_hook "/usr/bin/ls -la"
  assert_allow
}

@test "allow: absolute path outside cwd (e.g. /usr/bin/env)" {
  run_hook "/usr/bin/env FOO=bar"
  assert_allow
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

# ── Deny: process substitution <(...) and >(...) ─────────────────────────────

@test "deny: diff <(cmd1) <(cmd2) → process substitution" {
  run_hook "diff <(sort file1) <(sort file2)"
  assert_deny "Process substitution"
}

@test "deny: cmd >(tee log) → process substitution (output)" {
  run_hook "cmd >(tee log.txt)"
  assert_deny "Process substitution"
}

# ── Deny: command substitution $(...) and backticks ──────────────────────────

@test "deny: echo \$(date) → command substitution" {
  run_hook 'echo $(date)'
  assert_deny "Command substitution"
}

@test "deny: git log --since=\$(date) → command substitution" {
  run_hook 'git log --since=$(date -d yesterday)'
  assert_deny "Command substitution"
}

@test "deny: git commit with \$() → suggests temp file approach" {
  run_hook 'git commit -m "$(echo test)"'
  assert_deny "tmp/commit-msg.txt"
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

# ── Deny: /tmp → use repo tmp/ ────────────────────────────────────────────────

@test "deny: cmd > /tmp/output.txt → use repo tmp/" {
  run_hook "blah-blerg > /tmp/blerg-output.txt"
  assert_deny "Use tmp/"
}

@test "deny: mkdir -p /tmp/foo → use repo tmp/" {
  run_hook "mkdir -p /tmp/foo"
  assert_deny "Use tmp/"
}

@test "deny: ls /tmp (bare, no trailing slash) → use repo tmp/" {
  run_hook "ls /tmp"
  assert_deny "Use tmp/"
}

@test "deny: ../../../tmp/foo (relative traversal) → use repo tmp/" {
  run_hook "mkdir -p ../../../tmp/foo"
  assert_deny "Use tmp/"
}

@test "deny: ../../tmp/out.txt (relative traversal) → use repo tmp/" {
  run_hook "blah-blerg > ../../tmp/out.txt"
  assert_deny "Use tmp/"
}

@test "deny: ../tmp/x (single parent traversal) → use repo tmp/" {
  run_hook "TMPDIR=../tmp/x cmd"
  assert_deny "Use tmp/"
}

# ── Allow: repo tmp/ ─────────────────────────────────────────────────────────

@test "allow: mkdir -p tmp" {
  run_hook "mkdir -p tmp"
  assert_allow
}

@test "allow: cmd > tmp/output.txt" {
  run_hook "blah-blerg > tmp/output.txt"
  assert_allow
}

@test "deny: /tmp message suggests .gitignore" {
  run_hook "mkdir -p /tmp/foo"
  assert_deny ".gitignore"
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
