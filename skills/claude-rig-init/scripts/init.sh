#!/usr/bin/env bash

set -euo pipefail

# Create tmp/
mkdir -p tmp

# Ensure .gitignore entries
touch .gitignore
for entry in ".claude/settings.local.json" ".claude/tmp/" "tmp/"; do
  grep -qxF "$entry" .gitignore || echo "$entry" >> .gitignore
done

# Report state
echo "=== tmp/ ==="
echo "EXISTS"
echo ""
echo "=== .gitignore ==="
cat .gitignore
echo ""
echo "=== .claude/settings.json ==="
if [ -f .claude/settings.json ]; then
  echo "EXISTS"
  cat .claude/settings.json
else
  echo "MISSING"
fi
