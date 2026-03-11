# Claude Bundle System - Spec

## Problem

When working in new repos, all Claude preferences/commands/customizations are
missing:
- Custom statusline
- Custom slash commands (`/superdb-expert`, etc.)
- Custom agents
- Project-level settings (sandbox, permissions)
- Common CLAUDE.md preferences (git commit format, etc.)

## Current Setup (brain repo)

| Component | Location | Scope |
|-----------|----------|-------|
| `statusline-command.sh` | `ai-agents/claude/` | Global (settings.json) |
| `claude-installer.sh` | `ai-agents/claude/` | One-time global setup |
| Custom commands | `ai-agents/claude/commands/*.md` | Global (symlinked) |
| Custom agents | `.claude/agents/` | Project-level |
| settings.local.json | `.claude/` | Project-level |
| CLAUDE.md | repo root | Project-level |

## Design Decisions

1. **Symlinks back to brain repo are acceptable** - centralized updates, brain
   repo must exist
2. **CLAUDE.md: Include directive approach** - add reference to shared
   preferences file rather than injection
3. **Profiles (superdb vs web, etc.)**: Future consideration, not v1

## Solution: `claude-bundle` CLI

### Directory Structure

```
ai-agents/claude/
  bundle/
    claude-bundle              # Main CLI script (symlink to ~/bin)
    lib/
      init.sh                  # Initialize new repo
      status.sh                # Show what's installed
      merge-settings.sh        # Merge settings using super
    templates/
      settings.local.json      # Common baseline (mirrors real structure)
      CLAUDE.md                # Minimal starter (if none exists)
    preferences/
      common.md                # Shared preferences (git commit format, etc.)
```

### CLI Commands

#### `claude-bundle init`

```bash
claude-bundle init [--full]
```

1. Create `.claude/` directory if needed
2. Copy `settings.local.json` template (sandbox defaults)
3. Symlink common agents from brain repo
4. Handle CLAUDE.md:
   - If exists: optionally append include directive
   - If not: create from minimal template with include

#### `claude-bundle status`

```bash
claude-bundle status
```

Shows what's installed, symlinks vs copies, brain repo connection status.

### CLAUDE.md Include Approach

Instead of injecting content, add a directive at the top of CLAUDE.md:

```markdown
For additional preferences, also follow:
~/modev/brain/ai-agents/claude/bundle/preferences/common.md
```

The `preferences/common.md` file contains things like:
- Git commit format preferences
- Code style preferences
- Common tool usage patterns

### Default Templates

#### `templates/settings.local.json`

Common baseline - mirrors the real settings.local.json structure:

```json
{
  "permissions": {
    "allow": [
      "WebFetch(domain:github.com)",
      "WebFetch(domain:superdb.org)",
      "WebSearch",
      "Bash(gh search:*)",
      "Bash(gh api:*)"
    ],
    "deny": []
  },
  "sandbox": {
    "enabled": true,
    "autoAllowBashIfSandboxed": true
  }
}
```

#### Merging Strategy

Uses `super` to merge into existing settings.local.json:

```bash
# Merge common settings into existing (additive for arrays)
super -J -c '
  permissions.allow := (
    [...this.permissions.allow?, ...other.permissions.allow?] | union
  ),
  sandbox := {...this.sandbox?, ...other.sandbox?}
' existing.json template.json
```

This allows:
- Additive merging for permissions (doesn't clobber existing)
- Per-repo customization on top of common base
- If no existing file, just copy the template

#### `preferences/common.md`

```markdown
# Common Claude Preferences

## Git Commits
- Use conventional commit format when possible
- End commit messages with the Claude co-author line
- etc.
```

## Implementation Steps

### Phase 1: Template Library
- [ ] Create `ai-agents/claude/bundle/` directory structure
- [ ] Create `templates/settings.local.json` with common baseline
- [ ] Create minimal `CLAUDE.md` template
- [ ] Create `preferences/common.md` with shared preferences

### Phase 2: Settings Merging
- [ ] Create `lib/merge-settings.sh` using super
- [ ] Test additive merge with existing settings.local.json
- [ ] Handle case where settings.local.json doesn't exist (just copy)

### Phase 3: CLI Script
- [ ] Create `claude-bundle` main script
- [ ] Implement `init` command (creates .claude/, merges permissions)
- [ ] Implement `status` command
- [ ] Add to PATH (update claude-installer.sh or document manual step)

### Phase 4: Agent Symlinks
- [ ] Add agent symlinking to init (link brain repo agents)
- [ ] Handle case where agent already exists

### Phase 5: Documentation
- [ ] Add usage examples for common scenarios

## Future Considerations (Not v1)

- **Profiles/presets**: `claude-bundle init --profile=superdb` for
  domain-specific setups
- **Update command**: `claude-bundle update` to refresh templates
- **Unlink command**: Remove bundle components from a repo

## TODO

- [ ] Include `/recap` command from devlog repo (`claude-recap.sh`) - summarizes
  last 7d of Claude history across all projects. Figure out how to bundle this
  (symlink to devlog? copy script? make it a user-level command?)

## Files to Create

- `ai-agents/claude/bundle/claude-bundle` (main CLI)
- `ai-agents/claude/bundle/lib/init.sh`
- `ai-agents/claude/bundle/lib/status.sh`
- `ai-agents/claude/bundle/lib/merge-settings.sh`
- `ai-agents/claude/bundle/templates/settings.local.json`
- `ai-agents/claude/bundle/templates/CLAUDE.md`
- `ai-agents/claude/bundle/preferences/common.md`
