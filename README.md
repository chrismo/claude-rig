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

### `rules/`

User-level rules (`.md` files) symlinked into `~/.claude/rules/`. Loaded at the start of every Claude Code session across all projects.

- **tdd-preference** — prefer test-first when modifying code with an existing test suite; flag when coverage is missing
- **theory-vs-fact** — distinguish unproven theories from observed facts; don't present assumptions as conclusions
- **verify-before-closing** — don't assume a task is done after a PR merge; validate in production and close out remaining work

### `bin/`

CLI tools symlinked into `~/.local/bin/`:

- **permissions-audit** — consolidate allow/deny permission rules across git worktrees and global settings. Run from a repo root to discover `.claude/settings.local.json` in all worktrees plus `~/.claude/settings.json`. Flags: `--local-only` (skip global), `--sup` (structured output for piping into `super`).

### `skills/`

User-level skills symlinked into `~/.claude/skills/`:

- **/plan** — spawn pre-implementation architecture and design review agents
- **/review** — spawn quality review agents before committing
- **/prove-it** — verify facts and assumptions before responding
- **/claude-rig-init** — scaffolding helper for new claude-rig setups

**Tip:** Skills support inline shell execution with `` !`command` `` syntax in the markdown body. The command runs at invocation time and its output is injected as context before Claude sees the prompt. The built-in `/commit` skill uses this to pre-load `git status`, `git diff HEAD`, etc. Useful for building skills that need live system state.

### `statusline/`

A two-line statusline for Claude Code, powered by [SuperDB](https://superdb.org) (`super` CLI):

Both lines are plugin-driven — assembled from executable scripts in `statusline/plugins.d/`. Filename format is `<line>.<order>-<name>` (e.g. `1.10-project`, `2.50-cost`): the part before the dot selects the line, the part after controls ordering within it.

| Plugin | Segment |
|--------|---------|
| `1.10-project` | project name |
| `1.20-git` | git branch + status |
| `1.25-mta` | active MTA ticket (multi-Claude coordination) |
| `1.30-dir` | relative directory |
| `1.40-version` | Claude Code version |
| `1.50-model` | model + effort-level bars |
| `1.60-sandbox` | sandbox status |
| `2.10-hud` | [`hud`](https://github.com/chrismo/hud) status bar (optional, skipped if hud not installed) |
| `2.50-cost` | session cost + wall/API duration |
| `2.60-lines` | lines added/removed |
| `2.70-context` | context window usage % |
| `2.72-autocompact` | current `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` threshold |
| `2.75-rate-limits` | 5h / 7d rate-limit usage + reset |

Drop any executable into `plugins.d/` to add a segment. The script receives `CLAUDE_STATUS_INPUT` env var pointing to the session JSON. Output a string on stdout; empty output = segment skipped.

Override the plugin directory with `STATUSLINE_PLUGIN_DIR` env var.

Requires `super` (`brew install superdb/tap/super`).

### `hooks/`

**Auto-sandbox** (`ensure-sandbox.sh`) — a `SessionStart` hook that ensures sandbox mode is enabled on every new session, resume, and clear. Merges `sandbox.enabled: true` into `.claude/settings.local.json` using `super`. This is necessary because sandbox config only takes effect from `settings.local.json` — user-level and project-level `settings.json` are ignored.

**Dedicated tool enforcement** (`use-dedicated-tools.sh`) — a `PreToolUse` hook that intercepts Bash tool calls and denies commands that should use Claude Code's dedicated tools instead. This keeps Claude using the right tool for the job and avoids unnecessary permission prompts.

Denies CLI commands that have better built-in equivalents:

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
./install.sh
```

The installer:
1. Configures `~/.claude/settings.json` with the statusline command
2. Installs Claude hooks for tab-status (Ghostty tab colors)
3. Installs the `PreToolUse` hook to enforce dedicated tools and block compound Bash commands
4. Installs `SessionStart` hooks to auto-enable sandbox on startup, resume, and clear
5. Sets `env.CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=16` (preserves any existing override)
6. Merges `permissions/{allow,deny}.sup` into `~/.claude/settings.json`
7. Merges `sandbox/allow-write.sup` into the sandbox allowWrite list
8. Symlinks skills into `~/.claude/skills/`
9. Symlinks agents into `~/.claude/agents/`
10. Symlinks rules into `~/.claude/rules/`
11. Symlinks `cc-audit-rules/` into `~/.cc-audit/rules` when any `*.json` rules are present

For tab-status to update your Ghostty tab titles, source `tab-status/set-title.sh` from your `.zshrc` and ensure `tab-status` is on your PATH (the installer links it to `~/.local/bin/`).

## Dependencies

- **[SuperDB](https://superdb.org)** (`super`) — powers the statusline's data extraction and formatting
- **[Ghostty](https://ghostty.org)** — terminal emulator with tab title support (tab-status is Ghostty-specific)
- **[hud](https://github.com/chrismo/hud)** (optional) — external status bar displayed on statusline line 2
