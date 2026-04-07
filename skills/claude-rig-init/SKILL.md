---
name: claude-rig-init
description: Bootstrap Claude Code plumbing in a repo (settings, tmp dir, gitignore)
disable-model-invocation: true
---

```!
# Create .claude/settings.json (no-op if exists)
mkdir -p .claude
touch .claude/settings.json

# Create tmp/
mkdir -p tmp

# Ensure .gitignore entries
touch .gitignore
for entry in ".claude/settings.local.json" ".claude/tmp/" "tmp/"; do
  grep -qxF "$entry" .gitignore || echo "$entry" >> .gitignore
done

# Report what we have now
echo "=== .claude/settings.json ==="
cat .claude/settings.json
echo ""
echo "=== .gitignore ==="
cat .gitignore
```

Summarize what was set up. If `.claude/settings.json` was empty, mention
that the user can run `install.sh` from their claude-rig repo to populate
hooks and permissions.
