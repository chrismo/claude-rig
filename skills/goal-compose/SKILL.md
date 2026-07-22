---
name: goal-compose
description: "Compose a paste-ready autonomous-run trigger for Claude Code — route a rough intent to the right built-in mechanism (a self-verifying /goal loop, or a dynamic workflow that fans subagents out), and hand back the exact line to paste"
allowed-tools: Bash, Read, Grep, Glob
---

# goal-compose

Turn the user's rough intent into a paste-ready trigger for one of Claude Code's
**two built-in autonomous mechanisms**, and hand them the exact line to paste.

The two mechanisms solve different shapes of problem, so the skill's first job is
to **route** the intent to the right one:

- **`/goal <condition>`** — a single linear loop. One Claude takes turns until a
  blind evaluator judges the condition met. Best for a **single convergent finish
  line** ("make X true", verified by a check whose proof fits in a reply).
- **a dynamic workflow** ("use a workflow to …") — a JavaScript script the runtime
  runs in the background, orchestrating **many subagents**. Best when the task is
  **bigger than one context**, needs the **same step across many items**, or wants
  a **repeatable cross-checked quality pattern**.

Compose for whichever fits. Don't force a fan-out task into a `/goal` line or a
single convergent check into a workflow.

## Route first: `/goal` or a workflow?

Before composing anything, decide which mechanism fits. Ask the questions in
order; the first "yes" points you at a workflow.

- **Does the task repeat the same step across many items?** (audit every route,
  migrate 200 files, review every changed file.) → **workflow.** Fanning one
  subagent out per item is the whole point; cramming N items into one `/goal`
  breaks "one measurable end state" and blows the char cap.
- **Is the task bigger than one context can hold?** (a repo-wide sweep, a
  migration whose intermediate state is huge.) → **workflow.** Its intermediate
  results live in script variables, not a context window.
- **Does it want independent agents to cross-check each other, or the same
  question drafted from several angles?** (adversarially verify each finding, draft
  a hard plan three ways and weigh them.) → **workflow.** That repeatable quality
  pattern is what a workflow adds over just running more turns.
- **Otherwise: a single finish line, verified by a check whose proof fits in a
  reply?** → **`/goal`.** This is the common case — most "make X true and keep
  going until it is" intents.

Two more signals worth weighing:

- A **"keep fixing until the check passes"** loop can be *either*. If it's one
  check on one codebase (`tsc` clean, one bats suite green), `/goal` is simpler.
  If each round fans work out across many files or wants per-file isolation, it's
  a workflow.
- **Cost and sign-off.** A workflow spawns many agents and can use far more tokens
  than a `/goal` loop. And a workflow takes **no mid-run user input** — for a task
  that needs a human checkpoint between stages, either use `/goal` or split the
  workflow into per-stage runs. Flag the tradeoff when you recommend a workflow.

Whichever you pick, **state the routing decision and the one-line why** at the top
of your output, then compose using the matching section below:

- `/goal` → "Composing a `/goal` condition" (the default, detailed below).
- workflow → "Composing a workflow prompt".

If it's genuinely borderline, say so, recommend one, and offer the other in a line.

## Composing a `/goal` condition

### First, the thing that's easy to forget

`/goal` is a **built-in Claude Code command** (v2.1.139+). It is not this skill,
and Claude cannot trigger it — the user pastes `/goal <condition>`, and Claude
Code then keeps taking turns on its own until the condition is met:

- After each turn a **separate fast model (Haiku) evaluates** whether the
  condition is satisfied. If not, Claude continues automatically.
- The evaluator **only sees what was surfaced in the conversation.** It does
  **not** run commands, read files, or inspect the repo. If the proof isn't in
  Claude's visible output, the goal will never read as met — the work gets done
  and the loop stalls. This is the single most important thing to design around.
- One goal per session, **hard cap of 4,000 characters** — a longer condition is
  rejected with an error (not silently truncated), so an over-written condition
  fails outright.
- `/goal` alone shows status; `/goal clear` cancels.

**This skill's only output is a `/goal <condition>` line for the user to paste.**
Do not try to start the goal loop yourself — you can't.

### What a good condition must have

Because the evaluator is blind to everything but the transcript, build the
condition from four parts:

1. **One measurable end state** — a single, checkable finish line (tests green,
   build exits 0, file exists, queue empty). Not a vibe ("clean up the code").
