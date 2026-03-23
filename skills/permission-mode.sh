#!/usr/bin/env bash

# Toggle Claude Code permission mode in ~/.claude/settings.json.
# Usage: permission-mode [mode]
#   mode: default | acceptEdits | plan | dontAsk | bypassPermissions
#   If omitted, shows the current mode.

set -euo pipefail

SETTINGS_FILE="$HOME/.claude/settings.json"
VALID_MODES="default acceptEdits plan dontAsk bypassPermissions"

if [[ ! -f "$SETTINGS_FILE" ]]; then
  echo "Error: $SETTINGS_FILE not found"
  exit 1
fi

current=$(super -f line -c 'coalesce(permissions.defaultMode, "default")' "$SETTINGS_FILE" 2>/dev/null)

# No argument — show current mode and allow list
if [[ $# -eq 0 ]]; then
  echo "Current mode: $current"
  echo ""
  echo "Allow rules:"
  rules=$(super -f line -c 'unnest permissions.allow | values this' "$SETTINGS_FILE" 2>/dev/null || true)
  if [[ -n "$rules" ]]; then
    while read -r rule; do
      echo "  $rule"
    done <<< "$rules"
  else
    echo "  (none)"
  fi
  echo ""
  echo "Usage: permission-mode <mode>"
  echo "Modes: $VALID_MODES"
  exit 0
fi

mode="$1"

# Validate mode
valid=false
for m in $VALID_MODES; do
  if [[ "$mode" == "$m" ]]; then
    valid=true
    break
  fi
done

if [[ "$valid" == "false" ]]; then
  echo "Error: invalid mode '$mode'"
  echo "Valid modes: $VALID_MODES"
  exit 1
fi

if [[ "$mode" == "$current" ]]; then
  echo "Already in '$mode' mode — no change needed."
  exit 0
fi

# Warn about dontAsk needing allow rules
if [[ "$mode" == "dontAsk" ]]; then
  allow_count=$(super -f line -c 'len(permissions.allow)' "$SETTINGS_FILE" 2>/dev/null)
  echo "Switching to dontAsk mode."
  echo "Tools not in your allow list ($allow_count rules) will be auto-denied — no prompts."
  echo ""
  echo "Current allow rules:"
  rules=$(super -f line -c 'unnest permissions.allow | values this' "$SETTINGS_FILE" 2>/dev/null || true)
  if [[ -n "$rules" ]]; then
    while read -r rule; do
      echo "  $rule"
    done <<< "$rules"
  else
    echo "  (none)"
  fi
  echo ""
fi

# Warn about bypassPermissions
if [[ "$mode" == "bypassPermissions" ]]; then
  echo "WARNING: bypassPermissions skips all permission prompts."
  echo "Only use this in sandboxed/container environments."
  echo ""
fi

# Update settings.json using super
new_settings=$(super -J -c "permissions.defaultMode:='$mode'" "$SETTINGS_FILE")
echo "$new_settings" > "$SETTINGS_FILE"

echo "$current → $mode"
echo ""
echo "Takes effect on next Claude Code session."
