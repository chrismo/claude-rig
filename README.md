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
- **/permission-mode** — toggle Claude Code permission mode (default, acceptEdits, plan, dontAsk, bypassPermissions)

### `statusline/`

A two-line statusline for Claude Code, powered by [SuperDB](https://superdb.org) (`super` CLI):

**Line 1:** project name | git branch+status | relative dir | Claude version | model + effort level | permission mode | sandbox status

**Line 2:** plugin-driven — assembled from executable scripts in `statusline/plugins.d/`:

| Plugin | Segment |
|--------|---------|
| `10-hud` | [`hud`](https://github.com/chrismo/hud) status bar (optional, skipped if hud not installed) |
| `50-cost` | session cost + wall/API duration |
| `60-lines` | lines added/removed |
| `70-context` | context window usage % |

Drop any executable into `plugins.d/` to add a segment. Numeric prefix controls ordering. The script receives `CLAUDE_STATUS_INPUT` env var pointing to the session JSON. Output a string on stdout; empty output = segment skipped.

Override the plugin directory with `STATUSLINE_PLUGIN_DIR` env var.

Requires `super` (`brew install superdb/tap/super`).

### `hooks/`

A `PreToolUse` hook that intercepts Bash tool calls and denies commands that should use Claude Code's dedicated tools instead. This keeps Claude using the right tool for the job and avoids unnecessary permission prompts.

**Dedicated tool enforcement** — denies CLI commands that have better built-in equivalents:

| Denied command | Use instead |
|----------------|-------------|
| `grep`, `rg` | Grep tool |
| `find` | Glob tool |
| `cat`, `head`, `tail` | Read tool |
| `sed`, `awk` | Edit tool |
| `echo`/`printf` with `>` redirect | Write tool |
| `super` CLI | SuperDB MCP tools |
| `python`/`python3` with json ops | SuperDB MCP tools |

**Compound command blocking** — denies pipes (`|`), chains (`&&`, `||`), and semicolons (`;`), which typically trigger permission prompts and can be broken into separate tool calls.

**Trade-off:** Both of these increase token usage — denied commands cost a round-trip, and splitting compound commands into separate tool calls means more calls (and more tokens) than a single one-liner would have used. The bet is that fewer permission prompts and better tool usage are worth the extra tokens.

Denied commands get a JSON response telling Claude which tool to use instead. Logs decisions to `~/.claude/logs/dedicated-tools-hook.sup`. Includes a bats test suite.

Monitor the log in a separate terminal:

```bash
watch -n1 tail -n 20 ~/.claude/logs/dedicated-tools-hook.sup
```

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

- **`claude-installer.sh`** — one-time setup that symlinks agents, skills, and configures `~/.claude/settings.json` with the statusline command, tab-status hooks, and the dedicated-tools PreToolUse hook
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
3. Installs the `PreToolUse` hook to enforce dedicated tools and block compound Bash commands
4. Symlinks skills into `~/.claude/commands/`
5. Symlinks agents into `~/.claude/agents/`

For tab-status to update your Ghostty tab titles, source `tab-status/set-title.sh` from your `.zshrc` and ensure `tab-status` is on your PATH (the installer links it to `~/.local/bin/`).

## Dependencies

- **[SuperDB](https://superdb.org)** (`super`) — powers the statusline's data extraction and formatting
- **[Ghostty](https://ghostty.org)** — terminal emulator with tab title support (tab-status is Ghostty-specific)
- **[hud](https://github.com/chrismo/hud)** (optional) — external status bar displayed on statusline line 2
