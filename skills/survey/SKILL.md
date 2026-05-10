---
name: survey
description: "Portfolio archaeology: scan ALL local branches for forgotten/neglected work and rank by 'could Claude do something useful on this right now?'"
allowed-tools: Bash, Agent
---

# Survey — Forgotten Branch Archaeology

You are scanning every local branch to find work that was important but has been neglected. The goal is not recency (that's `/work-context`) and not a single branch deep-dive (that's `/autopilot`). This is: **what have I forgotten, and can Claude make progress on it right now?**

## Step 1 — Enumerate all local branches

Run these in parallel:

```bash
git for-each-ref --format='%(refname:short)|%(committerdate:unix)|%(committerdate:relative)|%(subject)' refs/heads/
```

```bash
git worktree list --porcelain
```

```bash
gh pr list --state open --json headRefName,number,title,state 2>/dev/null || true
```

## Step 2 — Filter and score candidates

For each branch, compute:
- **Days since last commit** (primary staleness signal)
- **Has open PR?** (importance signal — someone cares)
- **Diverged commits from main** (`git rev-list --count main...<branch>`) — invested work
- **Branch name contains issue ID?** (e.g. `proj-123`) — signals tracked work

**Exclude** immediately:
- `main`, `master`, `develop`, or your current branch
- Branches with 0 diverged commits from main and no open PR (nothing was done)
- Branches merged into main (check: `git branch --merged main`)
- Staging/deploy branches (names matching `staging-*`, `deploy-*`, `release-*`)

**Score** each remaining branch (higher = more interesting):
- +3 if has open PR
- +2 if diverged > 5 commits
- +2 if branch name contains a ticket/issue ID
- +1 per 7 days stale (capped at +5)
- −2 if diverged < 2 commits (may be abandoned stub)

Select the **top 5–8 by score** for deeper analysis.

## Step 3 — Spawn one Explore subagent per candidate

For each candidate branch, launch an Agent (subagent_type: Explore) in parallel. Each agent receives:

> "Investigate this branch: `<branch-name>`. Run:
> - `git log main...<branch> --oneline` — what's been committed
> - `git diff main...<branch> --stat` — scope of changes
> - `gh pr list --head <branch> --state all --json number,title,body,state,url` — PR info
> - grep for TODO/FIXME in files changed vs main
> - If a worktree exists for this branch, check its CLAUDE.md and memory/ directory
>
> Report (under 150 words): what's being built, what's done, what's obviously next, any blockers that would stop autonomous work, and a rough effort estimate if Claude ran autopilot on it now."

Do NOT spawn agents for branches you've already excluded.

## Step 4 — Synthesize into ranked output

After agents return, organize into sections:

```
## Forgotten Work — Branch Survey

<N branches scanned> | <M candidates> | top <K> shown

### Ready for autopilot (Claude can proceed now)
1. **branch-name** — <X days stale> | <N commits ahead> | [PR #NNN]
   What: [1-2 sentence description]
   Next: [concrete next action]
   Runway: ~N hours before needing input

### Needs one decision first
2. **branch-name** — [the specific question that unblocks it]

### Has open PR but stalled
3. **branch-name** — [what's blocking merge]

### Low signal / probably dead
4. **branch-name** — [why it didn't make the cut; safe to delete?]

### Observations
- [Patterns: lots of stale PRs, common blocker type, cluster of related branches, etc.]

---
Pick a branch and run /autopilot to go deep on it.
```

## Guidance on classification

- **Ready for autopilot**: Claude can write code/tests/docs on this right now without a decision from you. Clear next step, no blocking questions.
- **Needs one decision first**: The next action is clear but requires a choice only you can make (scope, naming, approach). Name the decision explicitly — don't just say "needs direction."
- **Has open PR but stalled**: Work is done but something is blocking merge — review, CI, a comment to address. Name it.
- **Low signal / probably dead**: Fewer than 2 commits, no PR, stale > 30 days. Flag as safe-to-delete candidate.

Keep the whole response tight. The user wants to pick a target and get moving, not read a report.
