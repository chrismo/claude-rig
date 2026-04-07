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
echo "=== .claude/settings.json ==="
if [ -f .claude/settings.json ]; then
  echo "EXISTS"
  cat .claude/settings.json
else
  echo "MISSING"
fi
```

If `.claude/settings.json` is MISSING above, create it:
run `mkdir -p .claude` then `touch .claude/settings.json`.
This requires user approval because the sandbox protects `.claude/`.

Summarize what was set up. If `.claude/settings.json` was empty or
just created, mention that the user can run `install.sh` from their
claude-rig repo to populate hooks and permissions.
