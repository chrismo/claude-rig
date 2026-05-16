---
name: pod-peer
description: You may have peer Claude sessions cooperating with you — claude-pod lets you read what they're doing
allowed-tools: Bash
---

# pod-peer — you have peers

You may have other Claude sessions cooperating with you, often in the same
worktree but not always. They are working on related (or the same) problems.
You are not alone.

You don't have to coordinate proactively — but when you suspect overlap, are
hitting a problem that feels like it should've been solved elsewhere, or just
want to know what's going on, you can read peer conversations.

## Tool

`claude-pod` reads peer Claude sessions' `.jsonl` files and renders readable
turns.

```
Usage: claude-pod [path] [flags]
       claude-pod --all [path] [flags]
       claude-pod --peers [path] [flags]
       claude-pod --session <id-or-name> [render flags]

Selection:
  no args                most-recent session in $PWD
  <path>                 most-recent session in that worktree
  --all [path]           list sessions in worktree, newest first
  --peers [path]         like --all but excludes $CLAUDE_CODE_SESSION_ID
  --session <id-or-name> show a specific session by UUID or /rename name
  --exclude <id-or-name> skip this session (repeatable; with --all/--peers/default)

Render (with default or --session):
  --turns N            render only the last N readable turns
  --since <when>       ISO 8601 timestamp or relative duration (30m, 2h, 1d)
  --follow, -f         stream new turns after historical render (humans only)

Examples:
  claude-pod
  claude-pod --peers
  claude-pod --session ee28f782-247b-4c7e-88c4-11417fa87154 --turns 20
  claude-pod --session axon-staging-19 --since 30m   # name set via /rename
  claude-pod -f --since 5m            # human terminal watcher
```

Worktree scope is the default; pass a path to look at peers in another
worktree.

## When to look

- You're about to edit a file and want to check no peer is mid-edit on it.
- You hit a problem that smells like it was solved nearby — check before
  re-deriving the fix.
- The user references something a peer said.

Don't poll. Don't read peers for entertainment — every read costs tokens.
