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

### What the receiver rejects

The server's own log lines enumerate its validation, and they're the cheapest
map of what it will refuse:

```
[uds-messaging] Ignoring message without valid type field
[uds-messaging] Ignoring user message with missing or non-string content
[uds-messaging] Dropping ${e.type} message: session_id mismatch
[uds-messaging] Buffer exceeded 1 MiB without newline
[uds-messaging] Failed to parse JSON line: …
[uds-messaging] Failed to materialize file_attachments: …
[uds-messaging] Routed user message to queue (priority=${i}): …
[uds-messaging] Skipped: cross-session messaging gate off
[uds-messaging] Skipped: remote thin client
[uds-messaging] Refusing non-local socket …
```

Two of these matter for anyone writing to a socket by hand. Malformed input is
**silently discarded** — the server logs and moves on rather than replying or
closing, so a probe with the wrong shape looks identical to a probe that was
ignored for any other reason. And a `session_id` mismatch drops the message, so
a wrong `session_id` fails quietly.

There are also two conditions under which a session never opens a socket at all
— the cross-session messaging gate being off, and running as a remote thin
client. Either produces a live session with no `messagingSocketPath`.

Sending has its own guards: a 5s timeout, and a refusal to connect anywhere
non-local (`Refusing to connect to non-local IPC path`). On macOS the writer
delays `end()` briefly after writing rather than closing immediately.

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

The pin is consulted in two places. On the **send** path it guards against a
name that has quietly re-pointed at a different session:

```js
let s = $B(i.name), a = Object.hasOwn(n.sendMessagePins, s) ? n.sendMessagePins[s] : void 0
if (a !== void 0 && a.id === i.id) return {kind:"proceed", pin:a}   // pin matches → send
if (a !== void 0) { let c = Vxr(e) !== null                          // explicit ref typed?
  if (!c && e === i.name && e !== a.name) return {kind:"proceed", pin:void 0}
  if (!c) { /* re-resolve against a freshly fetched roster */ } }
```

On the **resolve** path it turns a pinned name back into a target, and drops
itself when the target is gone or the name has moved:

```js
let s = r.find((a) => (i ? a.kind==="cloud-session" : a.kind==="session")
                       && a.where !== "in-process" && a.id === o.id)
if (s === void 0) { Oe("send_message_pin","stale"); return }         // pinned session gone
if (n !== void 0 && s.name !== n && r.some((a) => a.name === n)) return  // name now someone else's
return Se("send_message_pin"), s
```

That second guard is the interesting one: if the session you pinned has been
renamed *and* some other agent has since taken the old name, the pin refuses to
resolve rather than silently delivering to the wrong session.

**VERIFIED.** Three sends to one peer, in order:

| # | `to` | result |
|---|---|---|
| 1 | `claude-rig-one` (no pin yet) | rejected — ambiguity error naming the ref |
| 2 | `claude-rig-one [2ee790]` | delivered, pin written |
| 3 | `claude-rig-one` (bare again) | delivered |

So the rule is **ref once per peer per session, bare name thereafter** — and the
rejection in step 1 costs nothing, since it never reaches the peer.

Worth knowing from the receiving end: the peer cannot tell which of these it
got. Addressing is resolved entirely sender-side, so a bare-name send and a ref
send arrive byte-identical.

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

### The roster does connect-probe

Listing live peers reads the registry *and* probes every socket:

```js
async function rfa(){
  let e = WXo()                                               // own socket path
  let t = (await tfa()).filter((i) => i.sock && i.sock !== e) // has a socket, and isn't me
  let r = await Promise.all(t.map((i) => p1p(i.sock)))        // probe all, concurrently
  let n = Wt() !== "wsl", o = []
  for (let i = 0; i < t.length; i++){ let {file:s, ...a} = t[i]
    if (r[i]) o.push(a)                                       // probe answered → on the roster
    else if (n && !zC(a.pid)) nIr.unlink(s).catch(()=>{}) }   // no answer + dead pid → delete file
  return o }
```

The probe is a 250ms connect that never sends anything:

```js
function p1p(e){ return new Promise((t)=>{
  if(!Z_e(e)){ t(!1); return }
  let r = Qpa.connect({path:e}), n = (o)=>{ r.destroy(); t(o) }
  r.on("connect", ()=>n(!0))
  r.on("error", (o)=>n(zt(o)==="EBUSY"))    // EBUSY counts as alive
  r.setTimeout(250, ()=>n(!1)) }) }
```

Three consequences. A registry file whose socket no longer answers **and** whose
PID is dead is deleted as a side effect of listing — the roster garbage-collects
itself (skipped on WSL). `EBUSY` is treated as reachable, since a listener too
busy to accept is still a listener. And self-exclusion is by socket path
compared against `CLAUDE_CODE_MESSAGING_SOCKET`, which is why you never see
yourself on your own roster.

So `messagingSocketPath` present does **not** imply reachable: it means the
session claimed an address, not that anything still answers there. Any tool
marking sessions "messageable" from the field alone will disagree with
`ListAgents` on a session that died without cleaning up.

This also corrects an earlier guess of mine. A decoy socket placed in
`/tmp/cc-socks` was never contacted — not because of any process-identity check,
but because enumeration starts from `~/.claude/sessions/*.json` and the decoy had
no registry file. It was never a candidate to probe.

The registry read underneath it:

```js
async function tfa(){ let e = Xpa.join(Tn(), "sessions"), t
  try { t = await nIr.readdir(e) } catch { return [] }
  return (await Promise.all(t.filter((n) => /^\d+\.json$/.test(n)).map(async (n) => {
    let o = n.replace(/\.json$/, ""), i = parseInt(o, 10) …
```

The filename is the PID and is the only thing trusted to identify the file;
anything not matching `/^\d+\.json$/` is ignored.

## What this means for claude-rig

- A ref can be computed offline from a registry file — no roster call needed.
- `sessionId` in the registry is the transcript UUID, so a PID maps to a
  `.jsonl` without the mtime-rank guessing `claude-tabs` used to do.
- Any tool marking a session "messageable" from `messagingSocketPath` alone is
  making the optimistic claim above, and may disagree with `ListAgents`.
- Delivery receipts are an unused capability: a sender can find out that a
  message was held rather than read.
