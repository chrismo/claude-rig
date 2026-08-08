# The internals contract

claude-rig reads things Claude Code does not expose as a supported API. All of
it can change in a point release, without notice and without a changelog entry.

This file is the inventory of those assumptions. Each has an ID, and the same ID
names a test in [`bin/claude-contract.bats`](../bin/claude-contract.bats). The
suite is the executable half; this file is the half that says *why it matters*
and *what to do when it goes red*.

```bash
bats bin/claude-contract.bats
```

`hooks/internals-drift.sh` fires on SessionStart and tells you to run it
whenever the running version differs from `docs/verified-against`. It never
checks anything itself — Claude Code upgrades without running `install.sh`, so a
version change is simply the moment to look.

## Why a version bump is the trigger, not a failing assertion

An assertion can keep passing while the meaning underneath it changes. During
this work, `SendMessage`'s "there is no busy state" stayed literally true —
messages are never rejected for busyness — while the roster gained a visible
`status` field, which made the documented claim read as "no such field". Nothing
would have gone red. Only re-reading on a version change catches that class.

So: green suite plus a stale stamp means *unverified*, not *fine*.

## The assumptions

### A — peer messaging (source anchors)

Checked by grepping the installed bundle with `bin/claude-src`. Anchors are
string literals, never identifiers: identifiers are re-mangled every build, so
asserting on one would fail for a rename that broke nothing.

| ID | Assumption | Relied on by | If it fails |
|---|---|---|---|
| A1 | The `uds-messaging` subsystem exists | `pod-peer` skill, [protocol doc](inter-claude-protocol.md) | Peer messaging was restructured. Re-read the module before trusting anything in the protocol doc. |
| A2 | Sessions advertise a socket via `messagingSocketPath` | `claude-tabs`, reachability marking | Reachability can no longer be read from the registry. Find the new field. |
| A3 | A session learns its own address from `CLAUDE_CODE_MESSAGING_SOCKET` | self-identification | Self-exclusion from rosters may break; find the new source. |
| A4 | Wire format is newline-delimited JSON (the logged `Inject messages` recipe) | any hand-written socket write | Direct socket injection is unsafe. Stop writing to sockets until re-derived. |
| A5 | Refs are `sha256(...)` cut to 12 (`digest("hex").slice(0,12)`) | offline ref computation | Every computed ref is wrong. Re-derive before using refs anywhere. |
| A6 | Bare-name sends are gated by `sendMessagePins` | `pod-peer` guidance on addressing | The "ref once, then bare name" rule may no longer hold. Re-check the skill's addressing section. |
| A7 | Sockets live under `cc-socks` | protocol doc, any socket path building | Socket discovery paths are wrong. |

### B — the session registry

`~/.claude/sessions/<pid>.json`, one file per running session.

| ID | Assumption | Relied on by | If it fails |
|---|---|---|---|
| B1 | The registry directory exists | `claude-tabs`, `claude-pod` | Session discovery is gone; `claude-tabs` falls back to nothing. Check whether it moved before rewriting anything. |
| B2 | Files are named `<pid>.json` | `claude-tabs read_registry` | The filename is how the PID is known. A rename breaks liveness checks. |
| B3 | Records carry `pid`, `sessionId`, `cwd`, `kind`, `status`, `startedAt` | `claude-tabs`, `claude-pod` name map | Whichever field vanished — `sessionId` is the worst, it's the transcript join. |
| B4 | `kind` ∈ `interactive\|bg\|daemon\|daemon-worker`, `status` ∈ `busy\|shell\|idle\|waiting` | status rendering | A new value renders as garbage rather than crashing. Add it. |

### E — addressability (what `claude-peer --ask` stands on)

`--ask` is a shipped feature that depends on being able to *join* the roster,
not just read it. That is a deeper dependency than anything else here: it writes
into Claude's own registry directory.

