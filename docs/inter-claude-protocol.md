# The inter-Claude messaging protocol

How one Claude Code session addresses and talks to another on the same machine.
Established against **2.1.224** by reading the shipped bundle with
`bin/claude-src` and verifying against live sessions. See
[reading-the-claude-binary.md](reading-the-claude-binary.md) for the extraction
method and its caveats — most importantly that identifiers are re-mangled every
build, so every citation below is a **string literal**, not a function name.

Two claims here are verified empirically, not just read. They're marked
**VERIFIED**. Everything else is read from source; where a claim is neither
verified nor directly read, it says so.

## 1. How the `[ref]` is derived — VERIFIED

`ListAgents` prints each row as `name [ref]`. The ref is a **SHA-256 of
`<kind>:<id>`, hex, truncated to 6 characters**, lengthened only as far as
needed to stay unique on the current roster.

The rendering is a one-liner:

```js
function zLe(e){return `${e.name} [${e.ref}]`}
```

The computation, and the collision walk that decides the length:

```js
function kLp(e,t){ return String(uu(`${e}:${t}`)) }   // hash of `kind:id`
var RLp = 6                                           // base length
// inside the roster builder:
let t = e.map(r => kLp(r.kind, r.id))
return e.map((r,n) => {
  let o = t[n], i = RLp
  while (i < o.length && t.some(s => s !== o && s.slice(0,i) === o.slice(0,i))) i++
  return {...r, ref: o.slice(0,i)}
})
```

For a peer session, `kind` is the literal `session` and `id` is that session's
`messagingSocketPath`. So:

```
ref = sha256("session:" + messagingSocketPath).hexdigest()[:6]
```

`uu` is the bundle's hash helper:

```js
function uu(e){ return yp(V_u.createHash("sha256").update(e).digest("hex").slice(0,12)) }
var V_u = require("crypto")
```

Note the **`.slice(0,12)`**: the digest is cut to 12 hex characters before the
ref logic ever sees it. So the collision walk above can lengthen a ref to at
most 12 characters, not 64 — with enough colliding sessions the loop exits on
`i < o.length` and returns a ref that is *not* unique. Nothing on a normal
machine will get near that.

This was also confirmed independently by result, before the definition was
found: of md5, sha1, sha256, sha512, blake2b, blake2s and sha3-256, only sha256
reproduced the observed refs, and it reproduced all four.

**Verification.** Computed from `~/.claude/sessions/*.json` and compared against
a live `ListAgents` roster:

```
name                   pid  computed ListAgents match
q-chat-rooms         21797  b58096   q-chat-rooms   OK
claude-rig-two       30571  1f4a1e   claude-rig-two OK
claude-rig-one       30739  2ee790   claude-rig-one OK
q-chat-rooms-6f      81153  3ca88e   q-chat-rooms-6f OK
```

Two consequences worth knowing. A ref is a function of the **socket path**, so
it is stable for a session's whole life and changes when the session restarts
(new PID → new path → new ref). And it is *not* derived from the session UUID —
searching `~/.claude/projects` for a transcript whose name starts with a ref
will never match.

## 2. The message envelope

The wire format is **newline-delimited JSON**, one message per line, 1MiB line
cap. The binary logs its own injection recipe at startup:

```
[uds-messaging] Inject messages: echo '{"type":"user","message":{"role":"user","content":"hello"}}' | socat - UNIX-CONNECT:<sock>
```

**VERIFIED** — a raw `AF_UNIX` write of exactly that shape (plus `\n`) into
another session's socket appeared in its conversation as a genuine user turn,
which it then answered. The write is fire-and-forget: nothing is returned on the
same connection.

### `type: "user"` — a message for the peer's conversation

What a real send puts on the wire:

```js
{...c, type:"user", message:{role:"user", content:l}, priority:"next", from:a,
 ...(n?.length ?? 0) > 0 && {file_attachments:n}}
```

`c` carries the generated `msg_id`. `from` is the sender's own socket address —
this is why a reply's `from` is a `uds:` path rather than the name you sent to.
`priority` is `next` for an ordinary send; `now` exists and is dispatched
differently (below). `file_attachments` is omitted entirely when empty.

### `type: "control"` — out-of-band actions

Two actions are handled; anything else is logged and dropped
(`Unhandled control action`):

- `rename` — carries a `name` string, renames the receiving session.
- `peer_message_status` — a delivery receipt (below).

### Delivery receipts

A sender is told what happened to a message it sent:

```js
{action:"peer_message_status", status:a, reason:tES(a), from:i,
 ...typeof l?.msg_id === "string" && {orig_msg_id: l.msg_id}}
```

