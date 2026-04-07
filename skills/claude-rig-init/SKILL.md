---
name: claude-rig-init
description: Bootstrap Claude Code plumbing in a repo (settings, tmp dir, gitignore)
disable-model-invocation: true
---

!`${CLAUDE_SKILL_DIR}/init.sh`

Summarize what was set up. If `.claude/settings.json` was empty, mention
that the user can run `install.sh` from their claude-rig repo to populate
hooks and permissions.
