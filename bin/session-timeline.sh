#!/usr/bin/env bash

set -euo pipefail

# Summarize all Claude Code sessions under ~/.claude/projects/.
# Useful for spotting sessions that spiked token usage.
#
# Usage:
#   session-timeline.sh [--since=<ISO-timestamp>]
#
# Example:
#   session-timeline.sh --since=2026-04-22T10:00:00Z
#
# Columns:
#   last_ts        most recent assistant turn
#   sid            session ID (first 8 chars)
#   turns          unique API requests (by requestId)
#   total_tokens   input + ccreate + cread + output, summed across turns
#   bloat_turns    turns with cache_creation_input_tokens >= 20000
#   cwd            working directory recorded for the session

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/config.sh"

SINCE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --since=*) SINCE="${1#--since=}" ;;
    --since) SINCE="$2"; shift ;;
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

render() {
  super -f csv -c "
    type == 'assistant' and has(message.usage) and ${since_clause}
    | summarize
        u := any(message.usage),
        ts := min(timestamp),
        sid := any(sessionId),
        cwd := any(cwd)
        by requestId
    | summarize
        first_ts := min(ts),
        last_ts := max(ts),
        turns := count(),
        tot_input := sum(u.input_tokens),
        tot_ccreate := sum(u.cache_creation_input_tokens),
        tot_cread := sum(u.cache_read_input_tokens),
        tot_output := sum(u.output_tokens),
        bloat_turns := sum(cast(u.cache_creation_input_tokens >= 20000, <int64>)),
        cwd := any(cwd)
        by sid
    | sort last_ts
    | values {
        last_ts,
        sid: sid[0:8],
        turns,
        total_tokens: tot_input + tot_ccreate + tot_cread + tot_output,
        bloat_turns,
        cwd
      }
  " "${files[@]}" | column -t -s,

  printf '\nLegend:\n'
  printf '  last_ts       most recent assistant turn\n'
  printf '  sid           session ID (first 8 chars)\n'
  printf '  turns         unique API requests (by requestId)\n'
  printf '  total_tokens  input + ccreate + cread + output, summed across turns\n'
  printf '  bloat_turns   turns with cache_creation_input_tokens >=20K\n'
  printf '  cwd           working directory recorded for the session\n'
}

if [[ -t 1 ]]; then
  render | ${PAGER:-less -FRX}
else
  render
fi
