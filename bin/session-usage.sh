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
#   cuml       cumulative total tokens (input + ccreate + cread + output)
#   flag       * = cread dropped >=50% below prior peak (possible cache break)
#              + = ccreate >=20000 on one turn (possible prompt bloat)

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/config.sh"

export ASDF_SUPERDB_VERSION="${ASDF_SUPERDB_VERSION:-0.3.0}"

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

render() {
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
  ' "$jsonl" | awk -F, '
    NR == 1 { next }
    {
      input = $3 + 0
      ccreate = $4 + 0
      cread = $5 + 0
      output = $6 + 0
      if (cread > peak) peak = cread
      cuml += input + ccreate + cread + output
      flag = ""
      if (ccreate >= 20000) flag = flag "+"
      if (peak >= 10000 && cread < peak * 0.5) flag = flag "*"
      printf "{\"ts\":\"%s\",\"req\":\"%s\",\"input\":%d,\"ccreate\":%d,\"cread\":%d,\"output\":%d,\"peak\":%d,\"cuml\":%d,\"flag\":\"%s\"}\n", \
        $1, substr($2, 1, 16), input, ccreate, cread, output, peak, cuml, flag
    }
  ' | grdy

  printf '\nLegend:\n'
  printf '  ts       request timestamp\n'
  printf '  req      requestId (truncated)\n'
  printf '  input    new (uncached) input tokens\n'
  printf '  ccreate  cache_creation_input_tokens\n'
  printf '  cread    cache_read_input_tokens\n'
  printf '  output   output tokens\n'
  printf '  peak     running max of cread\n'
  printf '  cuml     cumulative total tokens (input + ccreate + cread + output)\n'
  printf '  flag     +  ccreate >=20K on one turn (prompt bloat)\n'
  printf '           *  cread dropped >=50%% below prior peak (possible cache break)\n'
}

if [[ -t 1 ]]; then
  render | ${PAGER:-less -FRX}
else
  render
fi
