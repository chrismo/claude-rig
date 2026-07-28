# Workflow scripting notes

Reference notes on Claude Code's `Workflow` tool — how an orchestration script
actually communicates with its subagents, and which parts of the API aren't in
the public docs.

Companion script: [`agent-comms-demo.workflow.js`](agent-comms-demo.workflow.js).
Not installed by `install.sh` — it's a teaching artifact, not part of the rig.

## There is no message bus

A workflow script is plain JavaScript in a single process. Subagents are
separate Claude contexts that share nothing — not with each other, not with the
script, not with the orchestrating session. Three channels exist:

1. **Script → agent: the prompt string.** The only input. If agent B needs what
   agent A produced, the script interpolates it: ``agent(`Fix: ${found}`)``.
   There is no implicit context inheritance.
2. **Agent → script: the final assistant text.** Pass a `schema` (JSON Schema)
   and the subagent is forced to call a `StructuredOutput` tool instead of
   replying in prose; `agent()` then returns a validated JS object. Validation
   happens at the tool-call layer, so a bad shape is rejected and retried before
   the script sees it.
3. **Agent ↔ agent: the filesystem.** The script has no fs access, but subagents
   have Read/Write/Bash. For payloads too big to interpolate, agent A writes a
   file and the script passes only the path to agent B — keeping the payload out
   of every context.

## Verified by running it

The demo script confirmed each channel (run of 2026-07-27):

- Structured return: `{"codeword": "quiddity", "number": 7362}` arrived as an
  object, not text to parse.
- Interpolation: downstream agents used "quiddity"/7362 solely because a
  template literal put it in their prompt.
- **Isolation control:** an agent in the same run, asked to name the codeword
  with nothing interpolated, returned `NO_CHANNEL`. Same run, same orchestrator,
  zero visibility.
- Filesystem: an agent given only a path recovered `quiddity-7362` written by an
  earlier agent.

Resume economics, same 8 agents, after a two-line edit to the last stage:

| | first run | resume |
|---|---|---|
| subagent tokens | 141,180 | 35,266 |
| duration | 75s | 17s |

Unchanged agents replayed from the journal for free. This is the iteration
loop: edit the script file, resume with `resumeFromRunId`, pay only for what
changed.

## pipeline() vs parallel()

- `pipeline(items, ...stages)` — no barrier. Item A can be in stage 3 while item
  B is in stage 1. Wall-clock is the slowest *chain*. **This is the default.**
- `parallel(thunks)` — a barrier; awaits everything. Wall-clock is the sum of
  slowest-per-stage.

A barrier is correct only when a stage needs cross-item context: dedup across
the full result set, early-exit on zero total findings, or a prompt that
references the other items. It is *not* justified by needing to flatten/map/
filter between stages — do that inside a stage.

The tell: `parallel` → plain `flatMap` → `parallel`. That middle line has no
cross-item dependency, so the barrier buys nothing but latency.

Failure semantics differ. In `pipeline()`, a throwing stage drops that item to
`null` and skips its remaining stages; other items continue. In `parallel()`, a
failed thunk becomes `null` in the array and the call still resolves — it never
rejects. Either way, `.filter(Boolean)` before use.

## Undocumented API surface

The public docs cover the concept, saving, `args`, limits, and resume, and show
one skeleton with `meta`/`agent()`/`pipeline()`. As of 2026-07-27 the following
are **not** in the public docs — they come from the `Workflow` tool's own
description in the system prompt:

- `parallel()` barrier semantics, `log()`, `phase()`, `budget`
- The `(prevResult, originalItem, index)` stage-callback signature
- `isolation: 'worktree'`, `label`, `effort`, `agentType`, `model` opts
- `resumeFromRunId` / prefix-cache behavior
- **`Date.now()`, `Math.random()`, and argless `new Date()` throw** — they'd
  break resume's prefix matching. Pass timestamps via `args`; vary prompts by
  index for variation.
- **Plain JS, not TypeScript.** Type annotations, interfaces, and generics fail
  to parse.
- `meta` must be a pure literal — no variables, calls, spreads, or
  interpolation.

The workflows page points to "the Workflow tool entry in the Agent SDK
reference" for the full options; that entry could not be found there. The docs
index lists only two workflow-related pages.

The constraint that bites first when hand-writing a script — `Math.random()`
throwing — is documented nowhere you'd think to look.

## Gotchas hit for real

- **`args` arrives verbatim.** Pass actual JSON values, not a JSON-encoded
  string. Passing a string made `args.scratch` `undefined`, and the writer agent
  dutifully created `undefined/comms-demo-note.txt`. A stringified array reaches
  the script as one string, so `args.map(...)` throws.
- **Subagents don't validate intent.** The writer had a nonsense path and no
  reason to question it. Instructions are one-shot strings with no back-channel
  to ask "did you mean…?" — a wrong prompt gets executed confidently. That's the
  cost of the isolation that makes fan-out work.
- An agent still running when a workflow is stopped **isn't saved** and restarts
  on resume. Many small agents preserve more progress than one long one.
- Resume is session-scoped. Exit Claude Code and the next session starts fresh.

## Runtime limits

16 concurrent agents (fewer on limited cores), 1,000 agents total per run, no
direct filesystem or shell access from the script itself.

## Sources

- [Orchestrate subagents at scale with dynamic workflows](https://code.claude.com/docs/en/workflows)
- [Run agents in parallel](https://code.claude.com/docs/en/agents)
- [Tools reference](https://code.claude.com/docs/en/tools-reference)