2. **A stated check** — the exact command or observation that proves it
   (`npm test` exits 0, `git status` clean, `ls dist/app.js` succeeds).
3. **A surface-the-proof instruction** — tell Claude to **paste the evidence
   into its reply each turn** (the test summary, the exit code, the file
   listing). This is the part most people omit, and it's why goals stall: the
   work is done but the evaluator can't see it.
4. **A stop clause** — a turn cap or give-up condition so a stuck goal doesn't
   loop forever ("if not met after 15 turns, stop and summarize what's
   blocking").

Optional but often valuable: **constraints that must hold** ("without modifying
any other test file", "don't touch the public API").

**Keep it well under the 4,000-character cap.** A good condition is a few tight
sentences, not an essay. If a draft balloons toward the limit, that's the signal
the goal is doing too much — split it into chained goals (see anti-patterns).

### When a plan or spec is in play

Often the intent is already captured — a `spec.md`, a design doc, or a plan
Claude wrote earlier this session. Use it as the source of the finish line:

- **Reference the file by path in the condition** (`…per plan.md`) so the working
  Claude re-grounds itself each turn. How much you spell out depends on the plan:
  - If the plan's phase already defines its own crisp, checkable "done" (a
    "Phase 2 Goal" with a stated verification), keep the condition **short** —
    just point to it: "Complete the Phase 2 Goal in plan.md and paste the
    verification output it specifies." No need to re-spell what the plan already
    nails down.
  - If the phase's done criteria are vague, distill a concrete,
    transcript-checkable end state into the condition yourself. "Complete phase 2
    per plan.md" alone isn't verifiable; "phase 2 done — `npm test` green and the
    migration script exists, per plan.md" is.

  Either way, keep the **surface-the-proof** instruction: the evaluator can't
  open the plan, so it judges from the proof Claude pastes, not from the file.
- **A phased plan is not one goal.** Each phase is its own finish line, so it
  gets its own `/goal`, composed with all four parts and run in sequence: paste
  phase 1, let it clear, paste phase 2. Cramming a multi-phase plan into one
  condition breaks "one measurable end state" and bloats the cap.

## Composing a workflow prompt

A dynamic workflow is a script the runtime writes from a natural-language request
and runs in the background, orchestrating subagents. Like `/goal`, **Claude cannot
trigger it** — the user pastes a prompt that asks for one. So this skill's output
for the workflow route is also just a **line to paste**, not a script.

The trigger is a natural-language request that includes "use a workflow" (or the
keyword `ultracode`). The user then approves the planned phases before it runs.
The runtime does the fan-out; the paste line only has to describe the shape well.

A good workflow prompt names four things:

1. **The unit of work and how to discover it** — what to fan out over, and how the
   first agent finds the list ("every `.ts` file under `src/routes/`", "every file
   changed in this PR", "each component under `src/components/`").
2. **The per-item task** — the one thing done to each unit ("audit for missing auth
   checks", "migrate from styled-components to Tailwind").
3. **The quality/convergence pattern, if any** — the reason it's a workflow and not
   just a loop: "adversarially verify each finding before reporting", "merge the
   per-file findings into one ranked summary", "keep fixing until `tsc` passes or
   two rounds make no progress", "work on each file in its own isolated copy".
4. **The stopping/termination shape** — for a round-based loop, when to stop ("until
   the check passes or two rounds in a row make no progress", "stop once two rounds
   find nothing new"). Fan-out-once tasks terminate naturally when every item is done.

Unlike a `/goal` condition, a workflow prompt has **no character cap** and **no
blind evaluator** to design around — the subagents run real commands and read real
files, and their results live in the script, not the transcript. So the "surface
the proof in every reply" instruction that's load-bearing for `/goal` is *not*
needed here. Describe the work and the convergence; let the runtime orchestrate.

Match the shape to one of the canonical workflow forms:

- **Audit many files for one issue** — fan out one agent per file, collect, verify.
- **Migrate many files in parallel** — discover, transform each in isolation, verify.
- **Review every changed file → one summary** — reviewer per file, then a merge agent.
- **Keep fixing until a check passes** — run checker, fix, repeat until pass / no progress.
- **Research across many sources** — fan out readers, cross-check, synthesize.
- **Find issues until the list stops growing** — search in rounds, stop when a round adds nothing.

When it's a task the user will repeat (a review they run on every branch), tell
them they can **save the run afterward** as a `/<name>` command (in `/workflows`,
press `s`) so the orchestration is reusable.

## Process

1. **Get the intent.** Use the user's args as the rough goal. If they invoked
   this with nothing, or with something too vague to act on, ask 1–3
   sharp questions — focus on: *what's the finish line*, *how would you check it
   by hand*, and *what must NOT change*.

2. **Route.** Using "Route first", decide `/goal` vs workflow. This governs the
   rest: a `/goal` condition follows steps 3–6; a workflow prompt skips the
   `/goal`-only check-hunting detail (step 4) and is composed per "Composing a
   workflow prompt". State the decision + one-line why at the top of the output.

3. **Check for a plan or spec.** If the user linked a `.md`, or a plan/spec is
   already in the conversation, treat it as the source of the finish line(s) —
   see "When a plan or spec is in play". Note whether it's phased (each phase is
   its own `/goal`; a phase that's itself a fan-out may be its own workflow).

4. **Find the real check** *(`/goal` route)*. Don't guess the verification
   command — look. Inspect the repo for how things are actually verified here:
   - test runner / scripts (`package.json`, `Makefile`, `*.bats`,
     `pyproject.toml`, CI config)
   - build and lint commands
   - whatever the user named as their hand-check

   Prefer a command with an unambiguous exit code or a greppable summary line.
   Respect repo conventions found in `CLAUDE.md` (e.g. tests that must run with
   the sandbox disabled).

5. **Recommend a model.** Both mechanisms run on whatever model is active when the
   user pastes — a `/goal` loop uses the session model, and a workflow's subagents
   use the session model unless a stage routes elsewhere. Pick the right tier:
   - **Haiku 4.5** — mechanical tasks: formatting, boilerplate, trivial single-file
     edits where speed and cost matter more than reasoning depth
   - **Sonnet 4.6** — standard engineering: typical feature work, test fixes,
     moderate refactors
   - **Opus 4.8** — complex work: multi-file architectural changes, hard debugging,
     long-horizon agentic loops with many interdependent steps; Claude Code's
     default for autonomous coding runs at `xhigh` effort on Opus 4.8
   - **Fable 5** — ceiling problems: novel algorithm design, the hardest
     correctness or architectural problems, when Opus 4.8 is expected to struggle

   When unsure, lean toward Opus 4.8 for goal loops — it's optimized for
   long-horizon agentic execution. For a workflow, note that its many subagents
   multiply the per-token cost, so a cheaper tier can matter more. Include a
   one-line rationale and remind the user to switch before pasting:
   `/model <model-id>`.

6. **Draft the trigger.** For `/goal`: the condition(s) from the four parts above
   — one goal, or one goal per phase for a phased plan; keep each tight and
   imperative and bake in "show the output" explicitly. For a workflow: the
   "use a workflow to …" prompt from the four things above.

7. **Present it** in the matching output format below.

## Output format

Lead with the routing call in one line, then the matching block.

**`/goal` route:**

```
Routing: /goal — <one-line why>

## Paste this

/goal <the composed condition>

## Why it's shaped this way
- End state: <…>
- Check: <command/observation>
- Proof surfaced: <what Claude will paste each turn>
- Stop clause: <turn cap / give-up>
- Constraints: <or "none">
- Model: <recommended model + one-line rationale> — switch with `/model <model-id>` before pasting
```

**Workflow route:**

```
Routing: workflow — <one-line why (why not /goal)>

## Paste this

<the "use a workflow to …" prompt>

## Why it's shaped this way
- Unit of work: <what it fans out over + how discovered>
- Per-item task: <…>
- Quality/convergence: <cross-check / merge / keep-fixing shape, or "none — fan-out once">
- Termination: <round stop rule, or "when every item is done">
- Cost/sign-off note: <token multiplier; no mid-run input — checkpoint plan if needed>
- Model: <recommended model + one-line rationale> — switch with `/model <model-id>` before pasting
- Reusable: <"save afterward as /<name>", if the user will repeat it — else omit>
```

Keep the explanation to a few lines. The paste line is the product.

For a phased plan (a `/goal` per phase), present an **ordered sequence** instead —
one block per phase, with a note to run them one at a time (paste the next only
after the previous clears).

## Examples

### `/goal` route — rough intent → composed `/goal`

- *"get the auth tests passing"*
  → `/goal All tests under test/auth pass. After each change run \`npm test -- test/auth\` and paste the summary line (pass/fail counts) into your reply. Don't modify tests outside test/auth. If still failing after 15 turns, stop and summarize the remaining failures.`

- *"finish the changelog for this week"*
  → `/goal CHANGELOG.md has an entry for every PR merged in the last 7 days. Each turn, list the merged PRs you found (\`gh pr list --state merged --search "merged:>=<date>"\`) and which are still missing from CHANGELOG.md, then add them. Done when that missing list is empty — show the empty list. Stop after 10 turns if blocked.`

- *"make the bats suite green"* (repo-aware: honors CLAUDE.md)
  → `/goal \`bats hooks/use-dedicated-tools.bats\` exits 0 with zero failures. Run it each turn with the sandbox disabled (per CLAUDE.md) and paste the final tally. Don't weaken assertions to pass. If not green after 12 turns, stop and report what's failing.`

- *phased plan in `plan.md`* → one goal per phase, run in order:
  1. *(plan defines the Phase 1 goal+check, so point to it — short)*
     `/goal Complete the Phase 1 Goal in plan.md and paste the verification output it specifies each turn. Stop after 15 turns if blocked.`
  2. *(plan's Phase 2 done-criteria are vague, so distill them)*
     `/goal Phase 2 done per plan.md: the CLI wires the parser in and \`npm test\` is fully green. Paste the summary each turn. Don't touch the parser module. Stop after 15 turns if blocked.`
  (…paste each only after the previous clears.)

### Workflow route — rough intent → composed prompt

These are the same intents that *look* like a `/goal` but route to a workflow
because they fan out, sweep more than one context, or want cross-checking:

- *"check every route for missing auth"* (fan-out per file + verify → workflow,
  not one `/goal` cramming N routes into one condition)
  → `use a workflow to audit every route handler under src/routes/ for missing authentication checks, and adversarially verify each finding before reporting it`

- *"convert all the components to Tailwind"* (many files, isolation matters → workflow)
  → `use a workflow to migrate every component under src/components/ from styled-components to Tailwind, working on each file in its own isolated copy, and verify each result still renders`

- *"review this PR"* (per-file reviewers → one ranked summary → workflow)
  → `use a workflow to review every file changed in this PR for correctness issues, then merge the per-file findings into one ranked, deduplicated summary`

- *"get the type check clean"* (borderline — one check, but framed as rounds)
  → `use a workflow to run npx tsc --noEmit and keep fixing the reported errors until the type check passes or two rounds in a row make no progress` — *note: if the fixes are small and single-context, a `/goal` (`tsc` exits 0, paste the error count each turn, stop after N turns) is simpler; recommend that and offer the workflow.*

## Anti-patterns to steer the user away from

**Routing mistakes:**

- **Fan-out crammed into one `/goal`** — "audit all 40 routes and list every
  issue" is 40 units of work and multiple finish lines. Route it to a workflow.
- **A single convergent check turned into a workflow** — "make `npm test` pass"
  on one small codebase doesn't need subagent fan-out; a `/goal` is cheaper and
  simpler. Don't reach for a workflow just because it's fancier.
- **A workflow for something that needs a mid-run human checkpoint** — workflows
  take no mid-run input. If the user must approve between stages, use `/goal` or
  split into per-stage workflow runs.

**`/goal`-specific:**

- **Unmeasurable end states** — "improve performance", "make it robust". Pin it
  to a number or a passing check.
- **No proof in the transcript** — the work happens but Claude never prints the
  result, so the evaluator never sees completion. Always include "paste/show the
  output".
- **No stop clause** — an impossible or flaky condition loops until the user
  notices. Always cap turns.
- **Multiple finish lines in one goal** — "tests pass and docs updated and PR
  opened" is three conditions; the evaluator can't reason about partial credit.
  Pick the one that matters, or chain goals one at a time.
- **Blowing the 4,000-char cap** — stuffing step-by-step working instructions
  into the condition. The condition is a finish line, not a plan. If it's getting
  long, the detail belongs in the conversation, and the goal probably needs
  splitting.
