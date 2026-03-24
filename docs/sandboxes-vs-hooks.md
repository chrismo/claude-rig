# Sandboxes vs Hooks: Two Approaches to Claude Code Autonomy

_chrismo here: very vibe-y, definitely needs editing_

The common advice for reducing Claude Code permission prompt friction is to run it in a container, VM, or sandbox. This doc captures the tradeoffs between that approach and the hook-based control layer used in this repo.

## The Problem

Claude Code's permission prompts interrupt flow. Every piped command, every `grep`, every unfamiliar bash invocation triggers a prompt. This kills autonomy and makes it hard to walk away and let Claude work.

## Approach 1a: Claude Code's Built-in Sandbox (`/sandbox`)

Claude Code has a built-in sandbox mode that restricts Bash commands at the OS level — filesystem and network access are limited to the project directory and allowed domains. Enable via `/sandbox` or `sandbox.enabled` in settings.

**What it does:** Constrains Bash subprocesses only. Edit/Write/Read are Claude's own tools and operate outside the sandbox, so they still follow normal permission rules.

**What it doesn't do:** Eliminate permission prompts. You still get prompted for Edit/Write (session-scoped approval) and for Bash commands not in your allow list. With `sandbox.autoAllowBashIfSandboxed: true`, Bash prompts go away since the sandbox contains the blast radius — but file tool prompts remain.

**Gotcha:** If set in `~/.claude/settings.json` (global), it applies to all sessions across all projects. Project-level `.claude/settings.local.json` is more appropriate for per-repo control.

This is complementary to external sandboxes and hooks — it's another layer, not a replacement for either.

## Approach 1b: External Sandboxes (Containers / VMs / Fly Sprites / EC2)

Run Claude in an isolated environment where everything is safe to auto-allow.

### Pros

- Eliminates permission prompts entirely — auto-allow everything
- Unlocks true autonomy — walk away for 20 minutes
- Blast radius is contained (though not literally zero — network access, mounted volumes, and credential leakage are still concerns)
- Simple mental model: let it run, it can't hurt anything

### Cons

- Prompt injection risk increases — if Claude gets tricked by malicious content in a webpage or repo, the injected instructions execute in a fully permissive environment with no permission prompt to catch it. Sandbox escapes are real: [Snowflake AI escapes sandbox and executes malware](https://www.promptarmor.com/resources/snowflake-ai-escapes-sandbox-and-executes-malware)
- You lose your local environment — custom tools, dotfiles, CLIs, your whole rig
- Rebuilding your environment in a VM means maintaining images, syncing files, dealing with latency
- Doesn't improve tool quality — Claude still uses sloppy 5-command pipelines when a single Grep call would do, and you have a harder time reviewing what it did
- Best fit for generic setups (standard toolchains, VS Code); worse fit for heavily customized local environments

## Approach 2: Hooks + Dedicated Tool Enforcement (This Repo)

Stay on the local machine. Use PreToolUse hooks to steer Claude toward better tool choices and block commands that trigger unnecessary prompts.

### Pros

- Preserves your local environment — all your tools, all your customizations
- Improves tool quality, not just safety — Claude uses Read/Grep/Edit which produce structured, reviewable output
- Acts as an allowlist-style filter regardless of *why* Claude is running something (including prompt injection)
- Composable — you can always add a sandbox later and it layers on top
- You learn more about how Claude works by engaging with its tool dispatch directly

### Cons

- Increases token usage — denied commands cost a round-trip, split compound commands mean more tool calls
- Reduces permission prompts indirectly rather than eliminating them
- More effort to build and maintain than just pointing Claude at a container
- Compound command blocking catches legitimate commands (e.g., `git log | head -5`) that happen to use pipes

## Approach 3: Static Analysis of Settings (CC Lint — WIP)

A third leg that neither approach covers: analyzing your allow/deny configuration for coherence. Sandboxes don't help you understand your own settings. Hooks only fire at runtime. A lint tool can catch things like "you allowed `Bash(*)` which makes half your other rules meaningless."

## Approach 4: `dontAsk` Permission Mode

Claude Code's built-in `dontAsk` mode auto-denies any tool not explicitly in your `permissions.allow` list. No prompts at all — if it's not allowed, it's silently denied.

### What we found (tested 2026-03-23)

**It's startup-only.** Set via `claude --permission-mode dontAsk` or `defaultMode` in settings.json. Changes to settings.json don't take effect mid-session. The built-in shift+tab mode cycler only rotates through default/acceptEdits/plan — `dontAsk` is excluded. If you shift+tab away from it, you have to restart to get back.

**Session-scoped tools become blockers.** Claude Code has two persistence models for "yes, don't ask again":

| Tool type | Persistence |
|---|---|
| Bash commands | Permanently per project (written to settings.local.json) |
| File modification (Edit/Write) | Session-only (never persisted) |

In `default` mode, you approve Edit/Write once per session and forget about it. In `dontAsk` mode, that approval never happens — the tools just get denied. So you need `Edit` and `Write` in your allow list, which nobody would naturally have because they've never needed to add them explicitly.

**Denial kills momentum, hooks redirect.** When a PreToolUse hook denies a command, it provides a reason ("use Grep instead") and Claude self-corrects on the next attempt. When `dontAsk` denies, the message tells Claude not to work around the restriction and to stop and explain if it thinks the capability is essential. For tools with no alternative (like Write for new files), Claude just stops.

**The name is misleading.** `dontAsk` sounds permissive — "don't ask me, just do it." The actual behavior is the opposite: "don't ask, just deny." A name like `autoDeny` or `allowlistOnly` would communicate what it actually does.

### When it might work

- Headless/CI pipelines where you know exactly which tools are needed and pre-configure them all (including Edit and Write)
- Sessions where you only need Claude to read, search, and run specific pre-approved commands

### When it doesn't work (out of the box)

- Interactive development — too many tools are session-approved by default and don't show up in allow lists
- Any workflow that creates new files (Write) unless you've added `Write` to your allow list
- You can't combine `dontAsk` (deny unapproved) with `acceptEdits` (auto-approve file tools) — it's one mode, not a composition

### Next steps

Don't give up on `dontAsk` yet. The gaps are knowable and fixable — adding `Edit` and `Write` to the allow list is straightforward, and the `permissions-audit` script can surface what else is missing. The real question is whether a well-curated allow list + `dontAsk` can eliminate enough prompts to be worth the setup effort. Needs more hands-on time to find out.

## Bottom Line

Sandboxes are great for people who don't have a rig and want autonomy fast. Hooks are better for people with heavily customized local environments who want control and visibility. `dontAsk` mode is interesting in theory but has practical gaps for interactive development. The approaches aren't mutually exclusive — the ideal setup might be a sandbox for containment with hooks for tool quality discipline on top.
