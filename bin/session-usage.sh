#!/usr/bin/env bash

set -euo pipefail

# Per-turn token usage for a Claude Code session JSONL.
# Extracts usage data and flags potential prompt-cache breaks
# (see anthropics/claude-code#40652).
#
# Usage:
#   session-usage.sh <path-or-session-id> [--since=<ISO>] [--until=<ISO>]
#                    [--start-pct=<N> --end-pct=<N>]
#
# All timestamps (input and output) are UTC (ISO-8601 with Z).
#
# Passing --start-pct and --end-pct (e.g. 46 -> 91 over a 5h
# window) adds a pct column that interpolates where cuml sat at
# each row relative to the total burn in the frame.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/config.sh"

export ASDF_SUPERDB_VERSION="${ASDF_SUPERDB_VERSION:-0.3.0}"

SINCE=""
UNTIL=""
START_PCT=""
END_PCT=""
POSITIONAL=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --since=*)     SINCE="${1#--since=}" ;;
    --since)       SINCE="$2"; shift ;;
    --until=*)     UNTIL="${1#--until=}" ;;
    --until)       UNTIL="$2"; shift ;;
    --start-pct=*) START_PCT="${1#--start-pct=}" ;;
    --start-pct)   START_PCT="$2"; shift ;;
    --end-pct=*)   END_PCT="${1#--end-pct=}" ;;
    --end-pct)     END_PCT="$2"; shift ;;
    -h|--help)     awk '/^#!/ {next} /^#/ {in_block=1; print; next} in_block {exit}' "$0"; exit 0 ;;
    --*)           echo "Unknown argument: $1" >&2; exit 1 ;;
    *)             POSITIONAL+=("$1") ;;
  esac
  shift
done

if [[ ${#POSITIONAL[@]} -ne 1 ]]; then
  echo "Usage: $0 <jsonl-path-or-session-id> [--since=...] [--until=...] [--start-pct=...] [--end-pct=...]" >&2
  exit 1
fi

arg="${POSITIONAL[0]}"

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

frame_clause="true"
if [[ -n "$SINCE" ]]; then
  frame_clause="timestamp >= \"$SINCE\""
fi
if [[ -n "$UNTIL" ]]; then
  if [[ "$frame_clause" == "true" ]]; then
    frame_clause="timestamp < \"$UNTIL\""
  else
    frame_clause="$frame_clause and timestamp < \"$UNTIL\""
  fi
fi

render() {
  super -f csv -c "
    type == 'assistant' and has(message.usage) and ${frame_clause}
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
  " "$jsonl" | awk -F, -v start_pct="$START_PCT" -v end_pct="$END_PCT" '
    NR == 1 { next }
    substr($2, 1, 4) != "req_" { next }
    {
      input = $3 + 0
      ccreate = $4 + 0
      cread = $5 + 0
      output = $6 + 0
      if (cread > peak) peak = cread
      cuml += input + ccreate + cread + output
      fl = ""
      if (ccreate >= 20000) fl = fl "+"
      if (peak >= 10000 && cread < peak * 0.5) fl = fl "*"
      n++
      ts[n] = $1; req[n] = substr($2, 1, 16)
      ip[n] = input; cc[n] = ccreate; cr[n] = cread; op[n] = output
      pk[n] = peak; cm[n] = cuml; fg[n] = fl
    }
    END {
      total = cuml
      have_pct = (start_pct != "" && end_pct != "" && total > 0)
      for (i = 1; i <= n; i++) {
        pct_field = ""
        if (have_pct) {
          pct = start_pct + (cm[i] / total) * (end_pct - start_pct)
          pct_field = sprintf(",\"pct\":%.1f", pct)
        }
        printf "{\"ts\":\"%s\",\"req\":\"%s\",\"input\":%d,\"ccreate\":%d,\"cread\":%d,\"output\":%d,\"peak\":%d,\"cuml\":%d,\"flag\":\"%s\"%s}\n", \
          ts[i], req[i], ip[i], cc[i], cr[i], op[i], pk[i], cm[i], fg[i], pct_field
      }
    }
  ' | grdy

  printf '\nLegend (all timestamps UTC):\n'
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
  if [[ -n "$START_PCT" && -n "$END_PCT" ]]; then
    printf '  pct      interpolated rate-limit pct for this row (frame: %s%% -> %s%%)\n' "$START_PCT" "$END_PCT"
  fi
}

if [[ -t 1 ]]; then
  render | ${PAGER:-less -FRX}
else
  render
fi
