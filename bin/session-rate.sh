#!/usr/bin/env bash

set -euo pipefail

# Bucketed token-rate timeline across all Claude Code sessions.
# Sums tokens per time bucket and tracks a cumulative total so you
# can spot where rate-limit consumption actually spiked.
#
# Usage:
#   session-rate.sh [--since=<ISO>] [--until=<ISO>] [--bucket=<duration>]
#                   [--start-pct=<N> --end-pct=<N>]
#
# All timestamps (input and output) are UTC (ISO-8601 with Z).
#
# Passing --start-pct and --end-pct frames the window against an
# observed rate-limit percentage (e.g. 46% -> 91% over a 5h
# window) and adds a pct column that interpolates where cuml sat
# at each bucket relative to the total burn in the frame.
#
# Example:
#   session-rate.sh --since=2026-04-22T12:00:00Z --until=2026-04-22T17:00:00Z \
#                   --start-pct=46 --end-pct=91

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/config.sh"

export ASDF_SUPERDB_VERSION="${ASDF_SUPERDB_VERSION:-0.3.0}"

SINCE=""
UNTIL=""
BUCKET="5m"
START_PCT=""
END_PCT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --since=*)     SINCE="${1#--since=}" ;;
    --since)       SINCE="$2"; shift ;;
    --until=*)     UNTIL="${1#--until=}" ;;
    --until)       UNTIL="$2"; shift ;;
    --bucket=*)    BUCKET="${1#--bucket=}" ;;
    --bucket)      BUCKET="$2"; shift ;;
    --start-pct=*) START_PCT="${1#--start-pct=}" ;;
    --start-pct)   START_PCT="$2"; shift ;;
    --end-pct=*)   END_PCT="${1#--end-pct=}" ;;
    --end-pct)     END_PCT="$2"; shift ;;
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
  super -f csv -c "
    type == 'assistant' and has(message.usage) and ${frame_clause}
    | summarize u := any(message.usage), ts := min(timestamp), sid := any(sessionId) by requestId
    | values {
        b: bucket(cast(ts, <time>), ${BUCKET}),
        sid: sid[0:8],
        total: u.input_tokens + u.cache_creation_input_tokens + u.cache_read_input_tokens + u.output_tokens,
        ccreate: u.cache_creation_input_tokens,
        cread: u.cache_read_input_tokens
      }
    | summarize
        turns := count(),
        ccreate := sum(ccreate),
        cread := sum(cread),
        total := sum(total)
        by b, sid
    | sort b, sid
    | values {bucket: b, sid, turns, ccreate, cread, total}
  " "${files[@]}" | awk -F, -v start_pct="$START_PCT" -v end_pct="$END_PCT" '
    NR == 1 { next }
    substr($1, 1, 2) != "20" { next }
    {
      cuml += $6 + 0
      n++
      bucket[n] = $1; sid[n] = $2; turns[n] = $3
      ccr[n] = $4; crd[n] = $5; tot[n] = $6; cml[n] = cuml
    }
    END {
      total = cuml
      have_pct = (start_pct != "" && end_pct != "" && total > 0)
      for (i = 1; i <= n; i++) {
        pct_field = ""
        if (have_pct) {
          pct = start_pct + (cml[i] / total) * (end_pct - start_pct)
          pct_field = sprintf(",\"pct\":%.1f", pct)
        }
        printf "{\"bucket\":\"%s\",\"sid\":\"%s\",\"turns\":%d,\"ccreate\":%d,\"cread\":%d,\"total\":%d,\"cuml\":%d%s}\n", \
          bucket[i], sid[i], turns[i], ccr[i], crd[i], tot[i], cml[i], pct_field
      }
    }
  ' | grdy

  printf '\nLegend (all timestamps UTC; aggregates all sessions under %s/projects/*/*.jsonl):\n' "$CLAUDE_DIR"
  printf '  bucket   start of the time bucket.\n'
  printf '  sid      session ID (first 8 chars) contributing to\n'
  printf '           this bucket. Multiple sids per bucket means\n'
  printf '           tabs were active simultaneously.\n'
  printf '  turns    API requests from sid in this bucket. High\n'
  printf '           turn count in a small window = fast iteration.\n'
  printf '  ccreate  cache-creation tokens -- expensive. High on\n'
  printf '           a sids first appearance is session-init cost\n'
  printf '           (system prompt + MCP tool defs). Large MCP\n'
  printf '           configs amplify this across every new session.\n'
  printf '  cread    cache-read tokens -- cheap but still counts.\n'
  printf '           Large and growing = accumulated context being\n'
  printf '           re-read every turn (normal on 1M tier with\n'
  printf '           long sessions; still rate-limit pressure).\n'
  printf '  total    input + ccreate + cread + output for sid in\n'
  printf '           bucket. The absolute weight of this rows\n'
  printf '           activity.\n'
  printf '  cuml     running cumulative total across all rows.\n'
  printf '           Steep bucket-to-bucket jumps = fast-burn\n'
  printf '           moment; flat = idle. If one bucket adds 10M+\n'
  printf '           thats a tab swarm or runaway session worth\n'
  printf '           drilling into with session-usage.sh.\n'
  if [[ -n "$START_PCT" && -n "$END_PCT" ]]; then
    printf '  pct      linearly interpolated rate-limit pct across\n'
    printf '           the frame (%s%% -> %s%%). Rough anchor, not\n' "$START_PCT" "$END_PCT"
    printf '           authoritative -- cache_read is weighted\n'
    printf '           less than full-rate tokens.\n'
  fi
}

if [[ -t 1 ]]; then
  render | ${PAGER:-less -FRX}
else
  render
fi
