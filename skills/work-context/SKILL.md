---
name: work-context
description: Analyze current work context and recommend top priorities
allowed-tools: Bash
---

# Work Context - Priority Analysis

Collect current work context and analyze it to recommend the top 4 things to
focus on.

## Data Collection

Run this command to get structured data:

```bash
work-context data 7
```

This outputs JSON containing:
- **worktrees**: Git worktrees with branch names, age (days), and dirty status
- **cloud_sessions**: Claude web session branches with PR status (requires gh CLI)
- **standup**: (optional) Recent Linear issues with status and standup comments
- **conversations**: Recent Claude Code conversation topics grouped by date/project

Notes:
- Standup data is only available when a Linear integration is configured.
- Cloud sessions tracks branches matching `claude/*` or ending with 13-digit timestamps.

## Analysis Instructions

Analyze the data to recommend **top 4 priorities** for multitasking. Consider:

1. **Recency**: What was touched today or yesterday? Active work has momentum.
2. **Status**: What's In Progress vs QA vs blocked? QA items may need quick cleanup.
3. **Dependencies**: Are any items blocking others or waiting on external input?
4. **Quick wins**: Any items close to completion that could be finished quickly?
5. **Conversation context**: What topics have been actively discussed with Claude?

Cross-reference:
- Branch names often contain issue IDs (e.g., `proj-123-...`)
- Cloud session branches may have open PRs that need attention
- Standup contains issue status and recent comments
- Conversations show what you've been working on with Claude

## Output Format

```
## Top 4 Focus Areas

1. **[Issue/Branch]** - [Why this is a priority]
2. **[Issue/Branch]** - [Why this is a priority]
3. **[Issue/Branch]** - [Why this is a priority]
4. **[Issue/Branch]** - [Why this is a priority]

### Observations
- [Any stale work, blocked items, or things needing attention]
```
