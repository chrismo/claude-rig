#!/usr/bin/env bash

set -euo pipefail

# Summarize all Claude Code sessions under ~/.claude/projects/.
# Useful for spotting sessions that spiked token usage.
#
# Usage:
#   session-timeline.sh [--since=<ISO>] [--until=<ISO>]
#
# All timestamps (input and output) are UTC (ISO-8601 with Z).
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

export ASDF_SUPERDB_VERSION="${ASDF_SUPERDB_VERSION:-0.3.0}"

SINCE=""
UNTIL=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --since=*) SINCE="${1#--since=}" ;;
    --since)   SINCE="$2"; shift ;;
    --until=*) UNTIL="${1#--until=}" ;;
    --until)   UNTIL="$2"; shift ;;
    -h|--help)
      awk '/^#!/ {next} /^#/ {in_block=1; print; next} in_block {exit}' "$0"
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
  super -j -c "
    type == 'assistant' and has(message.usage) and ${frame_clause}
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
  " "${files[@]}" | grdy

  printf '\nLegend (all timestamps UTC):\n'
  printf '  last_ts       most recent assistant turn.\n'
  printf '  sid           session ID (first 8 chars).\n'
  printf '  turns         unique API requests (by requestId). Just\n'
  printf '                activity volume; not inherently good/bad.\n'
  printf '  total_tokens  input + ccreate + cread + output summed\n'
  printf '                across turns. Magnitude of API activity\n'
  printf '                -- bigger = more rate-limit burn. An\n'
  printf '                outlier here is the first suspect to\n'
  printf '                drill into with session-usage.sh.\n'
  printf '  bloat_turns   turns where ccreate >= 20K. A few (1-3)\n'
  printf '                is normal (cold start + resume gaps).\n'
  printf '                Many (10+) without proportional context\n'
  printf '                growth suggests repeated cache rebuilds\n'
  printf '                or MCP tool-def tax on every new turn.\n'
  printf '  cwd           working directory recorded for the session.\n'
}

if [[ -t 1 ]]; then
  render | ${PAGER:-less -FRX}
else
  render
fi
