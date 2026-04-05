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
# Note: use pipe instead of <<< here-string — bash 3.2 (macOS default) mangles <<<
command_str=$(echo "$input" | super -f line -c 'this.tool_input.command' -)

# Always allow commands targeting .claude/tmp — a safe temp directory within the
# project. This must come before all deny checks so it isn't caught by the
# absolute-path or compound-command rules.
if [[ "$command_str" =~ \.claude/tmp ]]; then
  log "allow" "claude-tmp" "$command_str"
  exit 0
fi

# Catch super CLI early — super queries often contain pipes/semicolons in their
# expression syntax, which would hit the compound-command denial below with a
# misleading message. Redirect to SuperDB MCP tools instead.
_first="${command_str%% *}"
if [[ "${_first##*/}" == "super" ]]; then
  log "deny" "super" "$command_str"
  deny_tool "Use the SuperDB MCP tools instead of the \`super\` CLI in Bash."
  exit 0
fi

# Deny any compound command (pipes, chains, semicolons) — these almost always
# trigger permission prompts, which defeats the goal of keeping things flowing.
if [[ "$command_str" =~ \||(\&\&)|\; ]]; then
  log "deny" "compound" "$command_str"
  deny_tool "Compound commands (pipes, &&, ||, ;) are not allowed. Break this into separate tool calls."
  exit 0
fi

# Deny process substitution <(...) and >(...) — these embed hidden commands
# that bypass the compound command check above.
if [[ "$command_str" =~ \<\(|\>\( ]]; then
  log "deny" "process-substitution" "$command_str"
  deny_tool "Process substitution (<(...) and >(...)) is not allowed. Break this into separate tool calls."
  exit 0
fi

# Deny command substitution $(...) — these always trigger permission prompts.
# Run the inner command separately and use the result.
if [[ "$command_str" =~ \$\( ]]; then
  log "deny" "command-substitution" "$command_str"
  if [[ "$command_str" =~ ^git\ commit ]]; then
    deny_tool "Command substitution (\$(...)) is not allowed. For multiline commit messages, use multiple -m flags (each adds a paragraph separated by a blank line). Title should be 50 chars or less. Wrap body lines at 72 columns. Example: git commit -m 'Short title' -m 'Body paragraph wrapped at 72 cols' -m 'Co-Authored-By: ...'"
  else
    deny_tool "Command substitution (\$(...)) is not allowed. Run the inner command separately, then use the result."
  fi
  exit 0
fi

# Deny scripts invoked by absolute path when they're under the working directory —
# absolute paths trigger per-worktree approval prompts; relative paths don't.
cwd=$(pwd)
if [[ "$command_str" == "$cwd"/* ]]; then
  log "deny" "absolute-path" "$command_str"
  deny_tool "Use a relative path instead of an absolute path for scripts under the working directory."
  exit 0
fi

# Deny commands that reference /tmp — these always trigger permission prompts
# because /tmp is outside the project directory. Use .claude/tmp within the repo instead.
# Also catch relative traversals like ../../../tmp that resolve to /tmp.
if [[ "$command_str" =~ (^|[[:space:]\"\'=])/tmp(/|$) ]] || [[ "$command_str" =~ (\.\./)+tmp(/|$) ]]; then
  log "deny" "tmp-redirect" "$command_str"
  deny_tool "Do not use /tmp — it is outside the project and triggers permission prompts. Use .claude/tmp/ instead (mkdir -p .claude/tmp first if needed)."
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
  find|ls)
    message="Use the Glob tool instead of \`$base_cmd\` in Bash."
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
  eval)
    message="\`eval\` is not allowed — it executes arbitrary strings and is never needed for normal tasks."
    ;;
  exec)
    message="\`exec\` is not allowed — it replaces the current process."
    ;;
  source)
    message="\`source\` is not allowed — use the Read tool to inspect files instead."
    ;;
  git)
    # Match git -C only as the first flag (not buried in commit messages etc.)
    if [[ "$command_str" =~ ^git\ -C\  ]]; then
      message="\`git -C\` is not allowed — run git commands from the correct directory instead."
    fi
    ;;
  bash|sh|zsh)
    if [[ "$command_str" =~ \ -c\  ]]; then
      message="\`$base_cmd -c\` is not allowed — it bypasses compound command restrictions. Run the command directly."
    else
      # Deny `bash script.sh` — run scripts directly so allow rules can match.
      args="${command_str#* }"
      first_arg="${args%% *}"
      if [[ -n "$first_arg" ]] && [[ "$first_arg" != "$command_str" ]] && [[ "$first_arg" != -* ]]; then
        message="Do not invoke scripts via \`$base_cmd\` — run directly (e.g., ./$first_arg instead of $base_cmd $first_arg). Ensure the script has a shebang (#!/usr/bin/env bash) and is executable (chmod +x). Direct invocation allows pre-approved allow rules to match."
      fi
    fi
    ;;
esac

if [[ -n "$message" ]]; then
  log "deny" "$base_cmd" "$command_str"
  deny_tool "$message"
else
  log "allow" "$base_cmd" "$command_str"
  exit 0
fi
