# Sandboxes vs Hooks: Two Approaches to Claude Code Autonomy

_chrismo here: very vibe-y, definitely needs editing_

The common advice for reducing Claude Code permission prompt friction is to run it in a container, VM, or sandbox. This doc captures the tradeoffs between that approach and the hook-based control layer used in this repo.

## The Problem

Claude Code's permission prompts interrupt flow. Every piped command, every `grep`, every unfamiliar bash invocation triggers a prompt. This kills autonomy and makes it hard to walk away and let Claude work.

## Approach 1: Sandboxes (Containers / VMs / Fly Sprites / EC2)

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

## Bottom Line

Sandboxes are great for people who don't have a rig and want autonomy fast. Hooks are better for people with heavily customized local environments who want control and visibility. The approaches aren't mutually exclusive — the ideal setup might be a sandbox for containment with hooks for tool quality discipline on top.
