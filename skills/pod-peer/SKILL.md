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

Source:
  --codex                read Codex (~/.codex) sessions instead of Claude's

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

## Codex peers

A peer in the same worktree may be Codex (the OpenAI CLI), not Claude. `--codex`
points every selection and render flag at `~/.codex` instead of Claude's
sessions, so you can read what a Codex peer is doing exactly as you'd read a
Claude one:

```
claude-pod --codex --peers          # Codex sessions in this worktree
claude-pod --codex --peers --new    # …only what they've said since you looked
claude-pod --codex --session <uuid> # a specific Codex rollout, by UUID
```

It's a separate source: `claude-pod --peers` shows Claude peers, `claude-pod
--codex --peers` shows Codex peers. When you suspect a Codex peer is in the
worktree, run both. Three things Codex doesn't support: `--session` by name
(Codex records no `/rename`), `--all/--peers -f` firehose (use `--new`), and
`--console`/`--record` (those read the human's terminal, which has no source).

Codex prepends each session with injected `<environment_context>` and
`<user_instructions>` turns — orientation boilerplate, not conversation. Skim
past them.

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

Don't read peers for entertainment — every read costs tokens. `--console-list`
and `--peers` are the cheap look before the expensive one.

## Keeping up, without burning tokens

**The unit of cost is a model turn, not a byte.** Anything that re-invokes you
costs a turn; anything that doesn't is free. That single fact decides everything
below.

### `--new` — read only what you haven't seen

`--tail N` and `--turns N` re-read what you already read. The more often you check,
the more you pay to re-read your own history. `--new` returns only what arrived
since *you* last looked, and remembers your position per stream:

```
claude-pod --console --tag tests --new   # only what that pane printed since last time
claude-pod --peers --new                 # only what each peer said since last time
```

Use `--new` for every catch-up read. Keep `--tail`/`--turns` for the first look at
something, or when you deliberately want history. `--new` tells you plainly when
nothing has changed, and recovers on its own when the human re-records a pane
(`script` truncates on start, so this is routine).

### The ladder — start at the top

**1. Pull on demand. This is the default.** Zero cost while idle. Read when the
human mentions something they saw, when a peer might overlap your work, or at a
natural checkpoint. Right for slow, multitasked work — which is most work. Stay
here unless there's a reason to leave.

**2. Waiting for one specific thing?** Use Bash `run_in_background` with a
condition that *exits*:

```
until grep -q "Ready in" .server-console.log; do sleep 1; done
```

Exactly one turn, when it trips. Right for "tell me when the suite finishes."

**3. High attention (an outage, a live debugging session)? Use Monitor as a
coalescing doorbell.**

Monitor turns **every stdout line into a model turn**. So piping a raw `tail -f`
into it costs a turn *per log line* — that, and not Monitor itself, is what makes
a watch "chatty." But the fix is *not* a keyword grep: any keyword list can miss
the thing that mattered.

Separate the two jobs. **The monitor decides when you wake. `--new` decides what
you read.** Wake on *any* new output, coalesced on an interval:

```bash
LOG=.prod-console.log
prev=$(wc -l < "$LOG")
while true; do
  sleep 20
  cur=$(wc -l < "$LOG")
  [ "$cur" -ne "$prev" ] && echo "$((cur - prev)) new lines in prod pane"
  prev=$cur
done
```

At most one turn per interval, and only when something actually happened. **Cost is
bounded by wall-clock, not by log volume** — a log screaming ten thousand lines a
second costs the same as one dribbling out three. When it fires, pull the content
with `claude-pod --console --tag prod --new`, and send a PushNotification if the
human would want to act on it now. Tighten the interval for more currency; loosen
it to spend less.

Nothing is missed: the doorbell doesn't judge importance, it only says "there's new
output" — and `--new` then hands you all of it.

A keyword filter (`tail -f "$LOG" | grep -E --line-buffered 'FATAL|Traceback|panic'`)
is worth adding only as a *second, faster* doorbell for "wake me instantly for a
catastrophe." It is an urgency hint, never your coverage. If you use one, remember
**silence is not success** — a filter matching only the happy path stays quiet
through a crashloop, and quiet looks exactly like healthy.

**4. Don't poll on a timer.** `/loop`, cron, a scheduled wake-up: each pays a full
turn per tick whether or not anything happened. The doorbell above is strictly
better — same interval, silent when nothing changed.

**`--follow` is for humans, not for you.** On a console it streams every line of a
terminal into your context; on `--peers` it's a firehose of every peer's turns.
It's meant for a human watching a terminal pane, where it costs nothing.
