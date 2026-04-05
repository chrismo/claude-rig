#!/usr/bin/env bash

set -euo pipefail

# Harvest permissions from ~/.claude/settings.json back into claude-rig .sup files
# Usage: harvest [--dry-run]

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/config.sh"

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
fi

if [[ ! -f "$SETTINGS_FILE" ]]; then
  echo "Error: $SETTINGS_FILE not found"
  exit 1
fi

if ! command -v super &>/dev/null; then
  echo "Error: 'super' command not found"
  exit 1
fi

# Extract allow rules (unnest array to one value per line)
allow_output=$(super -s -c 'this.permissions.allow | unnest this | sort this | uniq' "$SETTINGS_FILE" 2>/dev/null || true)
if [[ -n "$allow_output" ]]; then
  count=$(echo "$allow_output" | wc -l | tr -d ' ')
  if $DRY_RUN; then
    echo "=== permissions/allow.sup ($count rules) ==="
    echo "$allow_output"
    echo ""
  else
    echo "$allow_output" > "$PERMISSIONS_ALLOW"
    echo "✓ Harvested $count allow rules -> permissions/allow.sup"
  fi
else
  echo "  No allow rules found in settings.json"
fi

# Extract deny rules (unnest array to one value per line)
deny_output=$(super -s -c 'this.permissions.deny | unnest this | sort this | uniq' "$SETTINGS_FILE" 2>/dev/null || true)
if [[ -n "$deny_output" ]]; then
  count=$(echo "$deny_output" | wc -l | tr -d ' ')
  if $DRY_RUN; then
    echo "=== permissions/deny.sup ($count rules) ==="
    echo "$deny_output"
    echo ""
  else
    echo "$deny_output" > "$PERMISSIONS_DENY"
    echo "✓ Harvested $count deny rules -> permissions/deny.sup"
  fi
else
  echo "  No deny rules found in settings.json"
fi

if ! $DRY_RUN; then
  echo ""
  echo "Review changes with: git diff permissions/"
fi
