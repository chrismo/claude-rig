---
name: claude-rig-init
description: Bootstrap Claude Code plumbing in a repo (settings, tmp dir, gitignore)
disable-model-invocation: true
allowed-tools: Bash
---

```!
mkdir -p tmp

touch .gitignore
for entry in ".claude/settings.local.json" ".claude/tmp/" "tmp/"; do
  grep -qxF "$entry" .gitignore || echo "$entry" >> .gitignore
done

echo "=== tmp/ ==="
echo "EXISTS"
echo ""
echo "=== .gitignore ==="
cat .gitignore
echo ""
echo "=== .claude/ ==="
if [ -d .claude/tmp ]; then
  echo ".claude/tmp/ EXISTS"
else
  echo ".claude/tmp/ MISSING"
fi
if [ -f .claude/settings.json ]; then
  echo ".claude/settings.json EXISTS"
  cat .claude/settings.json
else
  echo ".claude/settings.json MISSING"
fi
```

After the above runs, you MUST create anything reported as MISSING:
1. `mkdir -p .claude/tmp` (if .claude/tmp/ MISSING)
2. `touch .claude/settings.json` (if .claude/settings.json MISSING)

The sandbox blocks writes to `.claude/`. Run these with
`dangerouslyDisableSandbox: true` so they succeed (the user
will be prompted to approve).

Summarize what was set up or already existed.
