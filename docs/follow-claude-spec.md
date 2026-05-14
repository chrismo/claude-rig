# follow-claude Skill Spec

**Status:** future idea, not built. Captured from conversation 2026-05-13.

## Problem

When running multiple Claude Code sessions in parallel (separate Ghostty panes / tabs), there's no first-class way for one Claude to observe another. Today the options are: copy/paste between panes, use `mta:*` shared-context skills (which require explicit registration), or roll your own tail of the transcript JSONL files.

Goal: a lightweight skill that lets the user point one Claude at one or more other live Claudes and have it follow along, no registration required on the followed side.

## Background: how Claude sessions are observable

Each Claude Code session writes a structured transcript to:

```
~/.claude/projects/<encoded-cwd>/<session-id>.jsonl
```

- Append-only, flushed live as turns happen.
- Each line is a JSON event: user message, assistant message, tool call, tool result.
- Far cleaner than `script(1)`-style PTY capture, which produces ANSI soup for TUI apps (Claude's own UI included).

This is the substrate the skill builds on.

## Why not `script(1)`

For human-in-the-loop scenarios (e.g. watching a `psql` session over SSM), wrapping the local terminal with `script -q -F <log> <command>` is the right answer — universal, app-agnostic, captures whatever hits the PTY. But for Claude↔Claude, both endpoints are full-screen TUIs, so `script` logs are dominated by alt-screen redraws and spinner frames. The JSONL transcripts already exist, already structured — use them.

## User experience

```
/follow-claude <session-id-or-prefix> [<session-id-or-prefix> ...]
```

- Full GUIDs or short prefixes (~8 chars).
- With no args: discovery mode — list all transcripts modified in the last N minutes across all `~/.claude/projects/*/` dirs, with cwd + last-message-time, and let the user pick.
- Dead/stale IDs (no mtime activity in the last N minutes; default 10) are reported and dropped, not errored on.

Companion skill `/whoami` (or similar): prints the current session's GUID so the user can paste it into the follower. Without this, finding your own session ID is annoying.

## Implementation sketch

Skill lives at `skills/follow-claude/SKILL.md` (symlinked by `install.sh` like the rest).

When invoked, the skill instructs the current Claude to:

1. **Resolve IDs to transcript paths.**
   ```
   find ~/.claude/projects -name "<prefix>*.jsonl"
   ```
   Support prefix matching. Reject ambiguous prefixes.

2. **Filter stale sessions.** Drop any whose `.jsonl` mtime is older than N minutes. Report the drops by short-id so the user knows which targets were ignored.

3. **Register survivors.** Write to a state file (e.g. `~/.claude/follow-claude/active.json`) so the follower can re-read it across turns without re-resolving:
   ```json
   [
     {"short_id": "a1b2c3d4", "cwd": "/path/to/...", "transcript_path": "...", "registered_at": "..."}
   ]
   ```

4. **Define the read protocol.** Skill body tells the follower how to consume:
   - On request ("what's a1b2 doing?"), Read the transcript tail.
   - Parse JSONL turns; surface user + assistant messages, suppress tool-call noise unless asked.
   - Prefix surfaced content with the short ID.

### Read model: pull, not push

Follower Claude reads transcripts on demand, not via a background `tail -F` + Monitor stream. Push mode burns context for events the follower doesn't need to react to. Pull keeps context lean and lets the user drive the question.

## Open questions

- **Scope:** transcripts only, or also surface `mta:*` shared-context files when present? They overlap but serve different purposes (`mta` is for explicit coordination; follow-claude is for ambient observation).
- **Discovery default:** should `/follow-claude` with no args auto-list candidates, or always require explicit IDs? Listing is friendlier; explicit is safer against accidentally tailing the wrong session.
- **Cross-host:** out of scope for v1. All sessions assumed to be on the same machine writing to the same `~/.claude/projects/` tree.

## Out of scope

- Bidirectional messaging — that's what `mta:*` and `claude -p` are for.
- Live streaming / Monitor integration — pull-on-demand is the v1 model.
- Filtering / redaction of sensitive content in transcripts — followers see whatever the followed session wrote.

## Related

- `mta:*` and `mtm:*` skills — productized version of multi-Claude coordination with explicit registration and shared context files.
- `docs/multi-session-coordination.md` — prior thinking on multi-session workflows.
- `script(1)` recipes (in conversation, not yet captured in docs) — the right tool for following a non-Claude terminal (e.g. psql over SSM).