`status` is one of `held`, `denied`, `expired`, `delivered`. The sender keeps a
bounded ring buffer of outstanding sends and matches receipts by `orig_msg_id`;
an unmatched receipt is dropped with:

```
[uds-messaging] peer_message_status dropped: no outstanding send matches orig_msg_id=…
```

Practically: **you can learn that a peer's human is sitting on your message**
(`held`) or refused it (`denied`). Nothing in claude-rig uses this yet.

### Dispatch ordering

A message that is `control`, or is `user` with `priority:"now"` and no
attachments, is processed immediately. Everything else is appended to a promise
chain and processed in order — so ordinary sends queue behind whatever the
receiver is already draining.

### Reply-address guard

Before sending a hold receipt, the reply address is checked to be in the same
socket directory and to end in `.sock`:

```
[uds-messaging] hold-receipt skipped: reply address outside our socket namespace (…)
```

So a peer cannot use the `from` field to redirect receipts at an arbitrary path.

## 3. Name resolution and pins — partial

Pins are ordinary session state, written through `setSendMessagePin(r, n)` and
reset to `{}` when the session's state is cleared. They are **in-memory and per
session**: a pin one session holds does nothing for another, and a restart drops
them.

The resolver's tail:

```js
let o = r === void 0 ? [] : n.filter((a) => a.name === r), s = (o.length > 0 ? o : n)[0]
if (s.where === "in-process") return {kind:"one", candidate:s}
return {kind:"ambiguous"}
```

Read plainly: a bare name resolves on its own **only** for an in-process agent —
one you spawned. For a peer session on this machine, a bare name returns
`ambiguous` even when exactly one candidate matches. That matches observation:
sending to a bare peer name failed with an error that named the ref, and the
same bare name worked afterwards.

**Not established:** the exact site where a pin is consulted to turn a bare name
back into a candidate. The pin write and the ambiguity branch are both located;
the read that joins them is not. The behaviour is confirmed from the outside
(ref once, bare name thereafter) but the code path is inferred.

## 4. Where roster metadata comes from — partial

The `name`, `kind`, `status` and uptime on a roster row are **not fetched from
the peer over the socket**. They are read from the peer's registry file,
`~/.claude/sessions/<pid>.json`, which every session writes about itself:

```js
Ie({pid: process.pid, sessionId: …, cwd: …, startedAt: Date.now(),
    procStart: …, version: …, peerProtocol: …, kind: r,
    entrypoint: …, ...s && {tmux: s},
    ...{messagingSocketPath: EPe.CLAUDE_CODE_MESSAGING_SOCKET},
    ...{name: …, nameSource: "derived", logPath: …, agent: …, jobId: …}})
```

The directory is created with mode `448` (octal `0700`). `messagingSocketPath`
is copied straight from the session's own `CLAUDE_CODE_MESSAGING_SOCKET`
environment variable — a session needs no discovery to know its own address.

Each file is parsed back into a peer record carrying `sock`, `cwd`, `startedAt`,
`procStart`, `name`, `kind`, `sessionId`, `jobId`, `parkedJobId`,
`bridgeSessionId`, `logPath`, `status`, `waitingFor`, `updatedAt`,
`statusUpdatedAt`, `entrypoint`, `agent`, `state`, `detail`, `tempo`, `needs`
and `peerProtocol`. The row is then rendered as:

```
name [ref]  ·  kind  ·  status  ·  [tmux <name>]  ·  started <n> ago
```

`kind` ∈ `interactive | bg | daemon | daemon-worker`;
`status` ∈ `busy | shell | idle | waiting`.

**Not established by this document:** that the roster also *connect-probes* each
socket before listing it. That claim comes from a peer session's reading of
`rfa()` and is plausible, but was not confirmed here. The indirect evidence is
weak: a decoy socket placed in `/tmp/cc-socks` named after a live non-Claude PID
never appeared on the roster — but that is equally explained by the registry
being the source of truth, since the decoy had no registry file at all. Treat
"present socket path ⇒ reachable" as *optimistic* either way: a registry file
can outlive the process that wrote it, which is why liveness is checked with
`kill(pid, 0)`.

## What this means for claude-rig

- A ref can be computed offline from a registry file — no roster call needed.
- `sessionId` in the registry is the transcript UUID, so a PID maps to a
  `.jsonl` without the mtime-rank guessing `claude-tabs` used to do.
- Any tool marking a session "messageable" from `messagingSocketPath` alone is
  making the optimistic claim above, and may disagree with `ListAgents`.
- Delivery receipts are an unused capability: a sender can find out that a
  message was held rather than read.
