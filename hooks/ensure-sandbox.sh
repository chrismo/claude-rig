#!/bin/bash
# SessionStart hook: ensure sandbox is enabled in .claude/settings.local.json

SETTINGS=".claude/settings.local.json"

mkdir -p .claude

if [ ! -f "$SETTINGS" ]; then
  echo '{}' > "$SETTINGS"
fi

super -J -c 'values {...this, sandbox:{enabled:true, autoAllowBashIfSandboxed:true, filesystem:{allowWrite:[".claude/tmp","tmp"]}}}' "$SETTINGS" > "$SETTINGS.tmp" \
  && mv "$SETTINGS.tmp" "$SETTINGS"
