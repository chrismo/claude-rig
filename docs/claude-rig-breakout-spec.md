# claude-rig Breakout Spec

Extract Claude Code customizations from the brain repo into a standalone
`claude-rig` public repo for easy sharing.

## What Moves

### From `ai-agents/claude/`
| File | Purpose |
|------|---------|
| `statusline-command.sh` | Two-line status line (SuperDB-powered) |
| `test-statusline-command.sh` | Status line tests |
| `.sample.json` | Sample status line input |
| `claude-installer.sh` | One-time global setup script |
| `claude-bundle-spec.md` | Bundle/init system spec (in progress) |
| `multi-session-coordination.md` | Multi-session notes |
| `block-claude-plugin.sh` | Plugin blocker script |
| `agents/*.md` | architecture-reviewer, bash-reviewer, code-quality, design-reviewer, security-reviewer, test-expert |
| `skills/*.md` | plan, review, prove-it |
| `mcp/slack.md` | Slack MCP notes |

### From `xdg/.config/ghostty/`
| File | Purpose |
|------|---------|
| `tab-status.md` | Tab status system docs (mermaid diagrams) |
| `set-title.sh` | Shell title helper |

### From `xdg/.local/bin/`
| File | Purpose |
|------|---------|
| `tab-status` | CLI for Ghostty tab colored circles |

### From `.claude/agents/`
| File | Purpose |
|------|---------|
| `superdb-expert.md` | SuperDB query specialist (also lives at global `~/.claude/agents/`) |

## What Stays in brain

- `xdg/.config/ghostty/config` — personal Ghostty config, broader than Claude
- `shell/zshrc` — personal shell config
- CLAUDE.md — brain-repo-specific instructions
- `.claude/settings.local.json` — brain-repo-specific permissions

## Proposed Repo Structure

```
claude-rig/
  README.md
  agents/
    architecture-reviewer.md
    bash-reviewer.md
    code-quality.md
    design-reviewer.md
    security-reviewer.md
    superdb-expert.md
    test-expert.md
  skills/
    plan.md
    prove-it.md
    review.md
  statusline/
    statusline-command.sh
    test-statusline-command.sh
    sample-input.json
  tab-status/
    tab-status                  # CLI script
    tab-status.md               # docs
    set-title.sh                # shell helper
  install/
    claude-installer.sh
    claude-bundle-spec.md       # evolves into real installer
  docs/
    multi-session-coordination.md
    mcp-slack.md
    block-claude-plugin.sh
```

## Relationship to MTA

MTA stays separate. claude-rig is the "personal toolkit" layer:
- Agents, skills, status line, tab status, installer
- MTA is the multi-session coordination framework (its own repo already)
- The `/ds:*` commands stay as user-level commands in `~/.claude/commands/`
  since they're dscout-specific wrappers around MTA

## Migration Steps

1. Create `claude-rig` repo on GitHub
2. Copy files (not git history — these are small files, clean start is fine)
3. Update `~/.claude/settings.json` statusline path to point at new repo
4. Update any symlinks from `~/.claude/agents/` to new repo locations
5. Update brain repo references (remove moved files, leave a pointer)
6. Update claude-installer.sh to clone claude-rig instead of referencing brain

## Open Questions

- Should the `/ds:*` commands move here too, or stay user-level? They're
  dscout-specific but demonstrate the pattern.
- Does `hud` (called by statusline line 2) belong here or is it separate?
- The `claude-bundle-spec.md` vision of an init/setup CLI — does that become
  the install story for claude-rig, or stay a separate thing?
