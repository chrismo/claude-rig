#!/usr/bin/env bash

# Consolidate Claude Code permission rules across git worktrees.
# Scans .claude/settings.local.json in each worktree and (by default)
# ~/.claude/settings.json for global rules.
#
# Usage: permissions-audit [options] [directory]
#   directory: git repo root to scan worktrees from (default: pwd)
#   --local-only: skip ~/.claude/settings.json
#   --sup / -s:   output in SUP format for piping into super

# NOTE: Target Bash 3.2 compatibility (macOS default).
# Avoid: ${var,,}, ${var^^}, local -n, associative arrays, <<<

set -euo pipefail

if ! command -v super &>/dev/null; then
  echo "Error: 'super' command not found. Install it: brew install superdb/tap/super"
  exit 1
fi

# Parse arguments
local_only=false
sup_output=false
target_dir=""

for arg in "$@"; do
  case "$arg" in
    --local-only) local_only=true ;;
    --sup|-s)     sup_output=true ;;
    -*)           echo "Unknown flag: $arg"; exit 1 ;;
    *)            target_dir="$arg" ;;
  esac
done

if [[ -z "$target_dir" ]]; then
  target_dir=$(pwd)
fi

if [[ ! -d "$target_dir" ]]; then
  echo "Error: directory not found: $target_dir"
  exit 1
fi

# Collect settings files
files=()

# Global settings
if [[ "$local_only" == "false" ]]; then
  global="$HOME/.claude/settings.json"
  if [[ -f "$global" ]]; then
    files+=("$global")
  fi
fi

# Discover worktrees (or fall back to target dir)
if git -C "$target_dir" rev-parse --is-inside-work-tree &>/dev/null; then
  while IFS= read -r line; do
    wt_path="${line%% *}"
    local_settings="$wt_path/.claude/settings.local.json"
    if [[ -f "$local_settings" ]]; then
      files+=("$local_settings")
    fi
  done < <(git -C "$target_dir" worktree list)
else
  # Not a git repo — just check the target directory itself
  local_settings="$target_dir/.claude/settings.local.json"
  if [[ -f "$local_settings" ]]; then
    files+=("$local_settings")
  fi
fi

if [[ ${#files[@]} -eq 0 ]]; then
  echo "No settings files found."
  exit 0
fi

# SUP output mode — emit structured records for piping
if [[ "$sup_output" == "true" ]]; then
  for f in "${files[@]}"; do
    echo "$f" | super -s -i line -c "
      unnest permissions.allow from '$f'
      | values {rule: this, type: 'allow', file: '$f'}
    " - 2>/dev/null || true
    echo "$f" | super -s -i line -c "
      unnest permissions.deny from '$f'
      | values {rule: this, type: 'deny', file: '$f'}
    " - 2>/dev/null || true
  done
  exit 0
fi

# Plain text output
file_count=${#files[@]}

# Collect allow rules
allow_lines=""
allow_total=0
for f in "${files[@]}"; do
  rules=$(super -f line -c 'unnest permissions.allow | values this' "$f" 2>/dev/null || true)
  if [[ -n "$rules" ]]; then
    while IFS= read -r rule; do
      allow_lines="${allow_lines}${rule}	${f}
"
      allow_total=$((allow_total + 1))
    done < <(echo "$rules")
  fi
done

# Collect deny rules
deny_lines=""
deny_total=0
for f in "${files[@]}"; do
  rules=$(super -f line -c 'unnest permissions.deny | values this' "$f" 2>/dev/null || true)
  if [[ -n "$rules" ]]; then
    while IFS= read -r rule; do
      deny_lines="${deny_lines}${rule}	${f}
"
      deny_total=$((deny_total + 1))
    done < <(echo "$rules")
  fi
done

# Count unique rules
allow_unique=0
if [[ -n "$allow_lines" ]]; then
  allow_unique=$(printf "%s" "$allow_lines" | cut -f1 | grep -v '^$' | sort -u | wc -l | tr -d ' ')
fi
deny_unique=0
if [[ -n "$deny_lines" ]]; then
  deny_unique=$(printf "%s" "$deny_lines" | cut -f1 | grep -v '^$' | sort -u | wc -l | tr -d ' ')
fi

# Print allow rules
if [[ $allow_total -gt 0 ]]; then
  echo "=== ALLOW ($allow_total rules, $allow_unique unique, from $file_count files) ==="
  echo "$allow_lines" | sort -t'	' -k1,1 | while IFS='	' read -r rule file; do
    [[ -z "$rule" ]] && continue
    printf "  %-50s %s\n" "$rule" "$file"
  done
  echo ""
fi

# Print deny rules
if [[ $deny_total -gt 0 ]]; then
  echo "=== DENY ($deny_total rules, $deny_unique unique, from $file_count files) ==="
  echo "$deny_lines" | sort -t'	' -k1,1 | while IFS='	' read -r rule file; do
    [[ -z "$rule" ]] && continue
    printf "  %-50s %s\n" "$rule" "$file"
  done
  echo ""
fi

if [[ $allow_total -eq 0 && $deny_total -eq 0 ]]; then
  echo "No permission rules found in $file_count files."
fi
