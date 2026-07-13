---
name: pod-peer
description: You may have peer Claude sessions cooperating with you, and a human whose terminal is recorded — claude-pod lets you read what they're doing
allowed-tools: Bash
---

# pod-peer — you have peers

You may have other Claude sessions cooperating with you, often in the same
worktree but not always. They are working on related (or the same) problems.
You are not alone.

The human is a peer too. Their terminal — the one you never see — is where the
app actually runs, the test suite actually fails, and the stack trace actually
scrolls past. When they record it, you can read it.

You don't have to coordinate proactively — but when you suspect overlap, are
hitting a problem that feels like it should've been solved elsewhere, or just
want to know what's going on, you can read peer conversations.

## On invoking this skill, orient yourself

Run both, in the current working directory:

```
claude-pod --peers          # which other Claude sessions are in this worktree
claude-pod --console-list   # which of the human's terminals are recording
```

Both are cheap — one line per session, one per pane. They tell you *what exists*,
not what it says. Don't read any contents yet; read a session or a console when
you have a reason to (below). Report what you found in a sentence, so the human
knows what you can see.

Either may come back empty. That's a normal answer: no peers, or no console
recording. Don't treat it as a problem, and don't nag the human to start one —
mention it only if you actually need what it would contain.

The current worktree is the default scope. Everything below also takes a path,
so you can look into another worktree when the human points you at one.

## Tool

`claude-pod` reads peer Claude sessions' `.jsonl` files and renders readable
turns.

```
Usage: claude-pod <path> [flags]
       claude-pod --all [path] [flags]
       claude-pod --peers [path] [flags]
       claude-pod --session <id-or-name> [render flags]

Selection:
  <path>                 most-recent session in that worktree
  --all [path]           list sessions in worktree, newest first
  --peers [path]         like --all but excludes $CLAUDE_CODE_SESSION_ID
  --session <id-or-name> show a specific session by UUID or /rename name
  --exclude <id-or-name> skip this session (repeatable; with --all/--peers)

Render flags:
  --turns N            render only the last N readable turns (per-session;
                       not valid with --all/--peers)
  --since <when>       ISO 8601 timestamp or relative duration (30m, 2h, 1d)
  --follow, -f         stream new turns. Per-session: render historical then
                       follow. With --all/--peers: firehose — interleave new
                       turns from every matched session, tagged by short sid.

Examples:
  claude-pod .
  claude-pod --peers
  claude-pod --session ee28f782-247b-4c7e-88c4-11417fa87154 --turns 20
  claude-pod --session axon-staging-19 --since 30m   # name set via /rename
                                                     # cross-worktree
  claude-pod -f --since 5m .                          # human terminal watcher
  claude-pod --peers -f                               # firehose all peers
```

Worktree scope is the default; pass a path to look at peers in another
worktree.

## The human's consoles

The human can record a terminal with `script`, which mirrors everything they see
into a log file, live. Those logs are the one stream in the pod you cannot
otherwise reach: their dev server's output, the test run they just watched fail,
the command they ran three minutes before asking you about it.

One pane per concern, each in `.<tag>-console.log` at the worktree root —
`.main-console.log`, `.tests-console.log`, `.server-console.log`.

```
claude-pod --console-list         # which panes are recording: tag, modified, lines
claude-pod --console              # read every pane, each headed by its tag
claude-pod --console --tag tests  # just the test pane
claude-pod --console --tail 40    # last 40 lines per pane
claude-pod --record --tag tests   # the command the human runs to start that pane
```

Output is ANSI-stripped and progress-redraws are collapsed, so what you read is
roughly what their eye resolved on screen. `--console` reads *every* pane rather
than guessing at the relevant one — so check the heading above each block, and
attribute what you read to the right terminal. `$CLAUDE_CONSOLE_LOG` overrides
discovery entirely.

**A log outlives the terminal that wrote it.** Every heading and listing says
whether a pane is `live` (a `script` process still has it open) or `ended`, and
how long ago it was last written:

```
── tests  (.tests-console.log, ended, last write 6d ago)
── server (.server-console.log, live, last write just now)
```

An `ended` pane is history, not the current terminal. A week-old `ended` log says
nothing about what the human is doing now — don't reason from it as though it
were live, and don't report its contents as the current state of anything. If
what you need is what's happening *right now* and every pane is stale, say so and
offer `claude-pod --record`; don't quietly answer from the old log.

You cannot start a recording. `script` must wrap the human's interactive shell,
and your Bash tool has no tty — it dies with `tcgetattr/ioctl: Operation not
supported on socket`. When you want a console and none is recording, run
`claude-pod --record` and hand them the command; they start it.

Read a console when the human describes something they saw rather than pasting it
("the server blew up", "the test output looked weird") — go look instead of
asking them to copy-paste. It is also the honest way to see whether something
works in *their* environment rather than in a tool-call subshell.

## When to look

- You're about to edit a file and want to check no peer is mid-edit on it.
- You hit a problem that smells like it was solved nearby — check before
  re-deriving the fix.
- The user references something a peer said, or something they saw in their
  terminal.

Don't poll. Don't read peers for entertainment — every read costs tokens. On a
console, `--console-list` is the cheap look before the expensive one; prefer
`--tag` and a bounded `--tail N` once you know which pane you want. Don't
`--follow` a console: `-f` is for a human watching a pane, and would stream
every line of their terminal into your context.
