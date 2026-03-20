---
name: permission-mode
description: "Toggle Claude Code permission mode (default, acceptEdits, plan, dontAsk, bypassPermissions)"
---

Set the Claude Code permission mode. The user may provide a mode name as an argument, or omit it to see the current mode and choose.

Valid modes:
- **default** — standard behavior, prompts for permission on first use
- **acceptEdits** — auto-accepts file edit permissions for the session
- **plan** — read-only, Claude can analyze but not modify or execute
- **dontAsk** — auto-denies tools unless pre-approved via allow rules (no prompts)
- **bypassPermissions** — skips all permission prompts (use only in sandboxed environments)

Steps:
1. Read `~/.claude/settings.json`
2. Show the current `permissions.defaultMode` value
3. If the user provided a mode argument, validate it against the list above. If no argument, ask which mode they want.
4. Use the Edit tool to update `permissions.defaultMode` in `~/.claude/settings.json`
5. Confirm the change

Note: The mode change takes effect on the next Claude Code session, not the current one.