| ID | Assumption | Relied on by | If it fails |
|---|---|---|---|
| E1 | The registry directory is writable by us | `claude-peer --ask` | `--ask` cannot register and must fail loudly rather than hang. Check whether Claude started policing the directory. |
| E2 | A roster entry needs only a live pid + an answering socket — no proof of being a real Claude | `claude-peer --ask` | Registration is being validated somehow (signature, cookie, process identity). `--ask` is dead; fall back to reading the peer's transcript for its reply. |
| E3 | Attribution is a text wrapper inside `message.content`, not a verified field | `--ask` reply parsing | The envelope moved. `--ask` will print protocol furniture, or nothing, instead of the answer. |

E2 is the one to watch. It is the assumption most likely to be deliberately
closed off, precisely because it is what lets a non-Claude process pose as a
peer — and if it is closed off, that is a *reasonable* change to make, not a
bug. Do not work around it; switch `--ask` to transcript-tailing instead.

### C — transcripts

The widest blast radius in the repo: seven scripts read these
(`claude-pod`, `claude-search`, `claude-tabs`, `work-context`, and the three
`session-*.sh`). It is also the surface most likely to change quietly, because
it is a data format rather than a mechanism.

| ID | Assumption | Relied on by | If it fails |
|---|---|---|---|
| C1 | The projects dir encodes a worktree as `-Users-name-…` | every transcript reader | No script can find the right directory for a worktree. |
| C2 | Transcript lines are JSON objects with `.type` | every transcript reader | Rendering and filtering break wholesale. |
| C3 | `user`/`assistant` records nest content under `.message.content` | `claude-pod` rendering, usage scripts | Conversations render empty. |

### D — the stamp

| ID | Assumption | If it fails |
|---|---|---|
| D1 | `docs/verified-against` matches the running build | Not a breakage. The assumptions were confirmed against a different build. Re-verify — **including the behavioural checks below** — then bump the file. |

## What is automated, and the one thing that isn't

`bin/claude-peer` reimplements discovery, ref derivation and sending in the
shell, so most of the behavioural half is now machine-checkable — `bats
bin/claude-peer.bats` stands up real unix sockets and exercises the probe and
the send for real:

- **Roster contents** — `claude-peer --list` builds its own roster from the
  registry plus a connect probe. Compare it against a Claude session's
  `ListAgents` output; the names and refs should match row for row.
- **Ref derivation** — computed with `shasum -a 256` and asserted in the suite.
- **Reachability** — asserted directly: a socket file with no listener behind it
  must not appear, and a send to it must fail.
- **Delivery** — a full round trip (write to a socket, confirm the bytes land)
  runs against a real listener in the suite.

**The one genuinely manual check is Claude's tool layer**, because bash cannot
call `SendMessage`:

- **The addressing rule.** Send to a peer by bare name with no prior pin: it
  should be rejected with an error naming the ref. Send with the ref: it should
  land. Send bare again: it should land. A change here means the `pod-peer`
  skill's addressing guidance is wrong.

That distinction matters: `claude-peer` proves the *transport and registry*
still work. It cannot prove that Claude's own resolver, pins and message
envelope are unchanged, because it deliberately bypasses all three.

Recorded in [inter-claude-protocol.md](inter-claude-protocol.md) with the exact
commands and their last observed output.

## When something goes red

1. **Don't rewrite the consumer first.** Find out what the mechanism became —
   `bin/claude-src` with a string literal from the same area is usually two or
   three hops from the answer. See [reading-the-claude-binary.md](reading-the-claude-binary.md).
2. **Update the doc that owns the claim**, not just the test. Each row above
   names one.
3. **Then** fix the consumer, and only then bump `docs/verified-against`.

Bumping the stamp is the last step, and it asserts something specific: that
every A–C assertion passed *and* the four behavioural checks were run. Bumping
it to silence the hook without doing the second half is how this whole thing
quietly stops being true.

## Adding an assumption

When you make something in claude-rig depend on a new Claude Code internal, add
a row here and a matching test. The rule of thumb: if a Claude Code release
could break it and you would not find out until a user hit the bug, it belongs
in the contract.
