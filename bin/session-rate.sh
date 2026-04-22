#!/usr/bin/env bash

set -euo pipefail

# Bucketed token-rate timeline across all Claude Code sessions.
# Sums tokens per time bucket and tracks a cumlulative total so you
# can spot where rate-limit consumption actually spiked.
#
# Usage:
#   session-rate.sh [--since=<ISO>] [--bucket=<duration>]
#
# Example:
#   session-rate.sh --since=2026-04-22T10:00:00Z --bucket=5m
#
# Columns:
#   bucket     start of the time bucket
#   turns      API requests in this bucket
#   ccreate    cache_creation tokens (new-context cost)
#   cread      cache_read tokens (cached-context cost)
#   total      all input + ccreate + cread + output in bucket
#   cuml        running cumlulative of total

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/config.sh"

SINCE=""
BUCKET="5m"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --since=*)  SINCE="${1#--since=}" ;;
    --since)    SINCE="$2"; shift ;;
    --bucket=*) BUCKET="${1#--bucket=}" ;;
    --bucket)   BUCKET="$2"; shift ;;
    -h|--help)
      sed -n '2,20p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
  shift
done

if ! command -v super &>/dev/null; then
  echo "Error: 'super' command not found" >&2
  exit 1
fi

shopt -s nullglob
files=( "$CLAUDE_DIR"/projects/*/*.jsonl )
if [[ ${#files[@]} -eq 0 ]]; then
  echo "No session JSONLs under $CLAUDE_DIR/projects" >&2
  exit 1
fi

since_clause="true"
if [[ -n "$SINCE" ]]; then
  since_clause="timestamp >= \"$SINCE\""
fi

super -f csv -c "
  type == 'assistant' and has(message.usage) and ${since_clause}
  | summarize u := any(message.usage), ts := min(timestamp) by requestId
  | values {
      b: bucket(cast(ts, <time>), ${BUCKET}),
      total: u.input_tokens + u.cache_creation_input_tokens + u.cache_read_input_tokens + u.output_tokens,
      ccreate: u.cache_creation_input_tokens,
      cread: u.cache_read_input_tokens
    }
  | summarize
      turns := count(),
      ccreate := sum(ccreate),
      cread := sum(cread),
      total := sum(total)
      by b
  | sort b
  | values {bucket: b, turns, ccreate, cread, total}
" "${files[@]}" | awk -F, -v OFS=$'\t' '
  NR == 1 {
    print $1, $2, $3, $4, $5, "cuml"
    next
  }
  {
    cuml += $5 + 0
    print $1, $2, $3, $4, $5, cuml
  }
' | column -t -s $'\t'
