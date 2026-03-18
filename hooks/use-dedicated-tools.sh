#!/usr/bin/env bash

# PreToolUse hook for Bash tool: denies commands that should use dedicated tools,
# and rejects compound commands (pipes, chains) which typically cause permission prompts.

set -euo pipefail

trap 'deny_tool "HOOK CRASH in use-dedicated-tools.sh (line $LINENO). Do NOT retry — the hook code itself is broken. Stop and tell the user."' ERR

LOG_DIR="$HOME/.claude/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/dedicated-tools-hook.sup"
MAX_LINES=200

# Output the deny JSON in the format Claude Code expects
deny_tool() {
  local reason="$1"
  cat <<EOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"$reason"}}
EOF
}

log() {
  local decision="$1" cmd="$2" full="$3"
  echo "$full" | super -s -i line -c "values {ts: now(), cmd: '$cmd', full: this, decision: '$decision'}" - >> "$LOG_FILE"
  tail -n "$MAX_LINES" "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
}

input=$(cat)

# Extract the command string from the hook JSON
command_str=$(super -f line -c 'this.tool_input.command' - <<< "$input")

# Deny any compound command (pipes, chains, semicolons) — these almost always
# trigger permission prompts, which defeats the goal of keeping things flowing.
if [[ "$command_str" =~ \||(\&\&)|\; ]]; then
  log "deny" "compound" "$command_str"
  deny_tool "Compound commands (pipes, &&, ||, ;) are not allowed. Break this into separate tool calls."
  exit 0
fi

# Get the first word (the primary command)
first_word="${command_str%% *}"
# Strip any leading path components (e.g. /usr/bin/grep -> grep, ~/.asdf/.../super -> super)
base_cmd="${first_word##*/}"

message=""

case "$base_cmd" in
  grep|rg)
    message="Use the Grep tool instead of \`$base_cmd\` in Bash."
    ;;
  find)
    message="Use the Glob tool instead of \`find\` in Bash."
    ;;
  cat|head|tail)
    message="Use the Read tool instead of \`$base_cmd\` in Bash."
    ;;
  sed|awk)
    message="Use the Edit tool instead of \`$base_cmd\` in Bash."
    ;;
  echo|printf)
    # Approximate: any > not followed by & (i.e., not >&). May false-positive on
    # quoted > inside strings, which is acceptable for a deny-with-guidance hook.
    if [[ "$command_str" =~ \>[^\&] ]]; then
      message="Use the Write tool instead of \`$base_cmd\` with file redirection in Bash."
    fi
    ;;
  python|python3)
    # Deny if doing JSON operations — SuperDB MCP handles this better
    if [[ "$command_str" =~ json ]]; then
      message="Use the SuperDB MCP tools instead of Python for JSON operations."
    fi
    ;;
  super)
    message="Use the SuperDB MCP tools instead of the \`super\` CLI in Bash."
    ;;
esac

if [[ -n "$message" ]]; then
  log "deny" "$base_cmd" "$command_str"
  deny_tool "$message"
else
  log "allow" "$base_cmd" "$command_str"
  exit 0
fi
