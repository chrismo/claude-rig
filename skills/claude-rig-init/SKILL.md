---
name: claude-rig-init
description: Bootstrap Claude Code plumbing in a repo (settings, tmp dir, gitignore)
disable-model-invocation: true
allowed-tools: Bash
---

Run [init.sh](scripts/init.sh) to set up tmp/ and .gitignore.

If `.claude/settings.json` is MISSING in the output, create it:
run `mkdir -p .claude` then `touch .claude/settings.json`.
This requires user approval because the sandbox protects `.claude/`.

Summarize what was set up. If `.claude/settings.json` was empty or
just created, mention that the user can run `install.sh` from their
claude-rig repo to populate hooks and permissions.
