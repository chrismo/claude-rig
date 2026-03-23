---
name: permission-mode
description: "Toggle Claude Code permission mode (default, acceptEdits, plan, dontAsk, bypassPermissions)"
---

Run the `permission-mode` command to toggle the Claude Code permission mode.

- If the user provided a mode argument (e.g., `/permission-mode dontAsk`), run: `permission-mode <mode>`
- If no argument, run: `permission-mode` (shows current mode and allow rules)

Valid modes:
- **default** — standard behavior, prompts for permission on first use
- **acceptEdits** — auto-accepts file edit permissions for the session
- **plan** — read-only, Claude can analyze but not modify or execute
- **dontAsk** — auto-denies tools unless pre-approved via allow rules (no prompts)
- **bypassPermissions** — skips all permission prompts (use only in sandboxed environments)

The mode change takes effect on the next Claude Code session, not the current one.
