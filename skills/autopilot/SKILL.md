---
name: autopilot
description: "Resume a (often neglected) branch/worktree: where we left off, and what has to be true before the user can engage autopilot and walk away for minutes or hours"
---

# Autopilot

It's a new day. The user is opening a branch or worktree they may not have touched in a while. Answer two questions, in this order.

## 1. Where did we leave off?

Investigate in parallel, then synthesize:

- `git status` — uncommitted changes, untracked files
- `git stash list` — anything stashed
- `git log --oneline -20` — recent commits on this branch
- `git log $(git merge-base HEAD @{u} 2>/dev/null || git merge-base HEAD main)..HEAD --oneline` — what's diverged from base
- `git branch --show-current` and how far ahead/behind its upstream
- `gh pr list --head "$(git branch --show-current)" --state all` — open or recently-closed PR for this branch
- Recent Claude session transcripts for this directory (try `claude-search` if available, otherwise `~/.claude/projects/<encoded-cwd>/`)
- Memory entries (`MEMORY.md` and the `memory/` directory) for project-type entries about this work
- TODO/FIXME comments in changed files

Report concisely:
- **What's being built / why** (one or two sentences)
- **What's done** (committed)
- **What's in flight** (uncommitted, stashed, or partial)
- **The next obvious step**

## 2. What has to be true before the user engages autopilot?

This is the load-bearing half of the skill. The user wants to step away and let you run for minutes or hours. List concrete impediments — anything that would force you to stop and ask them mid-flight. Be specific, not generic.

Categories to check:

- **Decisions** — design choices, naming, scope, tradeoffs you'd surface for approval
- **Access** — missing creds, API keys, services not running, sandbox restrictions, network hosts not allowlisted
- **Ambiguity** — requirements you can't infer from code, tickets, or memory
- **Validation gaps** — UI/integration behavior you can't verify yourself (no headless test, no staging env)
- **Destructive / irreversible ops** — force-push, deletes, migrations that need explicit approval
- **External blockers** — waiting on a review, a teammate, an unmerged dep
- **Test/build state** — failing tests, broken build, missing fixtures that would derail the next step

Rank impediments by how soon they'd interrupt sustained work — the thing that would stop you in the next 15 minutes is more important than the thing that would stop you in 3 hours.

## End with a runway estimate

Close the response with one line in this shape:

> If you resolve **[top 1–3 impediments]** now, I can run for **~N minutes/hours** on **[the next concrete tasks]** before I'd need to check in again.

Keep the whole response tight. The user is trying to get back into flow, not read a report.
