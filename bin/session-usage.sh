#!/usr/bin/env bash

set -euo pipefail

# Per-turn token usage for a Claude Code session JSONL.
# Extracts usage data and flags potential prompt-cache breaks
# (see anthropics/claude-code#40652).
#
# Usage:
#   session-usage.sh <path/to/session.jsonl>
#   session-usage.sh <session-id>           # searches ~/.claude/projects/*/
#
# Columns:
#   ts         request timestamp
#   req        requestId (short)
#   input     input_tokens (new, uncached)
#   ccreate    cache_creation_input_tokens
#   cread      cache_read_input_tokens
#   output     output_tokens
#   peak       running max of cread
#   flag       * = cread dropped >=50% below prior peak (possible cache break)
#              + = ccreate >=20000 on one turn (possible prompt bloat)

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/config.sh"

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <jsonl-path-or-session-id>" >&2
  exit 1
fi

arg="$1"

if [[ -f "$arg" ]]; then
  jsonl="$arg"
else
  matches=()
  while IFS= read -r line; do
    matches+=("$line")
  done < <(find "$CLAUDE_DIR/projects" -maxdepth 2 -name "${arg}*.jsonl" 2>/dev/null)
  if [[ ${#matches[@]} -eq 0 ]]; then
    echo "No JSONL found for session ID: $arg" >&2
    exit 1
  fi
  if [[ ${#matches[@]} -gt 1 ]]; then
    echo "Multiple JSONLs match '$arg':" >&2
    printf '  %s\n' "${matches[@]}" >&2
    exit 1
  fi
  jsonl="${matches[0]}"
fi

if ! command -v super &>/dev/null; then
  echo "Error: 'super' command not found" >&2
  exit 1
fi

super -f csv -c '
  type == "assistant" and has(message.usage)
  | summarize u := any(message.usage), ts := min(timestamp) by requestId
  | sort ts
  | values {
      ts,
      req: requestId,
      input: u.input_tokens,
      ccreate: u.cache_creation_input_tokens,
      cread: u.cache_read_input_tokens,
      output: u.output_tokens
    }
' "$jsonl" | awk -F, -v OFS=$'\t' '
  NR == 1 {
    print $1, $2, $3, $4, $5, $6, "peak", "flag"
    next
  }
  {
    cread = $5 + 0
    ccreate = $4 + 0
    if (cread > peak) peak = cread
    flag = ""
    if (ccreate >= 20000) flag = flag "+"
    if (peak >= 10000 && cread < peak * 0.5) flag = flag "*"
    print $1, substr($2, 1, 16), $3, $4, $5, $6, peak, flag
  }
' | column -t -s $'\t'
