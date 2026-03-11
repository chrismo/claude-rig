# claude-rig

Opinionated customizations for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) — agents, skills, a SuperDB-powered two-line statusline, a Ghostty tab-status system, and an installer to wire it all up.

## What's here

### `agents/`

Custom agent definitions (`.md` files) that get symlinked into `~/.claude/agents/`:

- **architecture-reviewer** — infrastructure and system design review
- **bash-reviewer** — bash code review and best practices
- **code-quality** — duplication, complexity, debug artifacts
- **design-reviewer** — DRY, SOLID, clean code
- **security-reviewer** — secrets, API security, infrastructure
- **superdb-expert** — SuperDB query specialist
- **test-expert** — test design, debugging failures, coverage

### `skills/`

User-level skills (slash commands) symlinked into `~/.claude/commands/`:

- **/plan** — spawn pre-implementation architecture and design review agents
- **/review** — spawn quality review agents before committing
- **/prove-it** — verify facts and assumptions before responding

### `statusline/`

A two-line statusline for Claude Code, powered by [SuperDB](https://superdb.org) (`super` CLI):

**Line 1:** project name | git branch+status | relative dir | Claude version | model + effort level | sandbox status

**Line 2:** hud bar | cost + duration | lines +/-  | context window %

Requires `super` (`brew install superdb/tap/super`). Line 2 also calls [`hud`](https://github.com/chrismo/hud) for an external status bar.

### `tab-status/`

Visual status indicators in Ghostty terminal tab titles for multi-Claude workflows. Colored circle emojis show what each Claude session is doing:

| Status | Emoji | Meaning |
|--------|-------|---------|
| active | 🟢 | Claude is working |
| waiting | 🟡 | Needs your input (permission prompt) |
| idle | ⚪ | Done, your turn |
| paused | 🔵 | Parked manually |
| blocked | 🔴 | Can't proceed |

Driven by Claude hooks that fire on prompt submit, permission request, tool use, and stop events. Includes a manual override system so you can park tabs without hooks clobbering the status.

See `tab-status/tab-status.md` for detailed flow diagrams.

### `install/`

- **`claude-installer.sh`** — one-time setup that symlinks agents, skills, and configures `~/.claude/settings.json` with the statusline command and tab-status hooks
- **`claude-bundle-spec.md`** — design spec for a future `claude-bundle init` CLI that sets up new repos with common settings, templates, and preferences

### `docs/`

- **`claude-rig-breakout-spec.md`** — how this repo was extracted from a monorepo
- **`multi-session-coordination.md`** — notes on orchestrating multiple Claude sessions
- **`mcp-slack.md`** — Slack MCP integration research
- **`block-claude-plugin.sh`** — script to block the JetBrains Claude plugin (if you prefer Claude Code over the IDE plugin)

## Install

Prerequisites: [SuperDB](https://superdb.org) for the statusline, [Ghostty](https://ghostty.org) for tab-status.

```bash
# Install super
brew install superdb/tap/super

# Clone and run the installer
git clone https://github.com/chrismo/claude-rig.git
cd claude-rig
bash install/claude-installer.sh
```

The installer:
1. Configures `~/.claude/settings.json` with the statusline command
2. Installs Claude hooks for tab-status (Ghostty tab colors)
3. Symlinks skills into `~/.claude/commands/`
4. Symlinks agents into `~/.claude/agents/`

For tab-status to update your Ghostty tab titles, source `tab-status/set-title.sh` from your `.zshrc` and ensure `tab-status` is on your PATH (the installer links it to `~/.local/bin/`).

## Dependencies

- **[SuperDB](https://superdb.org)** (`super`) — powers the statusline's data extraction and formatting
- **[Ghostty](https://ghostty.org)** — terminal emulator with tab title support (tab-status is Ghostty-specific)
- **[hud](https://github.com/chrismo/hud)** (optional) — external status bar displayed on statusline line 2
